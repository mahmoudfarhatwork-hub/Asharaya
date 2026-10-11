extends Node
class_name CombatSystem
# CombatSystem.gd — يُضاف كـ child node تحت اللاعب اسمه "CombatSystem"
# يستخدم Area3D أمام اللاعب لاكتشاف الأعداء وقت الهجوم

@export var attack_range: float = 2.0
@export var attack_cooldown: float = 0.6

var _can_attack: bool = true
@onready var player: CharacterBody3D = get_parent()
@onready var stats: PlayerStats = get_parent().get_node("PlayerStats")


func _ready() -> void:
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	# على PC: كليك شمال. على الموبايل: زر هجوم منفصل لازم تضيفه لـ MobileControls
	# (مسيبناه بسيط دلوقتي، لو عايز زر هجوم منفصل قولي وأضيفه لـ MobileControls.gd)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		attack()


func attack() -> void:
	if not _can_attack:
		return
	_can_attack = false
	get_tree().create_timer(attack_cooldown).timeout.connect(func(): _can_attack = true)

	var space_state := player.get_world_3d().direct_space_state
	var forward := -player.global_transform.basis.z
	var from := player.global_position + Vector3(0, 1, 0)
	var to := from + forward * attack_range

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var result := space_state.intersect_ray(query)

	if result and result.collider.has_method("take_damage"):
		var damage: int = stats.base_damage if stats else 10
		result.collider.take_damage(damage, player)
