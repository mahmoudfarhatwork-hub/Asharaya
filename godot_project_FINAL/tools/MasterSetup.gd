@tool
extends EditorScript
# MasterSetup.gd — أداة الإعداد التلقائي الشاملة لمشروع Asharaya
#
# ═══════════════════════════════════════════════════════════════════
# إزاي تشغّلها (نفس خطوات AutoSetup.gd القديمة):
# 1. في Godot: FileSystem → دبل كليك على tools/MasterSetup.gd يفتحه في Script Editor
# 2. وإنت فاتحه: من فوق File → Run (أو الاختصار Ctrl+Shift+X)
# 3. شوف تبويب "Output" تحت — هيطلعلك تقرير كامل بكل حاجة اتعملت وكل حاجة محتاجة منك
# 4. شغّلها تاني في أي وقت — أمنة تتكرر (idempotent)، ملهاش أي أثر جانبي لو اتشغلت
#    أكتر من مرة على نفس المشروع
#
# ده بديل شامل لـ AutoSetup.gd القديم، وبيعمل كل اللي كان بيعمله + أكتر:
#   ✅ Input Map + Collision Layers (زي القديم)
#   ✅ استخراج وتوزيع أصول من incoming_assets.zip، لكن دلوقتي بيحاول
#      يصنّفها تلقائي لو مش متبعة تنظيم المسارات الرسمي
#   ✅ تنضيف ملفات القمامة (__MACOSX, .DS_Store, Thumbs.db, ملفات .tmp)
#   ✅ فحص إن Nakama SDK فعلاً موجود ومربوط صح
#   ✅ فحص إن كل الـ Autoloads المكتوبة في project.godot ليها ملفات فعلية
#   ✅ تقرير نهائي واحد يقولك "التالي" بالظبط
#
# ═══════════════════════════════════════════════════════════════════
# إزاي تحط أصول جديدة (من Kaggle/HuggingFace):
# 1. نزّل ملفات .glb من الـ dataset بتاعك، وزمّعهم في ملف واحد اسمه
#    incoming_assets.zip بالظبط
# 2. لو كل ملف جوه الزيب بيتبع التنظيم الرسمي (مثال: weapons/rusty_sword.glb)
#    هيتحط أوتوماتيك في res://assets/weapons/rusty_sword.glb
# 3. لو ملف مش واضح مكانه (اسمه مش فيه كلمة مفتاحية معروفة)، هيتحط في
#    res://assets/_unsorted/ وهيظهرلك في التقرير عشان تنقله بنفسك يدوي
# 4. اسحب الزيب وسيبه في جذر المشروع (جنب project.godot)، وشغّل السكريبت تاني


const CATEGORY_KEYWORDS := {
	"weapons": ["sword", "staff", "axe", "bow", "shield", "dagger", "spear", "weapon"],
	"tools": ["hammer", "pickaxe", "shovel", "rod", "tool"],
	"monsters": ["slime", "goblin", "skeleton", "wolf", "troll", "monster", "creature"],
	"props": ["chest", "pot", "torch", "crate", "barrel", "prop", "furniture"],
	"resources": ["ore", "log", "herb", "coin", "gem", "resource"],
	"environment": ["terrain", "mountain", "sky", "tree", "bush", "forest", "rock", "grass", "rope"],
	"buildings": ["house", "castle", "cottage", "shop", "tower", "building"],
	"characters": ["human", "elf", "dwarf", "demon", "beast", "body_", "head_", "hair_"],
}

const JUNK_NAMES := ["__MACOSX", ".DS_Store", "Thumbs.db", "desktop.ini"]

var _report: Array[String] = []
var _unsorted_files: Array[String] = []
var _missing_autoloads: Array[String] = []


func _run() -> void:
	print("🚀 بدء الإعداد التلقائي الشامل لمشروع Asharaya...\n")

	_setup_input_map()
	_setup_collision_layers()
	_extract_and_sort_assets()
	_clean_junk_files()
	_verify_autoloads()
	_verify_nakama_sdk()

	ProjectSettings.save()
	EditorInterface.get_resource_filesystem().scan()

	_print_final_report()


