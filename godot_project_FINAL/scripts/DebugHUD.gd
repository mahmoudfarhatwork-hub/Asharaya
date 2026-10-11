extends Label
# =====================================================================
# Asharaya — DebugHUD
# =====================================================================
# لوحة بسيطة تظهر وقت الاختبار الفعلي على أي جهاز: المستوى اللي
# اتحدد تلقائيًا (Potato/Low/Medium/High/Ultra)، الـ FPS الحقيقي،
# عدد الـ Chunks المحمّلة، والرام المستخدمة. من غير الأرقام دي
# مينفعش نتأكد إن التحسين شغال فعلاً على جهاز حقيقي بدل الافتراض.
# اقفلها وقت الإصدار النهائي بمسح الـ Node من المشهد أو visible = false.
# =====================================================================

var _timer: float = 0.0

func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.25:
		return
	_timer = 0.0

	var tier_name := "غير معروف"
	var draw_dist := 0.0
	var perf = get_node_or_null("/root/Perf")
	if perf:
		tier_name = perf.Tier.keys()[perf.tier]
		draw_dist = perf.get_draw_distance()

	var chunk_count := 0
	var streamer = get_node_or_null("/root/Main/World/ChunkStreamer")
	if streamer:
		chunk_count = streamer.get_loaded_chunk_count()

	var mem_mb := OS.get_static_memory_usage() / 1048576.0

	var npc_count := 0
	if has_node("/root/Behavior"):
		npc_count = get_node("/root/Behavior").get_registered_count()

	var time_line := ""
	var time_mgr = get_node_or_null("/root/GameClock")
	if time_mgr:
		time_line = "\nالوقت: %s | يوم %d | %s" % [
			time_mgr.get_time_string(), time_mgr.game_day, time_mgr.get_current_season()
		]

	text = "FPS: %d\nTier: %s | Draw Distance: %.0f\nChunks Loaded: %d\nNPCs consulting model: %d\nMemory: %.1f MB\nPlatform: %s%s" % [
		Engine.get_frames_per_second(),
		tier_name,
		draw_dist,
		chunk_count,
		npc_count,
		mem_mb,
		OS.get_name(),
		time_line
	]
