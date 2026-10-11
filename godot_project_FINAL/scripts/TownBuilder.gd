extends Node3D
class_name TownBuilder
# TownBuilder.gd — يبني "مدينة المبتدئين" فعليًا وقت تشغيل اللعبة
# باستخدام الأصول الحقيقية الموجودة في المشروع (مش placeholders):
#   - أرضية بتكسجر عشب حقيقي (assets/environment/textures/Grass.png)
#   - أشجار حقيقية حوالين المدينة (عن طريق Assets.instantiate_random("trees"))
#   - 21 وحش حقيقي كـ "حياة برية" برة أسوار المدينة (عن طريق Assets)
#   - كشك واحد لكل مهنة من المهن التسعة (NPC مبسط + لافتة باسم المهنة)
#
# التصميم: دائرة مدينة نصف قطرها TOWN_RADIUS، فيها 9 أكشاك مرتبة حواليها،
# وبرة المدينة (من TOWN_RADIUS لحد WORLD_RADIUS) غابة فيها أشجار ووحوش
# منخفضة المستوى للاعبين الجداد.

const TOWN_RADIUS := 18.0
const WORLD_RADIUS := 70.0
const GRASS_TEXTURE_PATH := "res://assets/environment/textures/Grass.png"

const PROFESSION_STALLS := [
	{"id": "warrior", "name_ar": "نقابة المحاربين", "color": Color(0.6, 0.15, 0.15)},
	{"id": "mage", "name_ar": "برج السحرة", "color": Color(0.2, 0.3, 0.8)},
	{"id": "sorcerer", "name_ar": "كوخ المشعوذين", "color": Color(0.4, 0.1, 0.5)},
	{"id": "priest", "name_ar": "معبد الكهنة", "color": Color(0.9, 0.85, 0.6)},
	{"id": "healer", "name_ar": "دار المعالجين", "color": Color(0.3, 0.8, 0.6)},
	{"id": "blacksmith", "name_ar": "ورشة الحدادين", "color": Color(0.4, 0.4, 0.42)},
	{"id": "trader", "name_ar": "سوق التجار", "color": Color(0.85, 0.65, 0.2)},
	{"id": "farmer", "name_ar": "حظيرة المزارعين", "color": Color(0.5, 0.7, 0.25)},
	{"id": "beast_tamer", "name_ar": "حظيرة مروضي الوحوش", "color": Color(0.7, 0.45, 0.15)},
]

# وحوش منخفضة المستوى مناسبة لمنطقة البداية (باقي الـ21 اتسابوا لمناطق أعلى مستوى لاحقاً)
const STARTER_WILDLIFE := ["chicken", "pig", "deer", "bat", "bee", "mushroom", "crab"]

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_setup_lighting_and_sky()
	_setup_ground()
	_setup_town_stalls()
	_setup_town_wall_markers()
	_setup_forest_ring()
	_setup_wildlife()


func _setup_lighting_and_sky() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.03, 0.12)
	sky_mat.sky_horizon_color = Color(0.28, 0.12, 0.08)
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.05)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_depth_begin = WORLD_RADIUS * 0.7
	env.fog_depth_end = WORLD_RADIUS * 1.3
	env.fog_light_color = Color(0.15, 0.12, 0.2)
	env_node.name = "WorldEnvironment"
	env_node.environment = env
	add_child(env_node)

	var moon := DirectionalLight3D.new()
	moon.name = "Sun"
	moon.rotation_degrees = Vector3(-50, 35, 0)
	moon.light_energy = 0.75
	moon.light_color = Color(0.65, 0.72, 1.0)
	moon.shadow_enabled = true
	add_child(moon)


func _setup_ground() -> void:
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(WORLD_RADIUS * 2.2, WORLD_RADIUS * 2.2)
	mesh.subdivide_width = 30
	mesh.subdivide_depth = 30
	ground.mesh = mesh

	var mat := StandardMaterial3D.new()
	var tex: Texture2D = load(GRASS_TEXTURE_PATH) if ResourceLoader.exists(GRASS_TEXTURE_PATH) else null
	if tex:
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3(40, 40, 1)
	else:
		mat.albedo_color = Color(0.15, 0.28, 0.12)
	ground.material_override = mat

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(WORLD_RADIUS * 2.2, 0.1, WORLD_RADIUS * 2.2)
	col.shape = shape
	body.add_child(col)
	ground.add_child(body)
	add_child(ground)


func _setup_town_stalls() -> void:
	var stalls_root := Node3D.new()
	stalls_root.name = "ProfessionStalls"
	add_child(stalls_root)

	var count := PROFESSION_STALLS.size()
	for i in range(count):
		var angle := (TAU / count) * i
		var pos := Vector3(cos(angle) * (TOWN_RADIUS * 0.6), 0, sin(angle) * (TOWN_RADIUS * 0.6))
		_create_stall(stalls_root, pos, PROFESSION_STALLS[i])


