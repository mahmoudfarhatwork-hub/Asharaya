extends SceneTree
# tests/combat_selftest.gd — اختيار هدف الضربة (اتجاه + مدى + زاوية):
#   godot --headless --path godot_project_FINAL --script res://tests/combat_selftest.gd

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	_test_facing()
	_test_pick()
	print("COMBAT SELFTEST: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _test_facing() -> void:
	# اللاعب بيلف بـ atan2(x, z) فبيبص ناحية +Z المحلي (مش -Z)
	check(MeleeTargeting.facing_of(Basis.IDENTITY).is_equal_approx(Vector3(0, 0, 1)), "default facing is +Z")
	var turned := Basis(Vector3.UP, atan2(1.0, 0.0))
	check(MeleeTargeting.facing_of(turned).is_equal_approx(Vector3(1, 0, 0)), "after turning toward +X the player faces +X")


func _test_pick() -> void:
	var o := Vector3.ZERO
	var f := Vector3(0, 0, 1)
	check(MeleeTargeting.pick(o, f, [Vector3(0, 0, 1.5)], 2.0, 60.0) == 0, "enemy in front within range is picked")
	check(MeleeTargeting.pick(o, f, [Vector3(0, 0, -1.5)], 2.0, 60.0) == -1, "enemy behind is not picked")
	check(MeleeTargeting.pick(o, f, [Vector3(0, 0, 3.0)], 2.0, 60.0) == -1, "enemy out of range is not picked")
	check(MeleeTargeting.pick(o, f, [Vector3(1.5, 0, 0.2)], 2.0, 60.0) == -1, "enemy at the side (outside the arc) is not picked")
	check(MeleeTargeting.pick(o, f, [Vector3(1.0, 0, 1.0)], 2.0, 60.0) == 0, "enemy at 45 degrees inside the arc is picked")
	check(MeleeTargeting.pick(o, f, [Vector3(0, 0, 1.8), Vector3(0, 0, 0.8)], 2.0, 60.0) == 1, "the nearest enemy wins")
	check(MeleeTargeting.pick(o, f, [Vector3(0, 5, 1.0)], 2.0, 60.0) == -1, "enemy far above is not picked")
	check(MeleeTargeting.pick(o, f, [], 2.0, 60.0) == -1, "no enemies gives -1")
	check(MeleeTargeting.pick(o, f, [Vector3(0, 0, 0)], 2.0, 60.0) == 0, "enemy at the same spot is picked")
