extends CanvasLayer
class_name ConnectionMenu
# ConnectionMenu.gd — أول شاشة بتظهر لما اللعبة تفتح
# يختار اللاعب: يلعب أوفلاين (بدون سيرفر خالص) أو أونلاين (يدخل IP سيرفر Oracle/مؤجر مؤقتاً)

signal mode_selected

var _ip_field: LineEdit
var _port_field: LineEdit
var _status_label: Label
var _lan_name_field: LineEdit
var _lan_ip_field: LineEdit
var _lan_status_label: Label
var _lan_hosts_box: VBoxContainer


func _ready() -> void:
	layer = 100
	_build_ui()
	NetworkManager.lan_hosts_updated.connect(_on_lan_hosts_updated)
	NetworkManager.start_lan_discovery()


func _exit_tree() -> void:
	NetworkManager.stop_lan_discovery()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 620)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 600)
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "⚔️ Asharaya"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "اختر طريقة اللعب"
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	# ── وضع أوفلاين ──
	var offline_btn := Button.new()
	offline_btn.text = "🔌 العب أوفلاين (بدون سيرفر)"
	offline_btn.custom_minimum_size = Vector2(0, 44)
	offline_btn.pressed.connect(_on_offline_pressed)
	vbox.add_child(offline_btn)

	var offline_note := Label.new()
	offline_note.text = "كل حاجة هتتحفظ على جهازك، مفيش لاعبين تانيين"
	offline_note.add_theme_font_size_override("font_size", 12)
	offline_note.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(offline_note)

	vbox.add_child(HSeparator.new())

	# ── وضع أونلاين ──
	var online_label := Label.new()
	online_label.text = "🌐 أونلاين — سيرفر Oracle / مستأجر"
	vbox.add_child(online_label)

	var ip_row := HBoxContainer.new()
	vbox.add_child(ip_row)

	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "عنوان IP السيرفر (مثال: 123.45.67.89)"
	_ip_field.text = GameConfig.server_host if GameConfig.server_host != "127.0.0.1" else ""
	_ip_field.custom_minimum_size = Vector2(260, 36)
	ip_row.add_child(_ip_field)

	_port_field = LineEdit.new()
	_port_field.placeholder_text = "المنفذ"
	_port_field.text = str(GameConfig.server_port)
	_port_field.custom_minimum_size = Vector2(80, 36)
	ip_row.add_child(_port_field)

	var online_btn := Button.new()
	online_btn.text = "الاتصال بالسيرفر والدخول"
	online_btn.custom_minimum_size = Vector2(0, 44)
	online_btn.pressed.connect(_on_online_pressed)
	vbox.add_child(online_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.modulate = Color(1, 0.6, 0.4)
	vbox.add_child(_status_label)

	var offline_default_note := Label.new()
	offline_default_note.text = "ملحوظة: لو السيرفر مش شغال أو الـ IP غلط، اللعبة هترجع أوفلاين تلقائياً"
	offline_default_note.add_theme_font_size_override("font_size", 11)
	offline_default_note.modulate = Color(0.6, 0.6, 0.6)
	offline_default_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(offline_default_note)

	# الأونلاين متقفل مؤقتًا (الحالي: أوفلاين + LAN فقط) — شوف GameConfig.ONLINE_ENABLED
	if not GameConfig.ONLINE_ENABLED:
		online_label.visible = false
		ip_row.visible = false
		online_btn.visible = false
		offline_default_note.visible = false

	vbox.add_child(HSeparator.new())

	# ── وضع الشبكة المحلية (LAN) — العب مع أصحابك على نفس الواي فاي ──
	var lan_label := Label.new()
	lan_label.text = "🖧 نفس الشبكة (LAN) — مع أصحابك بدون سيرفر"
	vbox.add_child(lan_label)

	_lan_name_field = LineEdit.new()
	_lan_name_field.placeholder_text = "اسمك في اللعبة"
	_lan_name_field.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(_lan_name_field)

	var host_btn := Button.new()
	host_btn.text = "🏠 استضف اللعبة (Host)"
	host_btn.custom_minimum_size = Vector2(0, 44)
	host_btn.pressed.connect(_on_lan_host_pressed)
	vbox.add_child(host_btn)

	var host_note := Label.new()
	host_note.text = "لازم تكونوا كلكم متوصّلين بنفس الشبكة (نفس الراوتر/واي فاي)"
	host_note.add_theme_font_size_override("font_size", 11)
	host_note.modulate = Color(0.6, 0.6, 0.6)
	host_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(host_note)

	var join_label := Label.new()
	join_label.text = "الألعاب المتاحة على شبكتك:"
	join_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(join_label)

	_lan_hosts_box = VBoxContainer.new()
	vbox.add_child(_lan_hosts_box)
	_render_lan_hosts([])

	var manual_row := HBoxContainer.new()
	vbox.add_child(manual_row)

	_lan_ip_field = LineEdit.new()
	_lan_ip_field.placeholder_text = "أو اكتب IP المضيف يدوي (مثال: 192.168.1.5)"
	_lan_ip_field.custom_minimum_size = Vector2(280, 36)
	manual_row.add_child(_lan_ip_field)

	var join_btn := Button.new()
	join_btn.text = "انضم"
	join_btn.custom_minimum_size = Vector2(70, 36)
	join_btn.pressed.connect(_on_lan_join_pressed)
	manual_row.add_child(join_btn)

	_lan_status_label = Label.new()
	_lan_status_label.text = ""
	_lan_status_label.modulate = Color(1, 0.6, 0.4)
	_lan_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_lan_status_label)


