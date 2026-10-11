extends Node3D

# ★ نظام "أصول حقيقية لو موجودة، Placeholder لو مش موجودة بعد"
# التحميل نفسه بقى مركزي في Autoload اسمه "Assets" (AssetAutoLoader.gd)
# بدل ما يتكرر هنا — نفس السلوك بالظبط: حط .glb في assets/models/<فئة>/
# واللعبة تستخدمه أوتوماتيك، وترجع للأشكال البدائية لو الفولدر فاضي.
# =====================================================================
# Asharaya — WorldGenerator (نسخة محسّنة تعتمد على PerformanceManager)
# =====================================================================
# الفرق عن أي World Generator عادي: كل قرار (عدد الأشجار، جودة الظل،
# مدى الرؤية) بييجي من Perf (PerformanceManager) مش أرقام ثابتة.
# نفس الملف يشتغل على هاتف 2GB وعلى PC قوي — العدد والجودة بس بيفرقوا.
#
# يفترض وجود Perf كـ Autoload (من PerformanceManager.gd)
# =====================================================================

var rng = RandomNumberGenerator.new()

func _ready():
	rng.randomize()
	# ننتظر Perf يخلص تحديد المستوى الأول (بيحصل في نفس الفريم عادةً)
	_setup_environment()
	_setup_lighting()
	_setup_ground()
	_setup_vegetation_multimesh()   # ← هنا السحر: MultiMesh بدل عناصر منفردة
	_setup_village()

# =====================================================================
# البيئة — الضباب هنا مش تجميلي بس، هو أداة أداء حقيقية:
# بيخفي حدود الـ Draw Distance عن اللاعب بدل ما يشوف العالم "يختفي"
# =====================================================================
func _setup_environment():
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.03, 0.15)
	sky_mat.sky_horizon_color = Color(0.3, 0.1, 0.05)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4

	# الضباب بيبدأ قبل الـ draw_distance بشوية، عشان الاختفاء يبقى ناعم
	var dd = Perf.get_draw_distance()
	env.fog_enabled = true
	env.fog_depth_begin = dd * 0.6
	env.fog_depth_end = dd
	env.fog_light_color = Color(0.2, 0.15, 0.25)

	env.glow_enabled = Perf.is_glow_enabled()
	env.glow_intensity = 0.4

	env_node.environment = env
	add_child(env_node)

func _setup_lighting():
	var moon = DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-45, 30, 0)
	moon.light_energy = 0.6
	moon.light_color = Color(0.6, 0.7, 1.0)
	# ← الظل بيتقفل تماماً على الأجهزة الضعيفة، مش بس يقل جودة
	moon.shadow_enabled = Perf.are_shadows_enabled()
	add_child(moon)

const GROUND_SIZE: float = 500.0  # كانت 200 وده كان بيخلي الأرض تحس إنها ضيقة/بتخلص بسرعة

func _setup_ground():
	var ground = MeshInstance3D.new()
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	# subdivide عشان الإضاءة/الظل ينعموا على مساحة كبيرة كده
	mesh.subdivide_width = 20
	mesh.subdivide_depth = 20
	ground.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.25, 0.1)
	ground.material_override = mat
	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(GROUND_SIZE, 0.1, GROUND_SIZE)
	col.shape = shape
	body.add_child(col)
	ground.add_child(body)
	add_child(ground)

# =====================================================================
# ★★★ الجزء الأهم: نباتات بـ MultiMesh بدل Node لكل عشبة/شجرة ★★★
# فرق الأداء حقيقي: 1000 Node منفصل = 1000 استدعاء رسم (Draw Call)
# 1000 نسخة في MultiMesh واحد = استدعاء رسم واحد بس
# العدد نفسه بييجي من Perf، يعني هاتف ضعيف بياخد عدد أقل تلقائياً
# =====================================================================
func _setup_vegetation_multimesh():
	_spawn_multimesh_grass()
	_spawn_multimesh_trees()

func _spawn_multimesh_grass():
	var count = Perf.get_grass_instance_count()
	if count <= 0:
		return  # المستوى الأضعف (Potato) ممكن يقفلها تماماً

	var mm_node = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var blade_mesh = PrismMesh.new()
	blade_mesh.size = Vector3(0.1, 0.5, 0.08)
	mm.mesh = blade_mesh
	mm.instance_count = count

	for i in range(count):
		var x = rng.randf_range(-70, 70)
		var z = rng.randf_range(-70, 70)
		if abs(x) < 15 and abs(z) < 15:
			continue
		var t = Transform3D()
		t = t.rotated(Vector3.UP, rng.randf_range(0, TAU))
		t.origin = Vector3(x, 0.25, z)
		mm.set_instance_transform(i, t)

	mm_node.multimesh = mm
	# ★ Godot 4.7 real feature: VisibilityRange — النجمة بتختفي تلقائي
	# لو بعيدة، بدون ما تحتاج كود إضافي لإخفائها يدوياً
	mm_node.visibility_range_end = Perf.get_draw_distance() * 0.5
	mm_node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mm_node)

