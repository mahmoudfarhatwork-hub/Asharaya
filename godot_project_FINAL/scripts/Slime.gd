extends CharacterBody3D
class_name Slime
# Slime.gd — حسب جدول الـ Bestiary بالظبط:
# HP:30, ضرر:5, XP:15, عملات:1-2 حديدية, يهاجم عند الاقتراب لمسافة 5م, بطيء جداً

@export var max_hp: int = 30
@export var damage: int = 5
@export var xp_reward: int = 15
@export var coin_reward_min: int = 1
@export var coin_reward_max: int = 2
@export var detection_range: float = 5.0
@export var move_speed: float = 1.2   # "بطيء جداً" حسب الوصف
@export var attack_range: float = 1.2
@export var attack_cooldown: float = 1.5
@export var respawn_seconds: float = 30.0   # افتراض معقول — الوثيقة مذكرتش زمن respawn محدد

var hp: int
var _target: Node3D = null
var _can_attack: bool = true
var _spawn_position: Vector3

const GRAVITY := 9.8


func _ready() -> void:
	add_to_group("monsters")
	hp = max_hp
	_spawn_position = global_position


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	_find_target()

	if _target:
		var dist := global_position.distance_to(_target.global_position)
		if dist <= attack_range:
			velocity.x = 0
			velocity.z = 0
			_try_attack()
		elif dist <= detection_range:
			var dir := (_target.global_position - global_position)
			dir.y = 0
			dir = dir.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
		else:
			velocity.x = 0
			velocity.z = 0
	else:
		velocity.x = 0
		velocity.z = 0

	move_and_slide()


func _find_target() -> void:
	# بسيط: بيدور على أقرب لاعب في نطاق اللعبة. لو عندك مجموعة "players" في الـ groups استخدمها
	var players := get_tree().get_nodes_in_group("players")
	var closest: Node3D = null
	var closest_dist := INF
	for p in players:
		var d := global_position.distance_to(p.global_position)
		if d < closest_dist and d <= detection_range:
			closest = p
			closest_dist = d
	_target = closest


func _try_attack() -> void:
	if not _can_attack or _target == null:
		return
	_can_attack = false
	get_tree().create_timer(attack_cooldown).timeout.connect(func(): _can_attack = true)

	if _target.has_node("PlayerStats"):
		_target.get_node("PlayerStats").take_damage(damage)


func take_damage(amount: int, attacker: Node = null) -> void:
	hp -= amount
	if hp <= 0:
		_die(attacker)


func _die(attacker: Node) -> void:
	if attacker and attacker.has_node("PlayerStats"):
		var stats: PlayerStats = attacker.get_node("PlayerStats")
		stats.gain_xp(xp_reward)
		stats.add_coins(randi_range(coin_reward_min, coin_reward_max), 0)

	# اختفاء + إعادة ظهور بعد فترة (نمط بسيط لمشروع V2؛ عدّله لو عايز نظام spawn أكبر)
	visible = false
	set_physics_process(false)
	set_collision_layer_value(1, false)
	get_tree().create_timer(respawn_seconds).timeout.connect(_respawn)


func _respawn() -> void:
	hp = max_hp
	global_position = _spawn_position
	visible = true
	set_physics_process(true)
	set_collision_layer_value(1, true)