func _on_offline_pressed() -> void:
	GameConfig.set_offline_mode(true)
	NetworkManager.stop_lan_discovery()
	mode_selected.emit()
	queue_free()


func _on_online_pressed() -> void:
	var host := _ip_field.text.strip_edges()
	var port_text := _port_field.text.strip_edges()
	if host.is_empty():
		_status_label.text = "❌ اكتب عنوان IP السيرفر الأول"
		return
	var port := int(port_text) if port_text.is_valid_int() else 7350
	GameConfig.set_server(host, port, false, "defaultkey")
	NetworkManager.stop_lan_discovery()
	mode_selected.emit()
	queue_free()


func _on_lan_host_pressed() -> void:
	var username := _lan_name_field.text.strip_edges()
	NetworkManager.stop_lan_discovery()
	NetworkManager.start_lan_host(username)
	mode_selected.emit()
	queue_free()


func _on_lan_join_pressed() -> void:
	var ip := _lan_ip_field.text.strip_edges()
	if ip.is_empty():
		_lan_status_label.text = "❌ اختار لعبة من القائمة أو اكتب IP"
		return
	_join_lan(ip)


func _join_lan(ip: String) -> void:
	var username := _lan_name_field.text.strip_edges()
	_lan_status_label.text = "⏳ بيتصل بـ %s..." % ip
	await NetworkManager.start_lan_join(ip, username)
	if NetworkManager.is_lan:
		mode_selected.emit()
		queue_free()
	else:
		_lan_status_label.text = "❌ تعذر الاتصال — تأكدوا إنكم على نفس الشبكة"


func _on_lan_hosts_updated(hosts: Array) -> void:
	_render_lan_hosts(hosts)


func _render_lan_hosts(hosts: Array) -> void:
	for c in _lan_hosts_box.get_children():
		c.queue_free()

	if hosts.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(بندوّر... لسه مفيش ألعاب ظاهرة على الشبكة)"
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.modulate = Color(0.6, 0.6, 0.6)
		_lan_hosts_box.add_child(empty_label)
		return

	for h in hosts:
		var row_btn := Button.new()
		row_btn.text = "▶️ %s  (%s)" % [h.get("name", "مضيف"), h.get("ip", "")]
		row_btn.custom_minimum_size = Vector2(0, 38)
		row_btn.pressed.connect(_join_lan.bind(h.get("ip", "")))
		_lan_hosts_box.add_child(row_btn)
