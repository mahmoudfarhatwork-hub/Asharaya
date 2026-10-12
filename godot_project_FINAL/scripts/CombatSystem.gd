extends Node
class_name CombatSystem
# CombatSystem.gd — يُضاف كـ child node تحت اللاعب اسمه "CombatSystem"
# يستخدم Area3D أمام اللاعب لاكتشاف الأعداء وقت الهجوم

@export var attack_range: float = 2.5
@export var attack_cooldown: float = 0.6
@export var attack_half_arc_deg: float = 60.0   # نص زاوية الضربة قدّام اللاعب

var _can_attack: bool = true
@onready var player: CharacterBody3D = get_parent()
@onready var stats: PlayerStats = get_parent().get_node("PlayerStats")


func _ready() -> void:
	set_process_unhandled_input(true)
	# زر الهجوم على الموبايل (signal عشان ما يتأثرش بترتيب الفريم)
	MobileControls.attack_pressed.connect(attack)


func _unhandled_input(event: InputEvent) -> void:
	# PC: كليك شمال. الموبايل: زر ATK من MobileControls
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		attack()


func attack() -> void:
	if not _can_attack:
		return
	_can_attack = false
	get_tree().create_timer(attack_cooldown).timeout.connect(func(): _can_attack = true)

	if player.has_method("play_action"):
		player.play_action("Sword_Attack")

	var origin := player.global_position
	var facing := MeleeTargeting.facing_of(player.global_transform.basis)
	var nodes: Array = []
	var positions: Array = []
	for n in get_tree().get_nodes_in_group("monsters"):
		if n is Node3D and n.has_method("take_damage"):
			nodes.append(n)
			positions.append((n as Node3D).global_position)
	var idx := MeleeTargeting.pick(origin, facing, positions, attack_range, attack_half_arc_deg)
	if idx < 0:
		return
	var target: Node3D = nodes[idx]
	var to_target := target.global_position - origin
	to_target.y = 0.0
	if to_target.length() > 0.01:
		player.rotation.y = atan2(to_target.x, to_target.z)   # يلف ناحية الهدف (مهم باللمس)
	var damage: int = stats.base_damage if stats else 10
	target.take_damage(damage, player)
