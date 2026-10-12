extends Node
# MobileControls.gd — Autoload. تحكم لمس (جويستيك + هجوم/قفز/جري/تفاعل) على الأندرويد بس.
# التخطيط من TouchLayout (نسبي لحجم الشاشة). المنطق (handle_touch/handle_drag) منفصل عن
# الرسم، فيتختبر على أي جهاز. على PC مش بيتفعّل خالص.

signal attack_pressed

const DEAD_ZONE := 0.12

var enabled: bool = false
var layout: Dictionary = {}

var movement_vector: Vector2 = Vector2.ZERO
var run_held: bool = false
var jump_just_pressed: bool = false
var interact_just_pressed: bool = false
var attack_just_pressed: bool = false

var _joystick_index: int = -1
var _run_index: int = -1
var _canvas: CanvasLayer
var _knob: TouchCircle


func is_mobile() -> bool:
	return OS.get_name() == "Android" or OS.get_name() == "iOS"


func _ready() -> void:
	if not is_mobile():
		return
	enabled = true
	set_process_input(true)
	_canvas = CanvasLayer.new()
	_canvas.layer = 100
	get_tree().root.call_deferred("add_child", _canvas)
	get_viewport().size_changed.connect(_on_viewport_resized)
	configure(get_viewport().get_visible_rect().size)


func _on_viewport_resized() -> void:
	configure(get_viewport().get_visible_rect().size)


# يحسب التخطيط لحجم الشاشة، ويعيد رسم الأزرار لو الواجهة شغالة
func configure(view_size: Vector2) -> void:
	layout = TouchLayout.compute(view_size)
	if _canvas != null:
		_rebuild_visuals()


func _rebuild_visuals() -> void:
	for child in _canvas.get_children():
		child.queue_free()
	var j: Dictionary = layout["joystick"]
	_add_circle(j["center"], j["radius"], Color(1, 1, 1, 0.18), "")
	_knob = _add_circle(j["center"], float(j["radius"]) * 0.5, Color(1, 1, 1, 0.38), "")
	var labels := {"attack": "ATK", "jump": "JUMP", "run": "RUN", "interact": "USE"}
	var colors := {
		"attack": Color(1, 0.25, 0.25, 0.45), "jump": Color(0.2, 0.6, 1, 0.45),
		"run": Color(1, 0.6, 0.2, 0.45), "interact": Color(0.2, 1, 0.4, 0.45),
	}
	for k in labels:
		var b: Dictionary = layout["buttons"][k]
		_add_circle(b["center"], b["radius"], colors[k], labels[k])


func _add_circle(center: Vector2, radius: float, color: Color, text: String) -> TouchCircle:
	var c := TouchCircle.new()
	c.position = center - Vector2(radius, radius)
	c.size = Vector2(radius * 2.0, radius * 2.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.circle_color = color
	c.label_text = text
	_canvas.add_child(c)
	return c


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		handle_drag(event.index, event.position)


func handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if not enabled or layout.is_empty():
		return
	if pressed:
		match TouchLayout.hit_test(layout, pos):
			"joystick":
				if _joystick_index == -1:
					_joystick_index = index
					_update_joystick(pos)
			"attack":
				attack_just_pressed = true
				attack_pressed.emit()
			"jump":
				jump_just_pressed = true
			"interact":
				interact_just_pressed = true
			"run":
				run_held = true
				_run_index = index
	else:
		if index == _joystick_index:
			_joystick_index = -1
			movement_vector = Vector2.ZERO
			_move_knob(layout["joystick"]["center"])
		if index == _run_index:
			_run_index = -1
			run_held = false


func handle_drag(index: int, pos: Vector2) -> void:
	if enabled and index == _joystick_index:
		_update_joystick(pos)


func _update_joystick(pos: Vector2) -> void:
	var c: Vector2 = layout["joystick"]["center"]
	var r: float = layout["joystick"]["radius"]
	var offset := (pos - c).limit_length(r)
	var v := offset / r
	movement_vector = v if v.length() >= DEAD_ZONE else Vector2.ZERO
	_move_knob(c + offset)


func _move_knob(center: Vector2) -> void:
	if _knob != null:
		_knob.position = center - _knob.size / 2.0


# يُستدعى من Player.gd في آخر كل فريم لتصفير الأزرار "ضغطة واحدة"
func consume_one_shot_inputs() -> void:
	jump_just_pressed = false
	interact_just_pressed = false
	attack_just_pressed = false
