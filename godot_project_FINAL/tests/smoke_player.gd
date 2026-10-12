extends Node
# tests/smoke_player.gd — اختبار تكامل: اللاعب في المشهد الرئيسي بياخد شخصية Quaternius وحركاتها تتغيّر بالسرعة.
# بيشتغل كمشهد عادي (عشان الـ autoloads تكون موجودة):
#   godot --headless --path godot_project_FINAL res://tests/smoke_player.tscn

var passed: int = 0
var failed: int = 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _ready() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	var player: CharacterBody3D = main.get_node("Player")
	CharacterAssembly.assemble(player, "human", "female", "warrior", 7)
	await get_tree().process_frame
	var body := player.get_node_or_null("HumanBody")
	check(body != null, "player has a HumanBody after assembly")
	var ap: AnimationPlayer = QuaterniusCharacter.get_animation_player(body) if body else null
	check(ap != null and ap.has_animation("ual/Idle"), "body is the Quaternius character with UAL animations")
	if ap == null:
		_finish()
		return
	for i in 90:
		await get_tree().physics_frame
	check(player.is_on_floor(), "player lands on the ground")
	player.velocity = Vector3.ZERO
	player._update_animation(Vector2.ZERO, false)
	check(ap.current_animation == "ual/Idle", "standing -> Idle (got %s)" % ap.current_animation)
	player.velocity = Vector3(0, 0, 5)
	player._update_animation(Vector2(0, 1), false)
	check(ap.current_animation == "ual/Walk", "walking -> Walk (got %s)" % ap.current_animation)
	player.velocity = Vector3(0, 0, 8)
	player._update_animation(Vector2(0, 1), true)
	check(ap.current_animation == "ual/Jog_Fwd", "running -> Jog_Fwd (got %s)" % ap.current_animation)
	_finish()


func _finish() -> void:
	print("SMOKE PLAYER: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
