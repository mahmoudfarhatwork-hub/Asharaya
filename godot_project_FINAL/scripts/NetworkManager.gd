extends Node
# NetworkManager.gd — Autoload (Singleton)
# كل اتصال اللعبة بالسيرفر بيمر من هنا: دخول، حركة، إحصائيات، شات، حفظ/تحميل بيانات
#
# ✅ يشتغل في وضعين بشفافية تامة لباقي اللعبة (نفس الدوال، نفس الإشارات):
#   1) ONLINE  — Nakama حقيقي (لوكال، أو سيرفر Oracle/مؤجر عن طريق GameConfig)
#   2) OFFLINE — بدون أي سيرفر، كل حاجة بتتحفظ في ملف محلي على الجهاز (user://)
#      وميزات المالتيبلير (اللاعبين التانيين، الشات) بتتقفل تلقائياً بهدوء

const OP_MOVE = 2
const OP_STATE_UPDATE = 3
const OP_STATS = 5

const CHAT_ROOM_NAME = "asharaya_global"
const LOCAL_SAVE_PATH := "user://offline_save.json"

const LAN_PORT := 8910
const LAN_DISCOVERY_PORT := 8911
const LAN_MAX_PLAYERS := 8

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket
var current_match_id: String = ""
var chat_channel_id: String = ""

var is_offline: bool = false
var is_lan: bool = false
var local_lan_id: String = ""
var local_lan_username: String = ""
var _local_data: Dictionary = {}   # {"player_progress:character": {...}, "player_progress:stats": {...}, ...}

# ── حالة الشبكة المحلية (LAN) ──
var lan_peer: ENetMultiplayerPeer
var _lan_players: Dictionary = {}   # "lan_<peer_id>" -> {x,y,z,rotY,hp,maxHp,level,userId,username}
var _my_lan_state: Dictionary = {"x": 0.0, "y": 0.0, "z": 0.0, "rotY": 0.0, "hp": 0, "maxHp": 0, "level": 1}

var _beacon_peer: PacketPeerUDP
var _beacon_timer: float = 0.0
var _discovery_listener: PacketPeerUDP
var _discovery_active: bool = false
var _discovered_hosts: Dictionary = {}   # ip -> {"name": String, "last_seen": float}

signal connected_to_server
signal login_failed(reason: String)
signal player_joined(user_id: String)
signal player_left(user_id: String)
signal world_state_updated(players: Dictionary)   # مواقع وإحصائيات اللاعبين (فاضية دايماً في أوفلاين)
signal chat_message_received(username: String, message: String)
signal lan_hosts_updated(hosts: Array)   # [{"ip": "...", "name": "..."}]


func _ready() -> void:
	pass  # الاتصال الفعلي بيحصل في login_and_join_world، مش هنا


func _process(delta: float) -> void:
	if _beacon_peer:
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			_beacon_timer = 1.5
			var msg := JSON.stringify({"game": "asharaya", "name": local_lan_username})
			_beacon_peer.put_packet(msg.to_utf8_buffer())

	if _discovery_active and _discovery_listener:
		var changed := false
		while _discovery_listener.get_available_packet_count() > 0:
			var pkt := _discovery_listener.get_packet()
			var ip := _discovery_listener.get_packet_ip()
			var parsed = JSON.parse_string(pkt.get_string_from_utf8())
			if parsed is Dictionary and parsed.get("game") == "asharaya":
				if not _discovered_hosts.has(ip):
					changed = true
				_discovered_hosts[ip] = {"name": parsed.get("name", "مضيف"), "last_seen": Time.get_ticks_msec() / 1000.0}
		var now := Time.get_ticks_msec() / 1000.0
		for ip in _discovered_hosts.keys().duplicate():
			if now - _discovered_hosts[ip]["last_seen"] > 4.0:
				_discovered_hosts.erase(ip)
				changed = true
		if changed:
			var arr: Array = []
			for ip in _discovered_hosts:
				arr.append({"ip": ip, "name": _discovered_hosts[ip]["name"]})
			lan_hosts_updated.emit(arr)


