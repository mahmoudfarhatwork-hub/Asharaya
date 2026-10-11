extends Node3D
# =====================================================================
# Asharaya — ChunkStreamer (نظام توزيع الأحمال بالمصفوفات)
# =====================================================================
# ده الجزء اللي كان ناقص في WorldGenerator القديم: العالم القديم كان
# كله بيتبني مرة واحدة (200×200) في _ready(). ده شغال لعالم صغير، بس
# مع عالم MMORPG مفتوح هيكبر، ده هيحمّل كل حاجة في الرام من أول ثانية
# حتى لو اللاعب واقف في مكان واحد.
#
# الحل هنا: العالم مقسّم لشبكة Chunks (مصفوفة ثنائية الأبعاد منطقية،
# مش نودز فعلية إلا وقت الحاجة). كل Chunk بييتحمّل لما لاعب يقرب منه،
# وبيتفك (يتشال من الرام) لما كل اللاعبين يبعدوا عنه. ده بالظبط معنى
# "مصفوفات توزع الأحمال" اللي طلبتها — بدل عالم واحد ضخم، مصفوفة قطع
# صغيرة بيتوزع تحميلها وتفريغها حسب مين قريب مين بعيد.
#
# يفترض وجود Perf (PerformanceManager) كـ Autoload.
# =====================================================================

const CHUNK_SIZE: float = 64.0          # حجم كل قطعة بالمتر
const UNLOAD_MARGIN: float = 1.4        # هامش قبل الفك، يمنع تحميل/فك متكرر عند الحدود

# مصفوفة تحميل الأحمال: مفتاح = "x_z" للقطعة -> بيانات القطعة
var _chunk_states: Dictionary = {}       # "3_-2" -> {status, node, distance}
var _load_queue: Array = []              # قطع منتظرة الدور (تحميل تدريجي، مش كله مرة واحدة)
var _player_positions: Dictionary = {}   # player_id -> Vector3

@export var chunk_scene: PackedScene     # المشهد اللي بيتنسخ لكل قطعة (تضبطه من المحرر)
@export var world_seed: int = 0

var _rng := RandomNumberGenerator.new()
var _frame_counter: int = 0

func _ready():
	_rng.seed = world_seed if world_seed != 0 else hash(Time.get_unix_time_from_system())
	set_process(true)

func register_player(player_id: int, pos: Vector3):
	_player_positions[player_id] = pos

func unregister_player(player_id: int):
	_player_positions.erase(player_id)

func update_player_position(player_id: int, pos: Vector3):
	_player_positions[player_id] = pos

# =====================================================================
# كل فريم: نحسب مين محتاج يتحمّل ومين محتاج يتفك، لكن التنفيذ الفعلي
# بيتوزع على عدة فريمات (Load Budget) عشان ملحقش نحمّل 10 قطع في فريم
# واحد ونعمل Lag Spike محسوس. العدد نفسه بييجي من Perf.
# =====================================================================
func _process(_delta):
	_frame_counter += 1
	if _player_positions.is_empty():
		return

	# كل عدة فريمات بس نعيد حساب مين قريب ومين بعيد (مفيش داعي كل فريم)
	if _frame_counter % 10 == 0:
		_evaluate_chunks()

	_flush_load_queue()

func _get_load_radius() -> int:
	# نصف قطر التحميل بالـ Chunks، مبني على draw_distance من Perf
	var dd = Perf.get_draw_distance()
	return max(1, int(ceil(dd / CHUNK_SIZE)))

func _evaluate_chunks():
	var radius = _get_load_radius()
	var needed: Dictionary = {}   # مفاتيح كل القطع المفروض تكون محمّلة دلوقتي

	for pid in _player_positions:
		var pos: Vector3 = _player_positions[pid]
		var cx = int(floor(pos.x / CHUNK_SIZE))
		var cz = int(floor(pos.z / CHUNK_SIZE))
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				# دائرة مش مربع — يوفر تحميل زوايا مش محتاجينها فعلاً
				if dx * dx + dz * dz > radius * radius:
					continue
				var key = "%d_%d" % [cx + dx, cz + dz]
				needed[key] = Vector2i(cx + dx, cz + dz)

	# قطع لازم تتحمّل ومش محمّلة
	for key in needed:
		if not _chunk_states.has(key):
			_chunk_states[key] = {"status": "queued", "node": null, "coord": needed[key]}
			_load_queue.append(key)

	# قطع محمّلة بس مبقتش لازمة (بهامش، عشان منفكش ونحمّل تاني كل ثانية)
	var unload_radius = radius * UNLOAD_MARGIN
	var to_unload: Array = []
	for key in _chunk_states:
		if _chunk_states[key]["status"] != "loaded":
			continue
		if needed.has(key):
			continue
		var coord: Vector2i = _chunk_states[key]["coord"]
		var still_close = false
		for pid in _player_positions:
			var pos: Vector3 = _player_positions[pid]
			var cx = int(floor(pos.x / CHUNK_SIZE))
			var cz = int(floor(pos.z / CHUNK_SIZE))
			if Vector2(coord.x - cx, coord.y - cz).length() <= unload_radius:
				still_close = true
				break
		if not still_close:
			to_unload.append(key)

	for key in to_unload:
		_unload_chunk(key)

