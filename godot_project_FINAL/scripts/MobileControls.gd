extends Node
# MobileControls.gd — Autoload (Singleton)
# بيبني واجهة تحكم لمس (جويستيك + أزرار) بالكود بالكامل — مفيش ملف .tscn منفصل
# مطلوب عشان الـ .tscn لو اتكتب يدوي فيه خطر يبوظ لو الصيغة غلط، والكود أضمن 100%
#
# بيظهر تلقائي بس لو اللعبة شغالة على Android. على PC مش هيظهر خالص.

var movement_vector: Vector2 = Vector2.ZERO
var run_held: bool = false
var jump_just_pressed: bool = false
var interact_just_pressed: bool = false

var _joystick_touch_index: int = -1
var _joystick_base_pos: Vector2
var _joystick_knob_pos: Vector2
const JOYSTICK_RADIUS := 80.0

var _canvas: CanvasLayer
var _joystick_base_visual: Control
var _joystick_knob_visual: Control
var _jump_button_rect: Rect2
var _run_button_rect: Rect2
var _interact_button_rect: Rect2


func is_mobile() -> bool:
	return OS.get_name() == "Android" or OS.get_name() == "iOS"


func _ready() -> void:
	if not is_mobile():
		return  # على PC، السكريبت ده منفعلش خالص، الكيبورد والماوس هما اللي شغالين

	_build_ui()
	set_process_input(true)


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 100
	get_tree().root.call_deferred("add_child", _canvas)

	var screen_size := DisplayServer.screen_get_size()

	# قاعدة الجويستيك (يسار الشاشة تحت)
	_joystick_base_pos = Vector2(150, screen_size.y - 150)
	_joystick_knob_pos = _joystick_base_pos

	_joystick_base_visual = _make_circle(_joystick_base_pos, JOYSTICK_RADIUS, Color(1, 1, 1, 0.2))
	_joystick_knob_visual = _make_circle(_joystick_knob_pos, JOYSTICK_RADIUS * 0.5, Color(1, 1, 1, 0.4))
	_canvas.call_deferred("add_child", _joystick_base_visual)
	_canvas.call_deferred("add_child", _joystick_knob_visual)

	# أزرار يمين الشاشة: تفاعل، جري، قفز
	var jump_pos := Vector2(screen_size.x - 120, screen_size.y - 220)
	var run_pos := Vector2(screen_size.x - 220, screen_size.y - 140)
	var interact_pos := Vector2(screen_size.x - 120, screen_size.y - 380)

	_jump_button_rect = Rect2(jump_pos - Vector2(45, 45), Vector2(90, 90))
	_run_button_rect = Rect2(run_pos - Vector2(45, 45), Vector2(90, 90))
	_interact_button_rect = Rect2(interact_pos - Vector2(40, 40), Vector2(80, 80))

	_canvas.call_deferred("add_child", _make_circle(jump_pos, 45, Color(0.2, 0.6, 1, 0.5), "QFZ"))
	_canvas.call_deferred("add_child", _make_circle(run_pos, 45, Color(1, 0.6, 0.2, 0.5), "جري"))
	_canvas.call_deferred("add_child", _make_circle(interact_pos, 40, Color(0.2, 1, 0.4, 0.5), "E"))


func _make_circle(pos: Vector2, radius: float, color: Color, label_text: String = "") -> Control:
	var c := Control.new()
	c.position = pos - Vector2(radius, radius)
	c.size = Vector2(radius * 2, radius * 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var draw_script := GDScript.new()
	draw_script.source_code = """
extends Control
@export var circle_color: Color
func _draw() -> void:
	draw_circle(size / 2, size.x / 2, circle_color)
"""
	draw_script.reload()
	c.set_script(draw_script)
	c.set("circle_color", color)

	if label_text != "":
		var lbl := Label.new()
		lbl.text = label_text
		lbl.position = Vector2(radius * 0.5, radius * 0.7)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		c.add_child(lbl)

	return c


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if pos.distance_to(_joystick_base_pos) <= JOYSTICK_RADIUS * 1.5 and _joystick_touch_index == -1:
				_joystick_touch_index = event.index
			elif _jump_button_rect.has_point(pos):
				jump_just_pressed = true
			elif _interact_button_rect.has_point(pos):
				interact_just_pressed = true
			elif _run_button_rect.has_point(pos):
				run_held = true
		else:
			if event.index == _joystick_touch_index:
				_joystick_touch_index = -1
				movement_vector = Vector2.ZERO
				_joystick_knob_pos = _joystick_base_pos
				if _joystick_knob_visual:
					_joystick_knob_visual.position = _joystick_knob_pos - Vector2(JOYSTICK_RADIUS * 0.5, JOYSTICK_RADIUS * 0.5)
			if _run_button_rect.has_point(pos):
				run_held = false

	elif event is InputEventScreenDrag:
		if event.index == _joystick_touch_index:
			var offset: Vector2 = event.position - _joystick_base_pos
			offset = offset.limit_length(JOYSTICK_RADIUS)
			movement_vector = offset / JOYSTICK_RADIUS
			_joystick_knob_pos = _joystick_base_pos + offset
			if _joystick_knob_visual:
				_joystick_knob_visual.position = _joystick_knob_pos - Vector2(JOYSTICK_RADIUS * 0.5, JOYSTICK_RADIUS * 0.5)


# يُستدعى من Player.gd في نهاية كل فريم عشان يصفّر الأزرار اللي "ضغطة واحدة" (jump/interact)
func consume_one_shot_inputs() -> void:
	jump_just_pressed = false
	interact_just_pressed = false