func login_and_join_world() -> void:
	if is_lan:
		return  # الاتصال بالشبكة المحلية بيحصل مباشرة من ConnectionMenu (start_lan_host/join)، مش هنا
	if GameConfig.offline_mode:
		_start_offline()
		return

	var ok := await _try_connect_online()
	if not ok:
		# فشل الاتصال بالسيرفر (مش شغال، أو معزول، أو IP غلط) -> يرجع أوفلاين تلقائياً
		# بدل ما يوقف اللعبة بالكامل. اللاعب يقدر يرجع أونلاين لاحقاً من الإعدادات.
		push_warning("⚠️ تعذر الاتصال بالسيرفر (%s:%d) — رجعنا للوضع أوفلاين مؤقتاً" % [GameConfig.server_host, GameConfig.server_port])
		_start_offline()


# ── محاولة الاتصال الحقيقي بسيرفر Nakama (لوكال أو مؤجر) ──
func _try_connect_online() -> bool:
	client = Nakama.create_client(
		GameConfig.server_key,
		GameConfig.server_host,
		GameConfig.server_port,
		"https" if GameConfig.server_use_ssl else "http"
	)

	# Nakama client الافتراضي بيستخدم HTTP timeout داخلي (~ثواني قليلة) — لو السيرفر
	# مقفول أو الـ IP غلط، authenticate_device_async هترجع exception بدل ما تعلّق للأبد
	var device_id := _get_or_create_device_id()
	session = await client.authenticate_device_async(device_id)

	if session == null or session.is_exception():
		login_failed.emit(str(session))
		return false

	socket = Nakama.create_socket_from(client)
	var connected: NakamaAsyncResult = await socket.connect_async(session)
	if connected.is_exception():
		login_failed.emit(str(connected))
		return false

	socket.received_match_state.connect(_on_match_state)
	socket.received_match_presence.connect(_on_match_presence)
	socket.received_channel_message.connect(_on_channel_message)

	var rpc_result: NakamaAPI.ApiRpc = await client.rpc_async(session, "find_or_create_world", "")
	if rpc_result.is_exception():
		login_failed.emit(str(rpc_result))
		return false

	var payload: Dictionary = JSON.parse_string(rpc_result.payload)
	current_match_id = payload["match_id"]

	var joined_match: NakamaRTAPI.Match = await socket.join_match_async(current_match_id)
	if joined_match.is_exception():
		login_failed.emit(str(joined_match))
		return false

	var joined_chat: NakamaRTAPI.Channel = await socket.join_chat_async(CHAT_ROOM_NAME, NakamaSocket.ChannelType.Room, true, false)
	if not joined_chat.is_exception():
		chat_channel_id = joined_chat.id

	is_offline = false
	print("✅ دخلت العالم أونلاين: ", current_match_id, " — سيرفر: ", GameConfig.server_host)
	connected_to_server.emit()
	return true


# ── الوضع الأوفلاين: بدون أي سيرفر، كل حاجة محلية ──
func _start_offline() -> void:
	is_offline = true
	_load_local_file()
	print("🔌 اللعبة شغالة أوفلاين (بدون سيرفر) — البيانات بتتحفظ على الجهاز")
	# نأجل الإشارة لفريم واحد عشان أي كود بيستنى await يلاقي سلوك متوقع بنفس الشكل
	call_deferred("emit_signal", "connected_to_server")


# ── شبكة محلية (LAN): تستضيف اللعبة على جهازك، وأصحابك يدخلوا بنفس الـ IP على نفس الواي فاي ──
func start_lan_host(username: String = "") -> void:
	lan_peer = ENetMultiplayerPeer.new()
	var err := lan_peer.create_server(LAN_PORT, LAN_MAX_PLAYERS)
	if err != OK:
		login_failed.emit("تعذر فتح سيرفر الشبكة المحلية (البورت %d مشغول؟)" % LAN_PORT)
		return

	var mp := get_tree().get_multiplayer()
	mp.multiplayer_peer = lan_peer
	is_lan = true
	is_offline = false
	local_lan_id = "lan_%d" % mp.get_unique_id()   # المضيف دايماً peer id = 1
	local_lan_username = username if username != "" else "المُضيف"
	_load_local_file()

	mp.peer_connected.connect(_on_lan_peer_connected)
	mp.peer_disconnected.connect(_on_lan_peer_disconnected)

	_start_lan_beacon()
	print("🖧 فتحت سيرفر شبكة محلية على البورت %d — استنى أصحابك يدخلوا" % LAN_PORT)
	call_deferred("emit_signal", "connected_to_server")


