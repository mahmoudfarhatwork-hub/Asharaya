extends Node
# RemotePlayersManager.gd — Autoload (Singleton) اسمه "RemotePlayersManager"
# ملحوظة: لا يوجد class_name هنا عمداً — نفس سبب HUD.gd (تعارض الاسم مع الـ Autoload)
# بيبني ويحدّث تمثيل بصري بسيط (كبسولة + اسم) لكل لاعب تاني في نفس العالم
# مبني بالكود بالكامل — مفيش .tscn منفصل، تفادياً لأي خطأ تنسيق

var _remote_nodes: Dictionary = {}   # session/user id -> Node3D


func _ready() -> void:
	NetworkManager.world_state_updated.connect(_on_world_state_updated)
	NetworkManager.player_left.connect(_on_player_left)


func _on_world_state_updated(players: Dictionary) -> void:
	var my_user_id := NetworkManager.session.user_id if NetworkManager.session else NetworkManager.local_lan_id

	for session_id in players.keys():
		var data: Dictionary = players[session_id]
		if data.get("userId", "") == my_user_id:
			continue  # ده أنا نفسي، مش هعرض نسخة تانية مني

		if not _remote_nodes.has(session_id):
			_remote_nodes[session_id] = _create_remote_visual(data)

		var node: Node3D = _remote_nodes[session_id]
		var target_pos := Vector3(data.get("x", 0.0), data.get("y", 0.0), data.get("z", 0.0))
		# تحريك سلس بدل القفز المفاجئ بين التحديثات
		node.global_position = node.global_position.lerp(target_pos, 0.3)
		node.rotation.y = data.get("rotY", 0.0)

		var label: Label3D = node.get_node("Label")
		label.text = "%s\nLv.%d  ❤️%d/%d" % [data.get("username", "لاعب"), data.get("level", 1), data.get("hp", 100), data.get("maxHp", 100)]


func _create_remote_visual(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "RemotePlayer_%s" % data.get("userId", "")

	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	mesh_instance.mesh = capsule
	mesh_instance.position.y = 0.9
	root.add_child(mesh_instance)

	var label := Label3D.new()
	label.name = "Label"
	label.position.y = 2.2
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	get_tree().root.add_child(root)
	return root


func _on_player_left(user_id: String) -> void:
	for session_id in _remote_nodes.keys():
		var node: Node3D = _remote_nodes[session_id]
		if node.name == "RemotePlayer_%s" % user_id:
			node.queue_free()
			_remote_nodes.erase(session_id)
			return
