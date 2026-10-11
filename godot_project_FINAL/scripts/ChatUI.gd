extends CanvasLayer
# ChatUI.gd — Autoload (Singleton) اسمه "ChatUI"
# ملحوظة: لا يوجد class_name هنا عمداً — نفس سبب HUD.gd (تعارض الاسم مع الـ Autoload)
# مطابق لموقع 7.1 في الوثيقة: الشات أسفل يسار الشاشة، حقل الإدخال يظهر بالـ Enter

var _log_label: RichTextLabel
var _input_field: LineEdit
var _messages: Array = []
const MAX_VISIBLE_MESSAGES := 5


func _ready() -> void:
	layer = 60
	NetworkManager.chat_message_received.connect(_on_message_received)

	var container := PanelContainer.new()
	container.position = Vector2(10, 550)
	container.custom_minimum_size = Vector2(400, 150)
	container.modulate = Color(1, 1, 1, 0.85)
	add_child(container)

	var vbox := VBoxContainer.new()
	container.add_child(vbox)

	_log_label = RichTextLabel.new()
	_log_label.custom_minimum_size = Vector2(380, 110)
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	vbox.add_child(_log_label)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "اضغط Enter للكتابة..."
	_input_field.visible = false
	_input_field.text_submitted.connect(_on_text_submitted)
	vbox.add_child(_input_field)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not _input_field.visible:
		_input_field.visible = true
		_input_field.grab_focus()
		get_viewport().set_input_as_handled()


func _on_text_submitted(text: String) -> void:
	if text.strip_edges() != "":
		NetworkManager.send_chat_message(text.strip_edges())
		# لو في NPC قريب، بيرد على كلامك (عقل الـ NPC المحلي بدون AI)
		var brain := get_node_or_null("/root/Dialogue")
		if brain and brain.has_method("handle_player_chat"):
			brain.handle_player_chat(text.strip_edges())
	_input_field.text = ""
	_input_field.visible = false
	_input_field.release_focus()


func _on_message_received(username: String, message: String) -> void:
	_messages.append("[b]%s:[/b] %s" % [NetSecurity.escape_bbcode(username), NetSecurity.escape_bbcode(message)])
	if _messages.size() > MAX_VISIBLE_MESSAGES:
		_messages.pop_front()
	_log_label.text = "\n".join(_messages)
