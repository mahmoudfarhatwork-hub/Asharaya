extends CharacterBody3D
class_name Monster
# Monster.gd — نسخة عامة من نفس منطق Slime.gd، تشتغل مع أي موديل حقيقي
# من الـ21 وحش الموجودين في assets/monsters/، كل وحش بإحصائياته الخاصة

@export var monster_id: String = "chicken"
@export var max_hp: int = 20
@export var damage: int = 3
@export var xp_reward: int = 8
@export var coin_reward_min: int = 1
@export var coin_reward_max: int = 2
@export var detection_range: float = 5.0
@export var move_speed: float = 1.5
@export var attack_range: float = 1.3
@export var attack_cooldown: float = 1.5
@export var respawn_seconds: float = 40.0
@export var is_passive: bool = false   # الحيوانات الأليفة (دجاج/خنزير/غزال) مش بتهاجم

# إحصائيات الحياة البرية المناسبة لمنطقة البداية — منخفضة الخطورة
const WILDLIFE_STATS := {
	"chicken": {"hp": 10, "damage": 0, "xp": 3, "coins": [1, 1], "passive": true},
	"pig":     {"hp": 18, "damage": 2, "xp": 5, "coins": [1, 2], "passive": true},
	"deer":    {"hp": 22, "damage": 0, "xp": 6, "coins": [1, 2], "passive": true},
	"bee":     {"hp": 8,  "damage": 4, "xp": 4, "coins": [1, 1], "passive": false},
	"bat":     {"hp": 15, "damage": 5, "xp": 7, "coins": [1, 2], "passive": false},
	"mushroom":{"hp": 12, "damage": 3, "xp": 5, "coins": [1, 2], "passive": false},
	"crab":    {"hp": 20, "damage": 4, "xp": 8, "coins": [2, 3], "passive": false},
}

var hp: int
var _target: Node3D = null
var _can_attack: bool = true
var _spawn_position: Vector3

const GRAVITY := 9.8


static func create(monster_id: String, position: Vector3) -> Monster:
	# فابريكة: بتبني Monster جاهز بموديله الحقيقي وإحصائياته الصح، ديمو-واحد-كول
	var model_path := "res://assets/monsters/%s/model.gltf" % monster_id
	var monster := Monster.new()
	monster.monster_id = monster_id

	var stats: Dictionary = WILDLIFE_STATS.get(monster_id, {"hp": 15, "damage": 3, "xp": 5, "coins": [1, 2], "passive": false})
	monster.max_hp = stats["hp"]
	monster.damage = stats["damage"]
	monster.xp_reward = stats["xp"]
	monster.coin_reward_min = stats["coins"][0]
	monster.coin_reward_max = stats["coins"][1]
	monster.is_passive = stats["passive"]

	monster.position = position

	# الشكل المرئي (الموديل الحقيقي)
	if ResourceLoader.exists(model_path):
		var scene: PackedScene = load(model_path)
		var visual: Node3D = scene.instantiate()
		visual.name = "Visual"
		monster.add_child(visual)

	# تصادم بسيط كبسولي حوالين الوحش
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 1.2
	col.shape = shape
	col.position.y = 0.6
	monster.add_child(col)

	return monster


func _ready() -> void:
	hp = max_hp
	_spawn_position = global_position


func _physics_process(delta: float) -> void:
	if is_passive:
		return  # الحيوانات الأليفة بتقف مكانها بس (ممكن تتصاد أو تترّوض)

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
		# مكافأة العملات دايماً حديدية (أقل عملة) في منطقة البداية
		CurrencySystem.add_iron_value(randi_range(coin_reward_min, coin_reward_max))
		var qs = attacker.get_node_or_null("QuestSystem")
		if qs and qs.has_method("report_event"):
			qs.report_event("kill", monster_id)
		var brain := get_node_or_null("/root/Dialogue")
		if brain and brain.has_method("add_world_fact") and not is_passive and randf() < 0.35:
			brain.add_world_fact("حد قدر يقتل %s قرب الغابة" % monster_id, 1.0)

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
