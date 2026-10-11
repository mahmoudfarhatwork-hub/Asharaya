extends CharacterBody3D
# =====================================================================
# Asharaya — Player (تحكم أساسي، خفيف على المعالجة)
# =====================================================================
# ماشي: لوحة مفاتيح + عصا افتراضية للموبايل (Virtual Joystick لو موجودة
# في المشهد كـ Node باسم "VirtualJoystick"، اختياري — الكود بيتعامل
# مع غيابها من غير كراش).
# =====================================================================

const SPEED: float = 5.0
const SPRINT_SPEED: float = 8.0

# --- الحركة الديناميكية: تسارع/تباطؤ بدل قفزة فورية للسرعة القصوى ---
const GROUND_ACCEL: float = 14.0     # تسارع وأنت واقف على الأرض
const GROUND_FRICTION: float = 16.0  # تباطؤ لما تسيب الأزرار
const AIR_ACCEL: float = 6.0         # تحكم أقل في الهوا (طبيعي أكتر)

# --- القفزة: مش تقيلة، وفيها "hang time" بسيط زي ألعاب المنصات ---
const JUMP_VELOCITY: float = 6.2
const JUMP_GRAVITY_MULT: float = 1.0     # وانت طالع
const FALL_GRAVITY_MULT: float = 1.8     # وانت نازل (نزول أسرع = إحساس أخف مش تقيل)
const LOW_JUMP_GRAVITY_MULT: float = 2.6 # لو سبت الزرار بدري، تنزل بسرعة (قفزة متغيرة الارتفاع)
const COYOTE_TIME: float = 0.12          # تقدر تنط لحظة بسيطة بعد ما تسيب الحافة
const JUMP_BUFFER_TIME: float = 0.12     # لو دُست نط شوية قبل ما توصل الأرض، بينفّذ لما توصل

const MOUSE_SENSITIVITY: float = 0.0025

# --- حماية من السقوط اللانهائي خارج حدود العالم ---
const FALL_RESPAWN_Y: float = -25.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

var _joystick: Node = null
var _player_id: int = 1

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

var _spawn_position: Vector3
var _last_safe_position: Vector3

func _ready() -> void:
	_joystick = get_node_or_null("/root/Main/UI/VirtualJoystick")
	if OS.has_feature("mobile"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	_spawn_position = global_position
	_last_safe_position = global_position

	# نسجل نفسنا في أنظمة الأداء والعالم لو موجودة (autoload/singleton pattern)
	var chunk_streamer = get_node_or_null("/root/Main/World/ChunkStreamer")
	if chunk_streamer:
		chunk_streamer.register_player(_player_id, global_position)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# --- Coyote time: بنسجّل عداد لحظات بسيطة بعد الحافة نقدر نقفز فيها ---
	if on_floor:
		_coyote_timer = COYOTE_TIME
		_last_safe_position = global_position
	else:
		_coyote_timer = max(0.0, _coyote_timer - delta)

	# --- Jump buffer: تسجيل ضغطة النط حتى لو لسه ملمستش الأرض ---
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		_jump_buffer_timer = max(0.0, _jump_buffer_timer - delta)

	# --- الجاذبية المتغيرة: نزول أسرع من الصعود = إحساس أخف وأكثر حيوية ---
	if not on_floor:
		var g_mult := FALL_GRAVITY_MULT if velocity.y < 0 else JUMP_GRAVITY_MULT
		if velocity.y > 0 and not Input.is_action_pressed("jump"):
			g_mult = LOW_JUMP_GRAVITY_MULT
		velocity.y -= gravity * g_mult * delta
	elif velocity.y < 0:
		velocity.y = 0.0

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	var input_dir := Vector2.ZERO
	if _joystick and _joystick.has_method("get_vector"):
		input_dir = _joystick.get_vector()
	else:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else SPEED

	# --- تسارع/تباطؤ ناعم بدل قفزة فورية للسرعة القصوى (ده اللي بيدي إحساس "ديناميكي") ---
	var accel := (GROUND_ACCEL if on_floor else AIR_ACCEL) if direction else GROUND_FRICTION
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * speed, accel * delta * speed)
		velocity.z = move_toward(velocity.z, direction.z * speed, accel * delta * speed)
	else:
		velocity.x = move_toward(velocity.x, 0, accel * delta)
		velocity.z = move_toward(velocity.z, 0, accel * delta)

	move_and_slide()

	# --- الحماية من السقوط اللانهائي: لو نزل تحت حد معين يرجع لآخر مكان آمن ---
	if global_position.y < FALL_RESPAWN_Y:
		_respawn()

	# تحديث الموقع لأنظمة الـ Chunk Streaming و Ambient NPC كل فريم فيزيائي فقط
	# (مش كل فريم رسم) — يقلل حمل التحديث على أنظمة الخلفية
	var chunk_streamer = get_node_or_null("/root/Main/World/ChunkStreamer")
	if chunk_streamer:
		chunk_streamer.update_player_position(_player_id, global_position)

func _respawn() -> void:
	# نرجع لآخر نقطة كانت على الأرض بأمان، أو لنقطة البداية لو مفيش
	var target := _last_safe_position if _last_safe_position != Vector3.ZERO else _spawn_position
	velocity = Vector3.ZERO
	global_position = target + Vector3(0, 1.0, 0)
