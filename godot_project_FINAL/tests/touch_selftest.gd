extends SceneTree
# tests/touch_selftest.gd — تخطيط ومنطق التحكم باللمس (بدون جهاز):
#   godot --headless --path godot_project_FINAL --script res://tests/touch_selftest.gd

var passed: int = 0
var failed: int = 0
const SIZES := [Vector2(1280, 720), Vector2(1560, 720), Vector2(800, 480), Vector2(2340, 1080), Vector2(1920, 1080), Vector2(1080, 2340)]


func _initialize() -> void:
	_test_layout()
	_test_hit_test()
	_test_controls_logic()
	print("TOUCH SELFTEST: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _all_controls(layout: Dictionary) -> Array:
	var items: Array = [{"name": "joystick", "c": layout["joystick"]["center"], "r": layout["joystick"]["radius"]}]
	for k in ["attack", "jump", "run", "interact"]:
		items.append({"name": k, "c": layout["buttons"][k]["center"], "r": layout["buttons"][k]["radius"]})
	return items


func _test_layout() -> void:
	for size in SIZES:
		var layout: Dictionary = TouchLayout.compute(size)
		var items := _all_controls(layout)
		var margin := 8.0
		var min_dim := minf(size.x, size.y)
		for it in items:
			var c: Vector2 = it["c"]
			var r: float = it["r"]
			check(c.x - r >= margin and c.y - r >= margin and c.x + r <= size.x - margin and c.y + r <= size.y - margin, "%s: %s is inside the screen" % [str(size), it["name"]])
			check(r * 2.0 >= 0.11 * min_dim, "%s: %s is a big enough touch target" % [str(size), it["name"]])
		var overlap := false
		for i in items.size():
			for j in range(i + 1, items.size()):
				if (items[i]["c"] as Vector2).distance_to(items[j]["c"]) < float(items[i]["r"]) + float(items[j]["r"]):
					overlap = true
		check(not overlap, "%s: no controls overlap" % str(size))
		check((layout["joystick"]["center"] as Vector2).x < size.x * 0.4, "%s: joystick is on the left" % str(size))
		check((layout["buttons"]["attack"]["center"] as Vector2).x > size.x * 0.55, "%s: attack is on the right" % str(size))


func _test_hit_test() -> void:
	var layout: Dictionary = TouchLayout.compute(Vector2(1560, 720))
	var a: Vector2 = layout["buttons"]["attack"]["center"]
	check(TouchLayout.hit_test(layout, a) == "attack", "touching attack centre hits attack")
	check(TouchLayout.hit_test(layout, layout["buttons"]["jump"]["center"]) == "jump", "jump centre hits jump")
	check(TouchLayout.hit_test(layout, layout["buttons"]["run"]["center"]) == "run", "run centre hits run")
	check(TouchLayout.hit_test(layout, layout["buttons"]["interact"]["center"]) == "interact", "interact centre hits interact")
	check(TouchLayout.hit_test(layout, layout["joystick"]["center"]) == "joystick", "joystick centre hits joystick")
	check(TouchLayout.hit_test(layout, Vector2(780, 100)) == "", "empty screen area hits nothing")


func _test_controls_logic() -> void:
	var mc = load("res://scripts/MobileControls.gd").new()
	mc.enabled = true
	mc.configure(Vector2(1560, 720))
	var layout: Dictionary = mc.layout
	var j: Vector2 = layout["joystick"]["center"]
	var jr: float = layout["joystick"]["radius"]
	# جويستيك: سحب لليمين بنص القطر
	mc.handle_touch(0, j, true)
	mc.handle_drag(0, j + Vector2(jr * 0.5, 0))
	check(absf(mc.movement_vector.x - 0.5) < 0.05 and absf(mc.movement_vector.y) < 0.05, "half drag right gives about 0.5 on x")
	mc.handle_drag(0, j + Vector2(jr * 5.0, 0))
	check(mc.movement_vector.length() <= 1.001, "movement vector is clamped to length 1")
	mc.handle_drag(0, j + Vector2(jr * 0.05, 0))
	check(mc.movement_vector == Vector2.ZERO, "tiny drag is inside the dead zone")
	# لمس متعدد: الجويستيك ماسك + ضغط هجوم بصباع تاني
	mc.handle_drag(0, j + Vector2(jr * 0.9, 0))
	mc.handle_touch(1, layout["buttons"]["attack"]["center"], true)
	check(mc.attack_just_pressed, "attack registers while the joystick finger is down")
	check(mc.movement_vector.length() > 0.5, "joystick keeps working during the attack press")
	mc.consume_one_shot_inputs()
	check(not mc.attack_just_pressed, "attack is a one-shot input")
	mc.handle_touch(0, j, false)
	check(mc.movement_vector == Vector2.ZERO, "releasing the joystick stops movement")
	# الجري: بيفضل شغال لو الصباع زحف بره الزر، ويقف لما يترفع
	var rr: Vector2 = layout["buttons"]["run"]["center"]
	mc.handle_touch(2, rr, true)
	check(mc.run_held, "run is held while pressed")
	mc.handle_drag(2, rr + Vector2(500, -300))
	check(mc.run_held, "run stays held if the finger slides off the button")
	mc.handle_touch(2, rr + Vector2(500, -300), false)
	check(not mc.run_held, "run stops when that finger lifts")
	# قفز وتفاعل ضغطة واحدة
	mc.handle_touch(3, layout["buttons"]["jump"]["center"], true)
	check(mc.jump_just_pressed, "jump registers")
	mc.handle_touch(4, layout["buttons"]["interact"]["center"], true)
	check(mc.interact_just_pressed, "interact registers")
	# جويستيك ما يتفعّلش من لمسة بعيدة
	mc.handle_touch(5, Vector2(780, 60), true)
	mc.handle_drag(5, Vector2(900, 60))
	check(mc.movement_vector == Vector2.ZERO, "a touch far from the joystick does not move the player")
	# لو التحكم مش مفعّل (PC) ما يستجيبش
	var off = load("res://scripts/MobileControls.gd").new()
	off.configure(Vector2(1560, 720))
	off.handle_touch(0, off.layout["buttons"]["attack"]["center"], true)
	check(not off.attack_just_pressed, "disabled controls ignore touches (desktop)")
	mc.free()
	off.free()
