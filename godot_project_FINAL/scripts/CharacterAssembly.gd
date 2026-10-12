extends Node
class_name CharacterAssembly
# CharacterAssembly.gd — أداة تركيب الشخصيات
#
# ═══════════════════════════════════════════════════════════
# ⚠️ اقرأ ده الأول: النظام ده "السباكة" (plumbing) بس، مش النماذج نفسها.
# مفيش ملفات .glb حقيقية موجودة دلوقتي — لو الملف مش موجود، بيستخدم شكل
# بديل (كبسولة ملونة) عشان تقدر تجرب النظام وتشوفه شغال قبل ما الأصول
# الحقيقية تكون جاهزة. لما تحط ملفات .glb في المسارات الصح، هتتحمّل تلقائي
# من غير ما تغيّر أي سطر كود.
# ═══════════════════════════════════════════════════════════
#
# ✅ ضمان عدم خلط الأعراق: كل الأجزاء بتتحمّل من مجلد العرق بتاعها بس
# (res://assets/characters/{race}/...) — مفيش أي مسار بيقدر "يسرح" لعرق
# تاني، فمستحيل جسم إلف ياخد راس بشري بالغلط.
#
# ✅ ضمان صفر تكرار: كل لاعب بياخد "appearance_seed" ثابت وقت إنشاء
# الحساب (مش عشوائي كل مرة يدخل اللعبة)، وده بيتحكم في:
#   - اختيار الجسم/الراس/الشعر (من الأشكال المتاحة للعرق)
#   - لون البشرة/الشعر/الملابس (قيمة مستمرة من ملايين الاحتمالات، مش من قايمة محدودة)
# التلوين المستمر (مش الأشكال بس) هو اللي بيضمن التنوع الفعلي الشبه-لانهائي.


static func assemble(character_root: Node3D, race_id: String, gender: String, profession: String, appearance_seed: int) -> void:
	if not RaceData.is_valid_race(race_id):
		push_error("❌ عرق غير معروف: %s — تم استخدام 'human' كبديل آمن" % race_id)
		race_id = "human"

	# شخصية Quaternius (Universal Base Characters) + حركات UAL — الأساس الجديد لكل الأعراق في الـ MVP
	if QuaterniusCharacter.has_assets():
		var old_body := character_root.get_node_or_null("HumanBody")
		if old_body:
			old_body.free()
		if QuaterniusCharacter.build(character_root, gender, appearance_seed) != null:
			return

	# احتياطي: موديل Mixamo البشري القديم
	if race_id == "human" and _has_real_human_model():
		_load_full_human_body(character_root, appearance_seed)
		return

	var race_info: Dictionary = RaceData.get_race(race_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = appearance_seed

	var base_path := "res://assets/characters/%s/%s" % [race_info["folder"], gender]

	var body_variants: int = race_info.get("body_variants", 3)
	var head_variants: int = race_info.get("head_variants", 8)
	var hair_variants: int = race_info.get("hair_variants", 6)

	var body_index := rng.randi_range(1, body_variants)
	var head_index := rng.randi_range(1, head_variants)
	var hair_index := rng.randi_range(1, hair_variants)

	# ألوان عشوائية مستمرة (مش من قايمة محدودة) — ده أساس ضمان عدم التكرار
	var skin_color := Color.from_hsv(rng.randf_range(0.02, 0.09), rng.randf_range(0.3, 0.6), rng.randf_range(0.5, 0.95))
	var hair_color := Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.9), rng.randf_range(0.2, 0.8))
	var cloth_color := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.8))

	_attach_part(character_root, "Body", "%s/body_%d.glb" % [base_path, body_index], skin_color)
	_attach_part(character_root, "Head", "%s/heads/head_%d.glb" % [base_path, head_index], skin_color)
	_attach_part(character_root, "Hair", "%s/hair/hair_%d.glb" % [base_path, hair_index], hair_color)
	_attach_part(character_root, "Clothes", "%s/professions/%s/clothes.glb" % [base_path, profession], cloth_color)


static func _attach_part(character_root: Node3D, part_name: String, resource_path: String, tint: Color) -> void:
	# احذف النسخة القديمة لو موجودة (مفيد لو بتغيّر شكل شخصية موجودة)
	var existing := character_root.get_node_or_null(part_name)
	if existing:
		existing.queue_free()

	var node: Node3D

	if ResourceLoader.exists(resource_path):
		var scene: PackedScene = load(resource_path)
		node = scene.instantiate()
		_apply_tint(node, tint)
	else:
		# بديل مؤقت للاختبار — كبسولة ملونة بدل الموديل الحقيقي
		node = _make_placeholder(part_name, tint)

	node.name = part_name
	character_root.add_child(node)