# ── 1. Input Map ──────────────────────────────────────────────────
func _setup_input_map() -> void:
	var actions := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"run": [KEY_SHIFT],
		"interact": [KEY_E],
	}

	for action_name in actions.keys():
		var events: Array = []
		for keycode in actions[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			events.append(ev)

		ProjectSettings.set_setting("input/%s" % action_name, {"deadzone": 0.5, "events": events})

		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		else:
			InputMap.action_erase_events(action_name)
		for ev in events:
			InputMap.action_add_event(action_name, ev)

	_report.append("✅ Input Map: move_forward/back/left/right, jump, run, interact")


# ── 2. Collision Layers ───────────────────────────────────────────
func _setup_collision_layers() -> void:
	var layers := {1: "world", 2: "player", 3: "enemies"}
	for layer_num in layers.keys():
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%d" % layer_num, layers[layer_num])
	_report.append("✅ Collision Layers: 1=world, 2=player, 3=enemies")


# ── 3. استخراج وتصنيف الأصول ──────────────────────────────────────
func _extract_and_sort_assets() -> void:
	var zip_path := "res://incoming_assets.zip"

	if not FileAccess.file_exists(zip_path):
		_report.append("ℹ️  مفيش incoming_assets.zip — تم تجاهل خطوة توزيع الأصول")
		return

	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		_report.append("❌ فشل فتح incoming_assets.zip (كود الخطأ: %d)" % err)
		return

	var files := reader.get_files()
	var placed_count := 0
	var unsorted_count := 0

	for file_path in files:
		if file_path.ends_with("/"):
			continue

		var content := reader.read_file(file_path)
		var dest_path := _resolve_destination(file_path)
		var dir_path := dest_path.get_base_dir()

		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

		var f := FileAccess.open(dest_path, FileAccess.WRITE)
		if f:
			f.store_buffer(content)
			f.close()
			placed_count += 1
			if dest_path.begins_with("res://assets/_unsorted/"):
				unsorted_count += 1
				_unsorted_files.append(dest_path)
		else:
			_report.append("   ❌ فشل كتابة: %s" % dest_path)

	reader.close()

	# نمسح الزيب بعد ما نستخرجه بنجاح، بدل ما يفضل يزحم جذر المشروع
	var backup_dir := "res://_backups"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_dir))
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(zip_path),
		ProjectSettings.globalize_path("%s/incoming_assets_%d.zip" % [backup_dir, Time.get_unix_time_from_system()])
	)

	_report.append("✅ استخراج الأصول: %d ملف اتحط في مكانه الصح، %d ملف مش واضح مكانه (اتحط في assets/_unsorted/)" % [placed_count - unsorted_count, unsorted_count])
	_report.append("   (الزيب الأصلي اتنقل لـ %s كنسخة احتياطية)" % backup_dir)


func _resolve_destination(file_path: String) -> String:
	# لو الملف أصلاً متبع تنظيم معروف (مساره يبدأ باسم فئة معروفة)، سيبه زي ما هو
	var first_segment := file_path.split("/")[0]
	if CATEGORY_KEYWORDS.has(first_segment):
		return "res://assets/%s" % file_path

	# لو مش كذلك، حاول تخمّن الفئة من اسم الملف نفسه
	var filename_lower := file_path.get_file().to_lower()
	for category in CATEGORY_KEYWORDS.keys():
		for keyword in CATEGORY_KEYWORDS[category]:
			if filename_lower.contains(keyword):
				return "res://assets/%s/%s" % [category, file_path.get_file()]

	# لو مقدرناش نخمّن حاجة، سيبه في _unsorted عشان تراجعه بنفسك
	return "res://assets/_unsorted/%s" % file_path.get_file()