func start_lan_join(ip: String, username: String = "") -> void:
	stop_lan_discovery()
	lan_peer = ENetMultiplayerPeer.new()
	var err := lan_peer.create_client(ip, LAN_PORT)
	if err != OK:
		login_failed.emit("عنوان IP غير صالح: %s" % ip)
		return

	var mp := get_tree().get_multiplayer()
	mp.multiplayer_peer = lan_peer

	var ok := await _await_lan_connection()
	if not ok:
		login_failed.emit("تعذر الاتصال بـ %s — تأكدوا إنكم على نفس الشبكة واللعبة فاتحة عند المضيف" % ip)
		mp.multiplayer_peer = null
		lan_peer = null
		return

	is_lan = true
	is_offline = false
	local_lan_id = "lan_%d" % mp.get_unique_id()
	local_lan_username = username if username != "" else "لاعب_%d" % mp.get_unique_id()
	_load_local_file()

	mp.peer_connected.connect(_on_lan_peer_connected)
	mp.peer_disconnected.connect(_on_lan_peer_disconnected)

	print("🖧 اتصلت بشبكة محلية عند %s" % ip)
	connected_to_server.emit()


func _await_lan_connection() -> bool:
	var elapsed := 0.0
	while elapsed < 6.0:
		var status := lan_peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			return true
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return false
		await get_tree().create_timer(0.15).timeout
		elapsed += 0.15
	return false


func _on_lan_peer_connected(id: int) -> void:
	player_joined.emit("lan_%d" % id)


func _on_lan_peer_disconnected(id: int) -> void:
	var uid := "lan_%d" % id
	_lan_players.erase(uid)
	player_left.emit(uid)
	world_state_updated.emit(_lan_players)


func disconnect_lan() -> void:
	stop_lan_discovery()
	_stop_lan_beacon()
	if lan_peer:
		get_tree().get_multiplayer().multiplayer_peer = null
		lan_peer = null
	is_lan = false
	_lan_players.clear()


# ── اكتشاف تلقائي لأي لعبة مفتوحة على نفس الشبكة (بث UDP بسيط) ──
func start_lan_discovery() -> void:
	if _discovery_listener == null:
		_discovery_listener = PacketPeerUDP.new()
		var err := _discovery_listener.bind(LAN_DISCOVERY_PORT)
		if err != OK:
			_discovery_listener = null
			return
	_discovered_hosts.clear()
	_discovery_active = true


func stop_lan_discovery() -> void:
	_discovery_active = false
	if _discovery_listener:
		_discovery_listener.close()
		_discovery_listener = null


func _start_lan_beacon() -> void:
	_beacon_peer = PacketPeerUDP.new()
	_beacon_peer.set_broadcast_enabled(true)
	_beacon_peer.set_dest_address("255.255.255.255", LAN_DISCOVERY_PORT)
	_beacon_timer = 0.0


func _stop_lan_beacon() -> void:
	_beacon_peer = null


# ── مزامنة الحركة والإحصائيات بين اللاعبين على الشبكة المحلية ──
@rpc("any_peer", "call_local", "unreliable_ordered")
func _rpc_lan_state(_claimed_uid: String, username: String, data: Dictionary) -> void:
	# الهوية من رقم المُرسِل الفعلي، مش من اللي بيدّعيه اللاعب (منع الانتحال)
	var uid := NetSecurity.lan_uid(_lan_sender_id())
	if uid == "":
		return
	var clean := NetSecurity.sanitize_lan_state(data)
	clean["userId"] = uid
	clean["username"] = NetSecurity.sanitize_username(username)
	_lan_players[uid] = clean
	world_state_updated.emit(_lan_players)


# رقم المُرسِل في RPC الحالي (0 معناها استدعاء محلي call_local فنستخدم رقمنا)
func _lan_sender_id() -> int:
	var sid := multiplayer.get_remote_sender_id()
	if sid == 0:
		sid = multiplayer.get_unique_id()
	return sid


func _lan_broadcast_state() -> void:
	if not is_lan or lan_peer == null:
		return
	if lan_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_rpc_lan_state.rpc(local_lan_id, local_lan_username, _my_lan_state.duplicate())


@rpc("any_peer", "call_local", "reliable")
func _rpc_lan_chat(username: String, text: String) -> void:
	if NetSecurity.lan_uid(_lan_sender_id()) == "":
		return
	var clean_text := NetSecurity.sanitize_chat(text)
	if clean_text == "":
		return
	chat_message_received.emit(NetSecurity.sanitize_username(username), clean_text)


