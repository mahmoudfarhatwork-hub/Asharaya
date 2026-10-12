extends SceneTree
# tests/project_config_selftest.gd — إعدادات لازم تكون صح عشان بناء الأندرويد ينجح ويشتغل صح:
#   godot --headless --path godot_project_FINAL --script res://tests/project_config_selftest.gd

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	check(bool(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false)), "ETC2/ASTC texture import is enabled (required for Android export)")
	var orient: Variant = ProjectSettings.get_setting("display/window/handheld/orientation", 1)
	check(typeof(orient) == TYPE_INT and int(orient) == 0, "orientation is landscape (int 0)")
	check(str(ProjectSettings.get_setting("application/config/name", "")) == "Asharaya", "project name is Asharaya")
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features", PackedStringArray())
	check("4.7" in features, "project feature tag is 4.7")
	print("PROJECT CONFIG SELFTEST: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)
