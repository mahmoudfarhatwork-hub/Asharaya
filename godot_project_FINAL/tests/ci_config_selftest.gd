extends SceneTree
# tests/ci_config_selftest.gd — فحص إعدادات الـ CI والتصدير (بيمنع أخطاء زي tag صورة Docker غلط):
#   godot --headless --path godot_project_FINAL --script res://tests/ci_config_selftest.gd

var passed: int = 0
var failed: int = 0
const IMAGE := "barichello/godot-ci:4.7.2"   # الـ tag الموجود فعلاً على Docker Hub (مفيش -stable)


func _initialize() -> void:
	var wf_path := ProjectSettings.globalize_path("res://").path_join("../.github/workflows/build.yml").simplify_path()
	var wf := FileAccess.get_file_as_string(wf_path)
	check(wf != "", "workflow file is readable")
	var images := 0
	for line in wf.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("image:"):
			images += 1
			check(t == "image: " + IMAGE, "docker image tag is %s (got: %s)" % [IMAGE, t])
	check(images == 3, "all 3 jobs use the same image (found %d)" % images)
	check(wf.find("export_templates/4.7.2.stable") != -1, "export templates path matches Godot 4.7.2")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.find("gradle_build/use_gradle_build=false") != -1, "Android export does not need the gradle build template")
	check(presets.find("use_gradle_build=true") == -1, "no preset requires the gradle build template")
	check(presets.find('name="Android (Low-End)"') != -1 and wf.find('"Android (Low-End)"') != -1, "workflow exports the preset that exists")
	check(presets.find("architectures/arm64-v8a=true") != -1, "arm64-v8a is enabled (needed for modern phones)")
	print("CI CONFIG SELFTEST: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)