func _spawn_multimesh_trees():
	var count = Perf.get_tree_instance_count()
	if count <= 0:
		return

	var mm_node = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D

	# ★ لو Assets عنده مجسم شجرة حقيقي، استخدمه، وإلا ارجع للعامود البدائي
	var trunk_mesh: Mesh = Assets.get_random_mesh("trees") if has_node("/root/Assets") else null
	if trunk_mesh == null:
		var placeholder := CylinderMesh.new()
		placeholder.top_radius = 0.3
		placeholder.bottom_radius = 0.4
		placeholder.height = 4.0
		trunk_mesh = placeholder
	mm.mesh = trunk_mesh
	mm.instance_count = count

	# ★ MultiMesh مالوش تصادم تلقائي (ده بالظبط سبب إن اللاعب كان بيعدي جوه
	# الشجر). بنضيف جسم تصادم حقيقي (StaticBody3D + CollisionShape3D) لكل
	# شجرة، بنفس مكانها وحجمها بالظبط. العدد محدود أصلاً (15-250 حسب الجهاز)
	# فده رخيص جداً على الأداء مقارنة بالفرق اللي بيعمله للّعب.
	var collisions_root = Node3D.new()
	collisions_root.name = "TreeCollisions"

	for i in range(count):
		var x = rng.randf_range(-90, 90)
		var z = rng.randf_range(-90, 90)
		if abs(x) < 20 and abs(z) < 20:
			continue
		var t = Transform3D()
		t = t.rotated(Vector3.UP, rng.randf_range(0, TAU))
		var s = rng.randf_range(0.8, 1.3)
		t = t.scaled(Vector3(s, s, s))
		t.origin = Vector3(x, 2.0, z)
		mm.set_instance_transform(i, t)

		var body = StaticBody3D.new()
		body.position = Vector3(x, 2.0, z)
		var col = CollisionShape3D.new()
		var shape = CylinderShape3D.new()
		shape.radius = 0.4 * s
		shape.height = 4.0 * s
		col.shape = shape
		body.add_child(col)
		collisions_root.add_child(body)

	mm_node.multimesh = mm
	mm_node.visibility_range_end = Perf.get_draw_distance()
	mm_node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mm_node)
	add_child(collisions_root)

func _setup_village():
	# القرية: بيوت حقيقية (مش MultiMesh لأن كل بيت مختلف/تفاعلي)
	# العدد صغير أصلاً (5 بيوت) فمفيش داعي للتحسين هنا
	# ★ باعدت المسافات عن المركز (كانت قريبة جدًا من نقطة ظهور اللاعب
	# عند 0,0,0 فكان بيطلع لقيّ نفسه بص في وش بيت على طول).
	var house_positions = [
		Vector3(-15, 0, 6), Vector3(15, 0, 6),
		Vector3(-15, 0, -10), Vector3(15, 0, -10),
		Vector3(0, 0, -16)
	]
	for pos in house_positions:
		_create_house(pos)

func _create_house(pos: Vector3):
	var instance: Node3D = Assets.instantiate_random("village") if has_node("/root/Assets") else null

	if instance != null:
		instance.position = pos
		add_child(instance)

		# ★ بنحسب صندوق إحاطة (AABB) حوالين المجسم الحقيقي عشان نبني
		# تصادم مناسب لحجمه بالظبط، مهما كان حجم/شكل الموديل اللي جبته
		var combined_aabb := AABB()
		var first := true
		for child in _get_all_mesh_instances(instance):
			var world_aabb: AABB = child.get_aabb()
			world_aabb.position += child.position
			if first:
				combined_aabb = world_aabb
				first = false
			else:
				combined_aabb = combined_aabb.merge(world_aabb)

		if not first:  # يعني لقينا Mesh فعلاً
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = combined_aabb.size
			col.shape = shape
			col.position = combined_aabb.position + combined_aabb.size * 0.5
			body.add_child(col)
			instance.add_child(body)
		return

	# --- Placeholder (لحد ما تحط أصل حقيقي في assets/models/village/) ---
	var house = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(4, 3, 4)
	house.mesh = mesh
	house.position = pos + Vector3(0, 1.5, 0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.5, 0.35)
	house.material_override = mat

	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(4, 3, 4)
	col.shape = shape
	body.add_child(col)
	house.add_child(body)

	add_child(house)

func _get_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_get_all_mesh_instances(child))
	return result
