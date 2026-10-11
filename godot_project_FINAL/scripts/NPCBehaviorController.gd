extends Node
# =====================================================================
# Asharaya — NPCBehaviorController
# =====================================================================
# طلبك: كل الـ 4000 NPC يكلموا النموذج، مش بس الـ 500 المتقدمين، والنموذج
# يبقى مسئول عن نشاطهم (مشي/شغل/هروب) مش بس كلامهم وقت الحوار.
#
# نقطة مهمة وصريحة قبل أي حاجة: مفيش طريقة يتحكم فيها نموذج لغوي عبر
# HTTP في حركة 4000 كائن **كل فريم** (60 مرة في الثانية) — ده يحتاج
# 240,000 طلب HTTP في الثانية، مش هيقدر عليه ولا سيرفر قوي في الدنيا،
# فما بالك بموديل ضعيف/بطيء زي اللي وصفته. أي حد يقولك ده ممكن يبقى
# بيكدب عليك أو مش فاهم الفرق بين "قرار" و"فيزيقا فريم بفريم".
#
# اللي فعليًا ممكن ومنطقي، وهو اللي الملف ده بيعمله:
# كل NPC (الـ 4000 كلهم، مش استثناء حد) بيسأل النموذج **بشكل دوري
# متباعد** "تعمل إيه دلوقتي؟" (idle/wander/work/greet/flee...)، والفاصل
# الزمني بيكبر كل ما الـ NPC بعيد عن اللاعب (قريب = كل 15-30 ثانية،
# بعيد/متوقف تمامًا = كل 3-6 دقايق). بين قرار وقرار، الحركة الفعلية
# (مشي خطوة خطوة) بتتحسب محليًا في كود الـ NPC نفسه زي أي لعبة عادية —
# مش مربوطة بالسيرفر. ده بالظبط نفس المنطق اللي بتستخدمه ألعاب فيها
# NPCs بذكاء اصطناعي حقيقي (زي تجارب Generative Agents الشهيرة).
#
# طلبات الحركة كمان محدودة بسقف تزامن (_get_request_budget) بالظبط
# زي حوار الـ 500، عشان لو استخدمت موديل ضعيف/بطيء، السيرفر ميتغرقش
# بـ 4000 طلب في نفس اللحظة.
#
# التركيب: ضيفه كـ Node تحت World في Main.tscn (موجود بالفعل).
# =====================================================================

var _entries: Dictionary = {}   # npc_id -> {node, profile, next_decision_time, thinking_label}
var _rng := RandomNumberGenerator.new()

# [min, max] بالثواني — تحدد كل قد ايه الـ NPC "بيفكر" تاني حسب حالته
const INTERVAL_VISIBLE: Array = [15.0, 30.0]     # ظاهر على الشاشة فعليًا
const INTERVAL_NEARBY: Array = [45.0, 90.0]      # قريب بس مش ظاهر (برة الكاميرا)
const INTERVAL_FAR: Array = [180.0, 360.0]       # بعيد جدًا/متوقف — لسه بيتشاور، بس نادر جدًا

func _ready() -> void:
	_rng.randomize()
	Dialogue.action_ready.connect(_on_action_ready)
	Dialogue.action_failed.connect(_on_action_failed)
	set_process(true)

# =====================================================================
# register_npc — ينادَى مرة واحدة لكل NPC وقت إنشائه (سواء من الـ 500
# المتقدمين أو الـ 3500 الخلفية، مفيش فرق في التسجيل نفسه).
# profile نفس شكل NPCDialogueBridge (name/role/faction/mood/location)
# + "available_actions" اختياري لو الـ NPC ده عنده نشاطات خاصة.
# =====================================================================
func register_npc(npc: Node3D, profile: Dictionary) -> void:
	var npc_id: String = profile.get("npc_id", str(npc.get_instance_id()))
	profile["npc_id"] = npc_id
	var brain := get_node_or_null("/root/Dialogue")
	if brain and brain.has_method("register_talkable"):
		brain.register_talkable(npc, profile)
	_entries[npc_id] = {
		"node": npc,
		"profile": profile,
		# نفرّق أول قرار عشوائيًا لكل NPC عشان الـ 4000 ميسألوش كلهم
		# في نفس اللحظة أول ما اللعبة تفتح
		"next_decision_time": Time.get_ticks_msec() / 1000.0 + _rng.randf_range(0.0, 25.0),
		"thinking_label": null,
	}