# ── الحركة ──
func send_position(pos: Vector3, rot_y: float) -> void:
	if is_lan:
		_my_lan_state["x"] = pos.x
		_my_lan_state["y"] = pos.y
		_my_lan_state["z"] = pos.z
		_my_lan_state["rotY"] = rot_y
		_lan_broadcast_state()
		return
	if is_offline:
		return  # مفيش لاعبين تانيين يشوفوها في أوفلاين
	if socket == null or current_match_id == "":
		return
	var data := {"x": pos.x, "y": pos.y, "z": pos.z, "rotY": rot_y}
	socket.send_match_state_async(current_match_id, OP_MOVE, JSON.stringify(data))


# ── الإحصائيات المبثوثة لباقي اللاعبين ──
func send_stats(hp: int, max_hp: int, level: int) -> void:
	if is_lan:
		_my_lan_state["hp"] = hp
		_my_lan_state["maxHp"] = max_hp
		_my_lan_state["level"] = level
		_lan_broadcast_state()
		return
	if is_offline:
		return
	if socket == null or current_match_id == "":
		return
	var data := {"hp": hp, "maxHp": max_hp, "level": level}
	socket.send_match_state_async(current_match_id, OP_STATS, JSON.stringify(data))


# ── الشات ──
func send_chat_message(text: String) -> void:
	if is_lan:
		if lan_peer and lan_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_rpc_lan_chat.rpc(local_lan_username, text)
		return
	if is_offline:
		chat_message_received.emit("أنت (أوفلاين)", text)  # صدى محلي بسيط، مفيش شات حقيقي بدون سيرفر
		return
	if socket == null or chat_channel_id == "":
		return
	socket.write_chat_message_async(chat_channel_id, {"message": text})


func _on_channel_message(message: NakamaAPI.ApiChannelMessage) -> void:
	var content: Dictionary = JSON.parse_string(message.content)
	chat_message_received.emit(message.username, content.get("message", ""))


# ── حفظ/تحميل بيانات اللاعب — نفس الواجهة أونلاين وأوفلاين ──
func save_player_data(collection: String, key: String, data: Dictionary) -> void:
	if is_offline or session == null:
		_local_data["%s:%s" % [collection, key]] = data
		_save_local_file()
		return
	var write := NakamaWriteStorageObject.new(collection, key, 1, 1, JSON.stringify(data), "")
	await client.write_storage_objects_async(session, [write])


func load_player_data(collection: String, key: String, default_value: Dictionary) -> Dictionary:
	if is_offline or session == null:
		return _local_data.get("%s:%s" % [collection, key], default_value)
	var ids := NakamaStorageObjectId.new(collection, key, session.user_id)
	var result: NakamaAPI.ApiStorageObjects = await client.read_storage_objects_async(session, [ids])
	if result.is_exception() or result.objects.size() == 0:
		return default_value
	return JSON.parse_string(result.objects[0].value)


func _on_match_state(state: NakamaRTAPI.MatchData) -> void:
	if state.op_code == OP_STATE_UPDATE:
		var data: Dictionary = JSON.parse_string(state.data)
		world_state_updated.emit(data.get("players", {}))


func _on_match_presence(presence: NakamaRTAPI.MatchPresenceEvent) -> void:
	for p in presence.joins:
		player_joined.emit(p.user_id)
	for p in presence.leaves:
		player_left.emit(p.user_id)


func _get_or_create_device_id() -> String:
	var path := "user://device_id.txt"
	if FileAccess.file_exists(path):
		var existing := FileAccess.open(path, FileAccess.READ).get_as_text().strip_edges()
		# المعرّفات القديمة (player_<وقت>) قابلة للتخمين، فبتتجدّد تلقائياً
		if NetSecurity.is_strong_device_id(existing):
			return existing
	var new_id := NetSecurity.make_device_id()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(new_id)
	return new_id


# ── تخزين محلي بسيط لوضع الأوفلاين (ملف JSON واحد على جهاز اللاعب) ──
func _load_local_file() -> void:
	if not FileAccess.file_exists(LOCAL_SAVE_PATH):
		_local_data = {}
		return
	var f := FileAccess.open(LOCAL_SAVE_PATH, FileAccess.READ)
	var text := f.get_as_text()
	var parsed = JSON.parse_string(text)
	_local_data = parsed if parsed is Dictionary else {}


func _save_local_file() -> void:
	var f := FileAccess.open(LOCAL_SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(_local_data))
