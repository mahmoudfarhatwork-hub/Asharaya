extends SceneTree
# tests/character_selftest.gd — اختبار شخصيات Quaternius + حركات UAL:
#   godot --headless --path godot_project_FINAL --script res://tests/character_selftest.gd

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	check(QuaterniusCharacter.has_assets(), "Quaternius body and UAL files are present")
	for gender in ["male", "female"]:
		_test_build(gender)
	_test_animation_is_applied()
	_test_picker()
	_test_play_pick()
	print("CHARACTER SELFTEST: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _make(gender: String) -> Node3D:
	var holder := Node3D.new()
	get_root().add_child(holder)
	return QuaterniusCharacter.build(holder, gender, 42)


func _test_build(gender: String) -> void:
	var body: Node3D = _make(gender)
	check(body != null, "%s: body builds" % gender)
	if body == null:
		return
	var skel: Skeleton3D = QuaterniusCharacter.find_skeleton(body)
	check(skel != null and skel.get_bone_count() == 65, "%s: skeleton has 65 bones" % gender)
	var ap: AnimationPlayer = QuaterniusCharacter.get_animation_player(body)
	check(ap != null, "%s: has an AnimationPlayer" % gender)
	if ap == null:
		return
	for a in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump_Start", "Jump", "Jump_Land", "Sword_Idle", "Sword_Attack", "Hit_Chest", "Death01", "Interact", "Farm_Harvest", "TreeChopping", "Sword_Block"]:
		check(ap.has_animation("ual/" + a), "%s: animation %s exists" % [gender, a])
	for a in ["Idle", "Walk", "Jog_Fwd", "Sprint"]:
		check(ap.get_animation("ual/" + a).loop_mode == Animation.LOOP_LINEAR, "%s: %s loops" % [gender, a])
	check(ap.get_animation("ual/Sword_Attack").loop_mode == Animation.LOOP_NONE, "%s: Sword_Attack does not loop" % gender)
	# كل المسارات لازم تتحل على عظام/عقد حقيقية (مفيش track يتيم)
	var root: Node = ap.get_node(ap.root_node)
	var orphan := 0
	var anim: Animation = ap.get_animation("ual/Walk")
	for i in anim.get_track_count():
		if root.get_node_or_null(NodePath(str(anim.track_get_path(i)).get_slice(":", 0))) == null:
			orphan += 1
	check(orphan == 0, "%s: Walk has no orphan tracks (%d)" % [gender, orphan])


func _test_animation_is_applied() -> void:
	var body: Node3D = _make("male")
	var skel: Skeleton3D = QuaterniusCharacter.find_skeleton(body)
	var ap: AnimationPlayer = QuaterniusCharacter.get_animation_player(body)
	if skel == null or ap == null:
		check(false, "animation applied: needs skeleton and player")
		return
	var bone := skel.find_bone("thigh_l")
	check(bone >= 0, "thigh_l bone exists")
	ap.play("ual/Walk")
	ap.advance(0.0)
	var q0: Quaternion = skel.get_bone_pose_rotation(bone)
	ap.advance(0.4)
	var q1: Quaternion = skel.get_bone_pose_rotation(bone)
	check(q0.angle_to(q1) > 0.05, "Walk actually moves the thigh bone (angle %.3f)" % q0.angle_to(q1))


func _test_picker() -> void:
	var idle: Dictionary = QuaterniusCharacter.pick(0.0, false, false, true)
	check(idle["name"] == "Idle", "standing picks Idle")
	var walk: Dictionary = QuaterniusCharacter.pick(2.0, false, false, true)
	check(walk["name"] == "Walk", "slow forward picks Walk")
	var run: Dictionary = QuaterniusCharacter.pick(5.0, true, false, true)
	check(run["name"] == "Jog_Fwd", "running picks Jog_Fwd")
	var back: Dictionary = QuaterniusCharacter.pick(2.0, false, true, true)
	check(back["name"] == "Walk" and float(back["speed"]) < 0.0, "backward plays Walk in reverse")
	var air: Dictionary = QuaterniusCharacter.pick(2.0, false, false, false)
	check(air["name"] == "Jump", "airborne picks Jump")


func _test_play_pick() -> void:
	var body: Node3D = _make("male")
	var ap: AnimationPlayer = QuaterniusCharacter.get_animation_player(body)
	var key: String = QuaterniusCharacter.play_pick(ap, QuaterniusCharacter.pick(0.0, false, false, true), "")
	check(ap.current_animation == "ual/Idle", "play_pick starts Idle")
	ap.advance(0.3)
	var pos_before: float = ap.current_animation_position
	var key2: String = QuaterniusCharacter.play_pick(ap, QuaterniusCharacter.pick(0.0, false, false, true), key)
	check(key2 == key and ap.current_animation_position >= pos_before, "same animation is not restarted")
	var key3: String = QuaterniusCharacter.play_pick(ap, QuaterniusCharacter.pick(3.0, false, true, true), key2)
	check(ap.current_animation == "ual/Walk" and is_equal_approx(ap.get_playing_speed(), -1.0), "backward plays Walk at speed -1")
	check(key3 != key2, "changing animation changes the key")