static func _make_placeholder(part_name: String, tint: Color) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh: Mesh
	var y_offset := 0.0

	match part_name:
		"Body":
			mesh = CapsuleMesh.new()
			(mesh as CapsuleMesh).height = 1.4
			(mesh as CapsuleMesh).radius = 0.35
			y_offset = 0.7
		"Head":
			mesh = SphereMesh.new()
			(mesh as SphereMesh).radius = 0.2
			y_offset = 1.6
		"Hair":
			mesh = SphereMesh.new()
			(mesh as SphereMesh).radius = 0.21
			y_offset = 1.65
		"Clothes":
			mesh = CylinderMesh.new()
			(mesh as CylinderMesh).top_radius = 0.36
			(mesh as CylinderMesh).bottom_radius = 0.3
			(mesh as CylinderMesh).height = 0.7
			y_offset = 1.0
		_:
			mesh = BoxMesh.new()

	mesh_instance.mesh = mesh
	mesh_instance.position.y = y_offset

	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mesh_instance.material_override = mat

	return mesh_instance


static func _apply_tint(node: Node3D, tint: Color) -> void:
	# بيدور على كل الـ MeshInstance3D جوه الموديل ويلوّنهم — يشتغل لو الموديل
	# الحقيقي مصمم يقبل تلوين (زي أغلب موديلات Mixamo/KayKit القياسية)
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = tint
			child.material_override = mat
		if child.get_child_count() > 0:
			_apply_tint(child, tint)


# ── توليد appearance_seed ثابت من user_id — نفس اللاعب دايماً ياخد نفس الشكل ──
static func seed_from_user_id(user_id: String) -> int:
	return hash(user_id) % 2147483647


# ═══ موديل Mixamo البشري الحقيقي + 6 حركات ═══
const HUMAN_BASE_DIR := "res://assets/characters/human_base/animations/"
const HUMAN_BASE_SCENE := HUMAN_BASE_DIR + "Reloading.fbx"
const HUMAN_ANIMATIONS := {
	"walk_backward": HUMAN_BASE_DIR + "Slow_Jog_Backwards.fbx",
	"zombie_standup": HUMAN_BASE_DIR + "Zombie_Stand_Up.fbx",
	"catwalk_walk": HUMAN_BASE_DIR + "Catwalk_Walk_Forward_HighKnees.fbx",
	"talk_phone": HUMAN_BASE_DIR + "Talking_On_Phone.fbx",
	"strut_walk": HUMAN_BASE_DIR + "Strut_Walking.fbx",
	"reload": HUMAN_BASE_DIR + "Reloading.fbx",
}


static func _has_real_human_model() -> bool:
	return ResourceLoader.exists(HUMAN_BASE_SCENE)


static func _load_full_human_body(character_root: Node3D, appearance_seed: int) -> void:
	var existing := character_root.get_node_or_null("HumanBody")
	if existing:
		existing.queue_free()
	var scene: PackedScene = load(HUMAN_BASE_SCENE)
	var body: Node3D = scene.instantiate()
	body.name = "HumanBody"
	character_root.add_child(body)
	var anim_player: AnimationPlayer = _find_animation_player(body)
	if anim_player == null:
		push_warning("افتح المشروع مرة في محرر Godot لاستيراد ملفات FBX")
		return
	var lib := AnimationLibrary.new()
	for anim_key in HUMAN_ANIMATIONS:
		var anim: Animation = _extract_first_animation(HUMAN_ANIMATIONS[anim_key])
		if anim:
			lib.add_animation(anim_key, anim)
	if anim_player.has_animation_library("mixamo"):
		anim_player.remove_animation_library("mixamo")
	anim_player.add_animation_library("mixamo", lib)
	if lib.has_animation("talk_phone"):
		anim_player.play("mixamo/talk_phone")


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


static func _extract_first_animation(fbx_path: String) -> Animation:
	if not ResourceLoader.exists(fbx_path):
		return null
	var scene: PackedScene = load(fbx_path)
	var temp: Node = scene.instantiate()
	var player := _find_animation_player(temp)
	var result: Animation = null
	if player:
		var names := player.get_animation_list()
		if names.size() > 0:
			result = player.get_animation(names[0]).duplicate()
	temp.queue_free()
	return result