func _create_stall(parent: Node3D, pos: Vector3, info: Dictionary) -> void:
	var stall := Node3D.new()
	stall.name = "Stall_%s" % info["id"]
	stall.position = pos
	parent.add_child(stall)

	# جسم الكشك (صندوق بلون مميز لكل مهنة)
	var body_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.2, 2.0, 2.2)
	body_mesh.mesh = box
	body_mesh.position.y = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = info["color"]
	body_mesh.material_override = mat
	stall.add_child(body_mesh)

	var static_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 2.0, 2.2)
	col.shape = shape
	col.position.y = 1.0
	static_body.add_child(col)
	stall.add_child(static_body)

	# NPC مبسط واقف قدام الكشك (كبسولة + اسم) لحد ما موديلات البشر الحقيقية تتضاف
	var npc := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.height = 1.7
	cap.radius = 0.35
	npc.mesh = cap
	npc.position = Vector3(0, 0.85, 1.6)
	var npc_mat := StandardMaterial3D.new()
	npc_mat.albedo_color = info["color"].lightened(0.3)
	npc.material_override = npc_mat
	stall.add_child(npc)

	# ربط الـ NPC بعقل الحوار (Dialogue): بروفايل ثابت (اسم/عرق/عمر/طباع) + يبقى قابل للكلام
	var brain := get_node_or_null("/root/Dialogue")
	var prof: Dictionary = {}
	if brain and brain.has_method("make_profile"):
		prof = brain.make_profile(info["id"], "ألدريك" if info["id"] == "trader" else "")
		brain.register_talkable(npc, prof)

	# كشك التجار تحديداً بيبقى NPC حقيقي تقدر تتفاعل معاه (E) وتشتري منه
	if info["id"] == "trader":
		var trader := TraderNPC.new()
		trader.npc_name = "ألدريك"
		trader.position = npc.position
		var trader_col := CollisionShape3D.new()
		var trader_shape := CapsuleShape3D.new()
		trader_shape.height = 2.2
		trader_shape.radius = 1.2   # نطاق تفاعل أوسع شوية من جسم الكبسولة نفسه
		trader_col.shape = trader_shape
		trader.add_child(trader_col)
		stall.add_child(trader)
		if not prof.is_empty():
			trader.set_meta("profile", prof)   # نفس عقل الـ NPC اللي قدام الكشك

	# لافتة اسم الكشك/المهنة
	var label := Label3D.new()
	label.text = info["name_ar"]
	label.position = Vector3(0, 2.6, 0)
	label.font_size = 40
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 0.95, 0.8)
	stall.add_child(label)


# علامات بسيطة (أعمدة) على حدود المدينة، تفصل منطقة الأمان عن الغابة
func _setup_town_wall_markers() -> void:
	var markers_root := Node3D.new()
	markers_root.name = "TownBoundaryMarkers"
	add_child(markers_root)

	var count := 16
	for i in range(count):
		var angle := (TAU / count) * i
		var pos := Vector3(cos(angle) * TOWN_RADIUS, 0, sin(angle) * TOWN_RADIUS)
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.15
		cyl.bottom_radius = 0.2
		cyl.height = 2.5
		pole.mesh = cyl
		pole.position = pos + Vector3(0, 1.25, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.3, 0.2)
		pole.material_override = mat
		markers_root.add_child(pole)


# غابة حوالين المدينة — أشجار حقيقية (Assets.instantiate_random("trees"))
func _setup_forest_ring() -> void:
	var forest_root := Node3D.new()
	forest_root.name = "ForestRing"
	add_child(forest_root)

	var tree_count := 90
	for i in range(tree_count):
		var angle := rng.randf_range(0, TAU)
		var dist := rng.randf_range(TOWN_RADIUS + 4.0, WORLD_RADIUS)
		var pos := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		_spawn_tree(forest_root, pos)


func _spawn_tree(parent: Node3D, pos: Vector3) -> void:
	var tree: Node3D
	if has_node("/root/Assets") and Assets.has_model_category("trees"):
		tree = Assets.instantiate_random("trees")
	if tree == null:
		var mesh_instance := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.25
		cyl.bottom_radius = 0.4
		cyl.height = 4.0
		mesh_instance.mesh = cyl
		mesh_instance.position.y = 2.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.4, 0.15)
		mesh_instance.material_override = mat
		tree = mesh_instance

	tree.position = pos
	var s := rng.randf_range(0.8, 1.4)
	tree.scale = Vector3(s, s, s)
	tree.rotate_y(rng.randf_range(0, TAU))
	parent.add_child(tree)

	# تصادم بسيط حوالين جذع الشجرة
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.4 * s
	shape.height = 3.0 * s
	col.shape = shape
	col.position.y = 1.5 * s
	body.add_child(col)
	parent.add_child(body)


# حياة برية للاعبين الجداد: وحوش حقيقية من الـ21 المتاحين، منخفضة الخطورة
func _setup_wildlife() -> void:
	var wildlife_root := Node3D.new()
	wildlife_root.name = "StarterWildlife"
	add_child(wildlife_root)

	var count := 20
	for i in range(count):
		var monster_name: String = STARTER_WILDLIFE[rng.randi() % STARTER_WILDLIFE.size()]
		var angle := rng.randf_range(0, TAU)
		var dist := rng.randf_range(TOWN_RADIUS + 6.0, WORLD_RADIUS * 0.85)
		var pos := Vector3(cos(angle) * dist, 0.5, sin(angle) * dist)
		_spawn_monster(wildlife_root, monster_name, pos)


func _spawn_monster(parent: Node3D, monster_name: String, pos: Vector3) -> void:
	var monster := Monster.create(monster_name, pos)
	monster.name = "Wildlife_%s_%d" % [monster_name, parent.get_child_count()]
	monster.rotate_y(rng.randf_range(0, TAU))
	parent.add_child(monster)
	monster.add_to_group("monsters")