# =====================================================================
# تحميل تدريجي: عدد القطع المسموح تحميلها في الفريم الواحد يعتمد على
# قوة الجهاز (تحديدًا الجزء الجوهري من "توزيع الأحمال")
# =====================================================================
func _flush_load_queue():
	if _load_queue.is_empty():
		return
	var budget = _get_load_budget()
	for i in range(min(budget, _load_queue.size())):
		var key = _load_queue.pop_front()
		if _chunk_states.has(key) and _chunk_states[key]["status"] == "queued":
			_load_chunk(key)

func _get_load_budget() -> int:
	match Perf.tier:
		Perf.Tier.POTATO: return 1
		Perf.Tier.LOW: return 1
		Perf.Tier.MEDIUM: return 2
		Perf.Tier.HIGH: return 3
		Perf.Tier.ULTRA: return 4
		_: return 1

func _load_chunk(key: String):
	var coord: Vector2i = _chunk_states[key]["coord"]
	var node: Node3D
	if chunk_scene:
		node = chunk_scene.instantiate()
	else:
		node = _generate_procedural_chunk(coord)

	node.position = Vector3(coord.x * CHUNK_SIZE, 0, coord.y * CHUNK_SIZE)
	node.name = "Chunk_%s" % key
	add_child(node)
	_chunk_states[key]["node"] = node
	_chunk_states[key]["status"] = "loaded"

func _unload_chunk(key: String):
	var node = _chunk_states[key].get("node")
	if is_instance_valid(node):
		node.queue_free()
	_chunk_states.erase(key)

# مولّد إجرائي بسيط لو مفيش chunk_scene متعين — نفس فكرة الأشجار/العشب
# القديمة بس محلي داخل القطعة نفسها بدل العالم كله دفعة واحدة
# نصف حجم الأرض الثابتة اللي بتعملها WorldGenerator حوالين نقطة البداية.
# القطع (chunks) اللي بتقع جوه المنطقة دي مالهاش داعي أرض إضافية (موجودة
# أصلاً)، أما اللي برّاها فلازم تجيب أرضها وتصادمها هي بنفسها، وإلا
# اللاعب هيدخل منطقة مفيش تحتها غير الفراغ ويسقط فيه للأبد.
const BASE_GROUND_HALF_SIZE: float = 250.0

func _generate_procedural_chunk(coord: Vector2i) -> Node3D:
	var chunk = Node3D.new()
	var local_rng = RandomNumberGenerator.new()
	local_rng.seed = hash("%d_%d_%d" % [coord.x, coord.y, world_seed])

	var chunk_center_x = coord.x * CHUNK_SIZE + CHUNK_SIZE * 0.5
	var chunk_center_z = coord.y * CHUNK_SIZE + CHUNK_SIZE * 0.5
	var needs_own_ground = abs(chunk_center_x) > BASE_GROUND_HALF_SIZE or abs(chunk_center_z) > BASE_GROUND_HALF_SIZE

	if needs_own_ground:
		var ground = MeshInstance3D.new()
		var ground_mesh = PlaneMesh.new()
		ground_mesh.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
		ground.mesh = ground_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.25, 0.1)
		ground.material_override = mat
		ground.position = Vector3(CHUNK_SIZE * 0.5, 0, CHUNK_SIZE * 0.5)
		var ground_body = StaticBody3D.new()
		var ground_col = CollisionShape3D.new()
		var ground_shape = BoxShape3D.new()
		ground_shape.size = Vector3(CHUNK_SIZE, 0.1, CHUNK_SIZE)
		ground_col.shape = ground_shape
		ground_body.add_child(ground_col)
		ground.add_child(ground_body)
		chunk.add_child(ground)

	var tree_count = int(Perf.get_tree_instance_count() / 20.0)
	if tree_count > 0:
		var mm_node = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var trunk: Mesh = Assets.get_random_mesh("trees") if has_node("/root/Assets") else null
		if trunk == null:
			trunk = CylinderMesh.new()
			trunk.top_radius = 0.3
			trunk.bottom_radius = 0.4
			trunk.height = 4.0
		mm.mesh = trunk
		mm.instance_count = tree_count

		# نفس فكرة WorldGenerator: شجر MultiMesh لوحده مفيهوش تصادم، فبنضيف
		# جسم تصادم فعلي لكل شجرة بنفس مكانها بالظبط.
		var collisions_root = Node3D.new()

		for i in range(tree_count):
			var tx = local_rng.randf_range(0, CHUNK_SIZE)
			var tz = local_rng.randf_range(0, CHUNK_SIZE)
			var t = Transform3D()
			t = t.rotated(Vector3.UP, local_rng.randf_range(0, TAU))
			t.origin = Vector3(tx, 2.0, tz)
			mm.set_instance_transform(i, t)

			var body = StaticBody3D.new()
			body.position = Vector3(tx, 2.0, tz)
			var col = CollisionShape3D.new()
			var shape = CylinderShape3D.new()
			shape.radius = 0.4
			shape.height = 4.0
			col.shape = shape
			body.add_child(col)
			collisions_root.add_child(body)

		mm_node.multimesh = mm
		chunk.add_child(mm_node)
		chunk.add_child(collisions_root)

	return chunk

func get_loaded_chunk_count() -> int:
	var c = 0
	for key in _chunk_states:
		if _chunk_states[key]["status"] == "loaded":
			c += 1
	return c