func unregister_npc(npc: Node3D) -> void:
	for npc_id in _entries.keys():
		if _entries[npc_id]["node"] == npc:
			_clear_thinking(_entries[npc_id])
			_entries.erase(npc_id)
			return

func get_registered_count() -> int:
	return _entries.size()

# =====================================================================
# كل فريم: نشوف مين حان دوره ونبعت له طلب، لكن بسقف صارم لعدد الطلبات
# الجديدة في نفس الفريم (احترام max_concurrent_requests في Dialogue)
# =====================================================================
func _process(_delta: float) -> void:
	if _entries.is_empty():
		return

	var now = Time.get_ticks_msec() / 1000.0
	var budget = _get_request_budget()
	var sent = 0

	for npc_id in _entries.keys():
		if sent >= budget:
			break
		var entry = _entries[npc_id]
		if not is_instance_valid(entry["node"]):
			continue
		if now < entry["next_decision_time"]:
			continue
		_request_decision(npc_id, entry)
		sent += 1

func _get_request_budget() -> int:
	# لو الموديل ضعيف وبطيء زي ما وصفت، خليه على POTATO/LOW يدويًا
	# مؤقتًا وقت الاختبار — رقم أصغر = ضغط أقل على السيرفر بس قرارات
	# النشاط بتاخد وقت أطول تتوزع بينهم
	match Perf.tier:
		Perf.Tier.POTATO: return 1
		Perf.Tier.LOW: return 1
		Perf.Tier.MEDIUM: return 2
		Perf.Tier.HIGH: return 3
		Perf.Tier.ULTRA: return 5
		_: return 1

func _get_visibility_state(npc: Node3D) -> int:
	if npc.visible:
		return 0  # ظاهر فعليًا
	elif npc.is_physics_processing():
		return 1  # قريب بس مش في الكاميرا
	else:
		return 2  # متوقف تمامًا (Culled)

func _request_decision(npc_id: String, entry: Dictionary) -> void:
	var state = _get_visibility_state(entry["node"])
	var interval: Array = [INTERVAL_VISIBLE, INTERVAL_NEARBY, INTERVAL_FAR][state]
	entry["next_decision_time"] = Time.get_ticks_msec() / 1000.0 + _rng.randf_range(interval[0], interval[1])

	# مؤشر "بيفكر..." — بس للـ NPC الظاهر فعليًا على الشاشة، مفيش داعي
	# نعمل Label3D لحاجة مش هتتشاف أصلاً
	if state == 0:
		_show_thinking(entry)

	Dialogue.request_npc_action(entry["profile"])

# =====================================================================
# مؤشر التفكير — نقط متحركة فوق راس الـ NPC، بتختفي أول ما الرد يوصل.
# مفيد جدًا مع موديل بطيء عشان اللاعب يحس إن الـ NPC "بيرد" مش واقف
# عالق، بدل ما يستغرب السكون المفاجئ.
# =====================================================================
func _show_thinking(entry: Dictionary) -> void:
	var npc: Node3D = entry["node"]
	var label: Label3D = entry.get("thinking_label")
	if not is_instance_valid(label):
		label = Label3D.new()
		label.font_size = 34
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1, 1, 1, 0.85)
		label.position = Vector3(0, 2.3, 0)
		npc.add_child(label)
		entry["thinking_label"] = label

	label.text = "."
	var tw = create_tween()
	tw.set_loops(20)  # لحد ما الرد يوصل ويشيلها _on_action_ready/_on_action_failed
	for dots in [".", "..", "...", ""]:
		tw.tween_callback(func():
			if is_instance_valid(label):
				label.text = dots
		)
		tw.tween_interval(0.3)

func _clear_thinking(entry: Dictionary) -> void:
	var label = entry.get("thinking_label")
	if is_instance_valid(label):
		label.queue_free()
	entry["thinking_label"] = null

func _on_action_ready(npc_id: String, action: Dictionary) -> void:
	if not _entries.has(npc_id):
		return
	var entry = _entries[npc_id]
	_clear_thinking(entry)
	var npc = entry["node"]
	if is_instance_valid(npc) and npc.has_method("apply_ai_action"):
		npc.apply_ai_action(action)

func _on_action_failed(npc_id: String, _error: String) -> void:
	if not _entries.has(npc_id):
		return
	# فشل/بطء الطلب — منوقفش الـ NPC، بيفضل على تصرفه المحلي الحالي
	# لحد الفرصة الجاية (next_decision_time اتحدد بالفعل قبل الإرسال)
	_clear_thinking(_entries[npc_id])