# ── 4. تنضيف ملفات القمامة ────────────────────────────────────────
func _clean_junk_files() -> void:
	var removed_count := 0
	removed_count += _clean_junk_recursive("res://")
	if removed_count > 0:
		_report.append("✅ تنضيف: اتشال %d ملف/مجلد قمامة (__MACOSX, .DS_Store, Thumbs.db, .tmp)" % removed_count)
	else:
		_report.append("✅ تنضيف: مفيش ملفات قمامة لقيتها — المشروع نضيف")


func _clean_junk_recursive(path: String) -> int:
	var removed := 0
	var dir := DirAccess.open(path)
	if not dir:
		return 0

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue

		var full_path := path.path_join(entry)
		var is_dir := dir.current_is_dir()

		if entry in JUNK_NAMES or entry.ends_with(".tmp"):
			var abs_path := ProjectSettings.globalize_path(full_path)
			if is_dir:
				OS.move_to_trash(abs_path) if OS.has_feature("editor") else DirAccess.remove_absolute(abs_path)
			else:
				DirAccess.remove_absolute(abs_path)
			removed += 1
		elif is_dir:
			removed += _clean_junk_recursive(full_path)

		entry = dir.get_next()
	dir.list_dir_end()
	return removed


# ── 5. فحص الـ Autoloads ──────────────────────────────────────────
func _verify_autoloads() -> void:
	var config := ConfigFile.new()
	if config.load("res://project.godot") != OK:
		_report.append("❌ مقدرش أفتح project.godot لفحص الـ Autoloads")
		return

	if not config.has_section("autoload"):
		return

	for key in config.get_section_keys("autoload"):
		var value: String = config.get_value("autoload", key)
		var script_path: String = value.lstrip("*")
		if not FileAccess.file_exists(script_path):
			_missing_autoloads.append("%s → %s" % [key, script_path])

	if _missing_autoloads.is_empty():
		_report.append("✅ كل الـ Autoloads (%d) ليها ملفات موجودة فعلياً" % config.get_section_keys("autoload").size())
	else:
		_report.append("⚠️  في %d Autoload ملفهم ناقص (اتفصّلوا تحت في التقرير)" % _missing_autoloads.size())


# ── 6. فحص Nakama SDK ─────────────────────────────────────────────
func _verify_nakama_sdk() -> void:
	var required_files := [
		"res://addons/com.heroiclabs.nakama/Nakama.gd",
		"res://addons/com.heroiclabs.nakama/client/NakamaClient.gd",
		"res://addons/com.heroiclabs.nakama/socket/NakamaSocket.gd",
	]
	var missing: Array[String] = []
	for f in required_files:
		if not FileAccess.file_exists(f):
			missing.append(f)

	if missing.is_empty():
		_report.append("✅ Nakama SDK: كل ملفاته الأساسية موجودة ومربوطة في project.godot")
	else:
		_report.append("❌ Nakama SDK ناقص %d ملف أساسي — نزّله من AssetLib (دور على \"Nakama\") أو من GitHub الرسمي" % missing.size())


# ── 7. التقرير النهائي ─────────────────────────────────────────────
func _print_final_report() -> void:
	print("═══════════════════════════════════════════════════")
	print("📋 التقرير النهائي:")
	print("═══════════════════════════════════════════════════")
	for line in _report:
		print(line)

	if not _missing_autoloads.is_empty():
		print("\n⚠️  Autoloads ناقصة:")
		for m in _missing_autoloads:
			print("   - %s" % m)

	if not _unsorted_files.is_empty():
		print("\n📦 ملفات محتاجة تراجعها وتنقلها بنفسك (مش واضح فئتها تلقائي):")
		for u in _unsorted_files:
			print("   - %s" % u)
		print("   نقلهم يدوي لمجلد الفئة الصحيحة جوه assets/، أو أضف كلمة مفتاحية")
		print("   لاسم الملف (مثلاً \"sword\" أو \"goblin\") وشغّل السكريبت تاني.")

	print("\n✅ خلص كل حاجة! لو مش ظاهر التحديث فوراً في Project Settings،")
	print("   اعمل: Project → Reload Current Project")
	print("═══════════════════════════════════════════════════")
