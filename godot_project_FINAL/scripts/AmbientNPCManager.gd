extends Node
# =====================================================================
# Asharaya — AmbientNPCManager
# =====================================================================
# تطبيق فعلي لفكرة "Mass Entity System" من وثيقة التصميم:
# 3500 NPC Ambient المفروض يستهلكوا CPU شبه صفري.
#
# الفكرة: أي NPC بعيد عن كل اللاعبين مش محتاج يحسب حركته كل فريم.
# نبعده لمستوى تحديث أبطأ بالتدريج كل ما يبعد، بدل تشغيل/إيقاف مفاجئ.
#
# يفترض وجود Perf (PerformanceManager) كـ Autoload
# =====================================================================

var ambient_npcs: Array = []
var player_positions: Array[Vector3] = []  # يتحدّث من كود اللاعبين (Multiplayer)

var _tick_counter: int = 0

func _ready():
	set_process(true)

func register_npc(npc: Node3D):
	ambient_npcs.append(npc)
	npc.set_meta("update_tier", 0)  # 0 = قريب/نشط بالكامل

func unregister_npc(npc: Node3D):
	ambient_npcs.erase(npc)

func update_player_position(player_id: int, pos: Vector3):
	# استدعِها من كود الشبكة (Nakama) كل ما موقع لاعب يتحدّث
	if player_id >= player_positions.size():
		player_positions.resize(player_id + 1)
	player_positions[player_id] = pos

# =====================================================================
# الحلقة الرئيسية — بنوزّع الفحص على عدة فريمات بدل كل الـ 3500 مرة واحدة
# ده بحد ذاته توفير أداء: فحص 3500 كائن كل فريم = تعليق محسوس
# فحص دفعة صغيرة كل فريم = توزيع الحمل بدون ما اللاعب يحس
# =====================================================================
func _process(_delta):
	if ambient_npcs.is_empty() or player_positions.is_empty():
		return

	var batch_size = _get_batch_size_for_tier()
	var total = ambient_npcs.size()

	for i in range(batch_size):
		var idx = (_tick_counter + i) % total
		_update_single_npc(ambient_npcs[idx])

	_tick_counter = (_tick_counter + batch_size) % total

func _get_batch_size_for_tier() -> int:
	# على الأجهزة الضعيفة، بنفحص دفعات أصغر — يعني كل NPC بياخد
	# تحديث أبطأ شوية، لكن ده غير محسوس بصرياً لأنه NPC خلفية أصلاً
	match Perf.tier:
		Perf.Tier.POTATO: return 40
		Perf.Tier.LOW: return 100
		Perf.Tier.MEDIUM: return 250
		Perf.Tier.HIGH: return 500
		Perf.Tier.ULTRA: return 1000
		_: return 150

func _update_single_npc(npc: Node3D):
	if not is_instance_valid(npc):
		return

	var nearest_dist = _get_nearest_player_distance(npc.global_position)
	var draw_distance = Perf.get_draw_distance()

	if nearest_dist > draw_distance * 1.5:
		# بعيد جداً عن أي لاعب: نوقفه بالكامل (Culled)
		npc.set_physics_process(false)
		npc.visible = false
	elif nearest_dist > draw_distance:
		# برة مدى الرؤية لكن قريب نسبياً: نحرّكه بس من غير رسم
		npc.visible = false
		npc.set_physics_process(true)
	else:
		# داخل مدى الرؤية: نشط بالكامل
		npc.visible = true
		npc.set_physics_process(true)

func _get_nearest_player_distance(pos: Vector3) -> float:
	var min_dist = INF
	for p_pos in player_positions:
		if p_pos == Vector3.ZERO:
			continue
		var d = pos.distance_to(p_pos)
		if d < min_dist:
			min_dist = d
	return min_dist
