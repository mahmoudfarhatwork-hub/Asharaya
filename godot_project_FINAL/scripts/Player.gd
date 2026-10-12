extends CharacterBody3D
# Player.gd — حركة موحدة تشتغل بالكيبورد على PC وباللمس على Android تلقائياً
# مفيش حاجة تتغير بين المنصتين — نفس الملف، نفس المشروع، تصدير مختلف بس

const WALK_SPEED := 5.0
const RUN_MULTIPLIER := 1.6
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8

const SEND_INTERVAL := 0.1
var _send_timer := 0.0

# لو فيه PlayerStats (V2+) هيتلاقى تلقائي ويتستخدم لضبط الجري بالستامينا
@onready var stats: Node = get_node_or_null("PlayerStats")


func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_send_position_to_server(delta)
	_send_stats_to_server(delta)

	if MobileControls.is_mobile():
		MobileControls.consume_one_shot_inputs()


func _get_movement_input() -> Vector2:
	if MobileControls.is_mobile():
		return MobileControls.movement_vector
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _is_jump_pressed() -> bool:
	if MobileControls.is_mobile():
		return MobileControls.jump_just_pressed
	return Input.is_action_just_pressed("jump")


func _is_run_held() -> bool:
	if MobileControls.is_mobile():
		return MobileControls.run_held
	return Input.is_action_pressed("run")


func _is_interact_pressed() -> bool:
	if MobileControls.is_mobile():
		return MobileControls.interact_just_pressed
	return Input.is_action_just_pressed("interact")


func _handle_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if _is_jump_pressed() and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := _get_movement_input()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var can_run := true
	var base_speed := WALK_SPEED
	if stats != null and stats.has_method("can_run"):
		can_run = stats.can_run()
	if stats != null and "move_speed" in stats:
		base_speed = stats.move_speed  # بيراعي فروق السرعة بين الأعراق/المهن (V6)

	var is_running := _is_run_held() and can_run
	var speed := base_speed * (RUN_MULTIPLIER if is_running else 1.0)

	if stats != null and stats.has_method("notify_running"):
		stats.notify_running(is_running and direction.length() > 0.1)

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		var target_rot := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	_update_animation(input_dir, is_running)

	move_and_slide()

	if _is_interact_pressed():
		_try_interact()


func _try_interact() -> void:
	for trader in get_tree().get_nodes_in_group("traders"):
		trader.try_open_shop_for(self)


func _send_position_to_server(delta: float) -> void:
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		NetworkManager.send_position(global_position, rotation.y)


func _send_stats_to_server(_delta: float) -> void:
	if stats != null and stats.has_method("get_hp_data"):
		var d: Dictionary = stats.get_hp_data()
		NetworkManager.send_stats(d.hp, d.max_hp, d.level)


# ربط حركات Mixamo بحالة اللاعب
var _anim_player: AnimationPlayer = null
var _anim_searched := false
var _current_anim_key := ""


func _update_animation(input_dir: Vector2, is_running: bool) -> void:
	# بنعيد البحث لو الجسم لسه ما اتركّبش أو اتبدّل (التركيب بيحصل بعد إنشاء الشخصية، مش وقت تحميل المشهد)
	if _anim_player == null or not is_instance_valid(_anim_player):
		var body := get_node_or_null("HumanBody")
		_anim_player = _find_anim_player(body) if body else null
		_current_anim_key = ""
	if _anim_player == null:
		return
	# حركات UAL (Quaternius): Idle / Walk / Jog / Jump بدل حركات Mixamo المؤقتة
	if _anim_player.has_animation("ual/Idle"):
		var picked := QuaterniusCharacter.pick(Vector2(velocity.x, velocity.z).length(), is_running, input_dir.y < -0.1, is_on_floor())
		_current_anim_key = QuaterniusCharacter.play_pick(_anim_player, picked, _current_anim_key)
		return
	var key := "reload"
	if input_dir.y < -0.1:
		key = "walk_backward"
	elif input_dir.y > 0.1:
		key = "strut_walk" if is_running else "catwalk_walk"
	elif input_dir.length() > 0.1:
		key = "strut_walk"
	if key != _current_anim_key:
		_current_anim_key = key
		if _anim_player.has_animation("mixamo/%s" % key):
			_anim_player.play("mixamo/%s" % key)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f := _find_anim_player(c)
		if f:
			return f
	return null
