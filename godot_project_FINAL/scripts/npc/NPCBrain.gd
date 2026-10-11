class_name NPCBrain
extends Node
# ═══════════════════════════════════════════════════════════════════════
# NPCBrain.gd — عقل الـ NPCs بدون ذكاء اصطناعي (يتسجل Autoload باسم "Dialogue")
# بديل مباشر لـ NPCDialogueBridge: نفس الإشارات (response_ready / action_ready...) ونفس
# الدوال (request_npc_response / request_npc_action)، فباقي اللعبة (NPCBehaviorController
# وغيره) ماشي من غير أي تعديل. لو رجعت للـ AI يوم، بدّل مسار الـ Autoload بس.
#
# بيتفاعل مع: طريقة كلام اللاعب (نية + نبرة + أدب/إهانة/تهديد)، مكانه (كشك/ساحة/غابة)،
# الوقت والطقس، حالته (HP/جوع/مستوى/فلوس)، وذاكرته (الـ NPC بيفتكر مين كلمه وعن إيه).
# والرد بيتولّد من قوالب تركيبية (NPCGrammar) مش جمل ثابتة، ويختلف بحسب شخصية الـ NPC
# وذكائه (رتبة + مهنة + عمر) ومزاجه الحالي.
# ═══════════════════════════════════════════════════════════════════════

signal response_ready(npc_id: String, text: String)
signal response_failed(npc_id: String, error: String)
signal action_ready(npc_id: String, action: Dictionary)
signal action_failed(npc_id: String, error: String)
signal response_detail(npc_id: String, result: Dictionary)
signal quest_offered(npc_id: String, quest: Dictionary)

@export var max_concurrent_requests: int = 3     # للتوافق مع كود قديم (الـ Brain محلي ومفيهوش طوابير)
@export var talk_radius: float = 6.5
@export var near_radius: float = 3.5
@export var auto_save_seconds: float = 45.0
@export var reply_delay_enabled: bool = true
@export var show_bubbles: bool = true

const MEMORY_PATH := "user://npc_memory.json"
const TOWN_RADIUS := 18.0            # نفس TownBuilder.TOWN_RADIUS
const STALL_RADIUS_FACTOR := 0.6     # نفس مكان الأكشاك في TownBuilder
const CONVO_SECONDS := 40.0
const SESSION_SECONDS := 90.0

const COMMERCE_ACTS := ["buy_talk", "sell_talk", "service_talk", "quest_talk"]
const SECONDARY_ANSWERABLE := ["ask_direction", "ask_danger", "ask_how", "ask_identity", "ask_job", "ask_rumor"]

const TOPIC_LABEL := {
	"buy_talk": "الشراء", "sell_talk": "البيع", "service_talk": "الخدمات", "quest_talk": "المهام",
	"direction_talk": "الطرق", "rumor_talk": "الأخبار", "lore_talk": "الحكايات القديمة",
	"danger_talk": "الأخطار", "advice_talk": "النصايح", "job_talk": "الشغل", "identity": "نفسي",
	"smalltalk": "الجو",
}

# مهام: مستويات الندرة من وثيقتك (1% أسطورية / 9% نادرة / 20% عادية / 30% تافهة / 40% لا شيء)
# والمكافآت بالحديدية: سهلة 10، متوسطة 50، بطولية 1 فضية، أسطورية 5 فضية
const QUEST_TIERS := {
	"trivial": {"xp": [50, 100], "iron": 10, "count": [1, 2]},
	"normal": {"xp": [200, 500], "iron": 50, "count": [2, 4]},
	"rare": {"xp": [1000, 2500], "iron": 1000, "count": [4, 7]},
	"legendary": {"xp": [2500, 5000], "iron": 5000, "count": [1, 1]},
}
const QUEST_KILL_BY_TIER := {
	"trivial": ["slime"], "normal": ["bat", "bee", "mushroom", "crab"], "rare": ["gray_wolf"], "legendary": ["goblin_boss"],
}
const QUEST_KILL_NAMES := {
	"slime": "السلايم", "bat": "الخفافيش", "bee": "النحل الغاضب", "crab": "السرطانات",
	"mushroom": "الفطريات الشريرة", "gray_wolf": "الذئاب الرمادية", "goblin_boss": "زعيم الغوبلن",
}
const QUEST_LEAD := {
	"farmer": "الحقل بيتخرب", "blacksmith": "محتاج خامة", "warrior": "الطريق مش آمن",
	"healer": "الأعشاب بتتداس", "priest": "الأرواح قلقانة", "trader": "القوافل متعطلة",
	"mage": "تجاربي محتاجة عينات", "sorcerer": "ليا حساب قديم", "beast_tamer": "المخلوقات هايجة",
}

var rng := RandomNumberGenerator.new()
var minds: Dictionary = {}
var world_state: Dictionary = {"weather": "clear", "facts": []}
var player_info: Dictionary = {"name": "", "gender": "male", "race": "human"}

var _nodes: Dictionary = {}        # npc_id -> instance_id
var _convo_npc: String = ""
var _convo_until: float = 0.0
var _saved: Dictionary = {}
var _dirty: bool = false
var _fact_counter: int = 0


func _ready() -> void:
	rng.randomize()
	_load_memory()
	var t := Timer.new()
	t.wait_time = auto_save_seconds
	t.autostart = true
	t.timeout.connect(_autosave)
	add_child(t)


func _exit_tree() -> void:
	_save_memory()


# ═══════════════ واجهة عامة ═══════════════

func set_player_info(player_name: String, gender: String = "male", race: String = "") -> void:
	player_info["name"] = player_name
	player_info["gender"] = gender
	if race != "":
		player_info["race"] = race


func set_weather(weather: String) -> void:
	world_state["weather"] = weather


# أي نظام (قتل وحش، حدث، مهمة...) يقدر يضيف خبر بيحكيه الـ NPCs كإشاعة
func add_world_fact(text: String, weight: float = 1.0) -> void:
	var facts: Array = world_state["facts"]
	_fact_counter += 1
	facts.append({"id": "f%d" % _fact_counter, "text": text, "weight": weight, "day": int(_time_info()["day"])})
	while facts.size() > 30:
		facts.pop_front()


# يبني بروفايل ثابت لـ NPC كشك مهنة (نفس الاسم والطباع كل مرة)
func make_profile(job_id: String, name_override: String = "") -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash("profile_" + job_id)
	var race: String = str(NPCLexicon.STALL_RACE.get(job_id, "human"))
	var gender: String = "female" if r.randf() < 0.4 else "male"
	var npc_id: String = "stall_" + job_id
	var nm: String = NPCLexicon.random_name(race, gender, r)
	if job_id == "mage":
		npc_id = "elara"          # مهمة الترحيب في QuestSystem بتستهدف "elara"
		nm = "إيلارا"
		gender = "female"
	if name_override != "":
		nm = name_override
	return {"npc_id": npc_id, "name": nm, "job": job_id, "race": race, "gender": gender}


func register_talkable(node: Node, profile: Dictionary) -> void:
	if node == null:
		return
	var id: String = str(profile.get("npc_id", ""))
	if id == "":
		return
	_nodes[id] = node.get_instance_id()
	node.set_meta("profile", profile)
	if not node.is_in_group("npcs"):
		node.add_to_group("npcs")


func mind_for(profile: Dictionary) -> NPCMind:
	var id: String = str(profile.get("npc_id", ""))
	if id == "":
		id = "anon_%d" % hash(str(profile))
		profile["npc_id"] = id
	if minds.has(id):
		return minds[id]
	var m := NPCMind.create(profile)
	if _saved.has(id):
		m.load_dict(_saved[id])
	minds[id] = m
	return m


# ── توافق مع NPCDialogueBridge: حوار ──
func request_npc_response(npc_profile: Dictionary, player_message: String, speaker_name: String = "اللاعب") -> void:
	var npc_id: String = str(npc_profile.get("npc_id", "unknown"))
	var ctx := _context_for_profile(npc_profile)
	if speaker_name != "" and speaker_name != "اللاعب":
		ctx["player_name"] = speaker_name
	var result := respond(npc_profile, player_message, ctx)
	call_deferred("_emit_response", npc_id, result)


# ── توافق مع NPCDialogueBridge: قرار نشاط (يستدعيه NPCBehaviorController) ──
func request_npc_action(npc_profile: Dictionary, _world_context: String = "") -> void:
	var npc_id: String = str(npc_profile.get("npc_id", "unknown"))
	var ctx := _action_context(npc_profile)
	var res := decide_action(npc_profile, ctx)
	call_deferred("_emit_action", npc_id, res)


# ═══════════════ شات اللاعب مع الـ NPCs القريبة ═══════════════

func handle_player_chat(text: String) -> void:
	var clean := text.strip_edges()
	if clean == "" or clean.begins_with("/"):
		return
	var player := _find_player()
	if player == null:
		return
	var target := _pick_target(player, clean)
	if target == null:
		return
	var profile := _profile_of(target)
	var ctx := build_context(target, player)
	ctx["player_node"] = player
	var result := respond(profile, clean, ctx)
	_convo_npc = str(profile.get("npc_id", ""))
	_convo_until = float(ctx["now_sec"]) + CONVO_SECONDS
	if "new_session" in result["flags"]:
		_report_event(player, "talk_npc", _convo_npc)
	_deliver(target, profile, result)


# ═══════════════ المحرك: تحليل ← مزاج ← اختيار فعل ← توليد كلام ═══════════════

func respond(profile: Dictionary, text: String, ctx: Dictionary) -> Dictionary:
	var mind: NPCMind = mind_for(profile)
	var pid: String = str(ctx.get("player_id", "local"))
	var mem: Dictionary = mind.mem(pid)
	var day: int = int(ctx.get("day", 1))
	var hour: float = float(ctx.get("hour", 12.0))
	var now: float = float(ctx.get("now_sec", Time.get_ticks_msec() / 1000.0))
	mind.decay_to(day, hour)

	var a: Dictionary = SpeechAnalyzer.analyze(text, [mind.npc_name])
	var first_contact: bool = int(mem["met"]) == 0
	var new_session: bool = now > float(mem["session_until"])
	if new_session:
		mem["pending"] = {}
	var stim: Dictionary = mind.apply_stimulus(a, mem)

	var act: String = _choose_act(mind, a, mem, ctx)
	var slots: Dictionary = _slots(mind, mem, ctx)
	var out: Dictionary = {"parts": [], "actions": [], "flags": [], "first": first_contact, "new_session": new_session}
	if new_session:
		out["flags"].append("new_session")

	# افتتاحية الجلسة: لو اللاعب مابدأش بتحية، الـ NPC ممكن يرحّب هو
	var greeted: bool = a["primary"] == "greet" or a["secondary"] == "greet"
	if new_session and not greeted and not (act in ["greet", "farewell", "silence", "refuse_hostile", "insult_react", "threat_react"]):
		var tone_k: String = _tone_key(mind, mem)
		if first_contact:
			out["parts"].append(_p("greet.first", slots, mind))
		elif tone_k != "hostile" and rng.randf() < 0.45 + float(mind.traits["warmth"]) * 0.3:
			out["parts"].append(_p("greet." + tone_k, slots, mind))

	_dispatch(act, mind, mem, a, ctx, slots, out)

	# نيّة ثانوية: الـ NPC الذكي يرد على الاتنين
	if mind.intelligence >= 0.7 and a["secondary"] in SECONDARY_ANSWERABLE and float(a["secondary_score"]) >= 1.0 and not (act in ["refuse_hostile", "insult_react", "threat_react", "pending_yes", "pending_no"]):
		var sec_act: String = _act_for_intent(str(a["secondary"]))
		if sec_act != "" and sec_act != act:
			var out2: Dictionary = {"parts": [], "actions": [], "flags": [], "first": false, "new_session": false}
			_dispatch(sec_act, mind, mem, a, ctx, slots, out2)
			out["parts"].append_array(out2["parts"])

	# تعليق سياقي (حالتك، الجو، المكان، ذاكرته معاك)
	if act in ["greet", "buy_talk", "smalltalk", "how_are_you", "advice_talk", "identity", "job_talk"]:
		if rng.randf() < 0.25 + float(mind.traits["talkativeness"]) * 0.3:
			var rm: String = _context_remark(mind, mem, ctx, slots)
			if rm != "":
				out["parts"].append(rm)

	var joined: String = " ".join(out["parts"]).strip_edges()
	if joined == "":
		joined = _p("silence", slots, mind)
	var final_text: String = NPCGrammar.stylize(joined, mind, str(ctx.get("player_gender", "male")), rng)

	# تحديث الذاكرة
	mind.remember_reply(final_text)
	if new_session:
		mem["met"] = int(mem["met"]) + 1
		mem["session_until"] = now + SESSION_SECONDS
	else:
		mem["session_until"] = now + SESSION_SECONDS
	mem["last_day"] = day
	if TOPIC_LABEL.has(act):
		mem["last_topic"] = TOPIC_LABEL[act]
		var topics: Dictionary = mem["topics"]
		topics[act] = int(topics.get(act, 0)) + 1
	_dirty = true

	return {
		"text": final_text, "act": act, "emotion": mind.emotion(), "affinity": float(mem["affinity"]),
		"actions": out["actions"], "flags": out["flags"],
		"debug": {"intent": a["primary"], "score": a["primary_score"], "secondary": a["secondary"],
			"tone": a["tone"], "stim": stim, "intelligence": mind.intelligence, "mood": mind.mood.duplicate()},
	}


func _dispatch(act: String, mind: NPCMind, mem: Dictionary, a: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	match act:
		"silence": out["parts"].append(_p("silence", slots, mind))
		"confusion": _act_confusion(mind, a, slots, out)
		"greet": _act_greet(mind, mem, ctx, slots, out)
		"farewell": out["parts"].append(_p("farewell." + _soft_tone(mind, mem), slots, mind))
		"thanks_reply": out["parts"].append(_p("thanks." + _soft_tone(mind, mem), slots, mind))
		"apology_reply": _act_apology(mind, mem, slots, out)
		"how_are_you": _act_how(mind, ctx, slots, out)
		"identity": _act_identity(mind, ctx, slots, out)
		"job_talk": out["parts"].append(_p("job." + (mind.job if NPCGrammar.FRAGS.has("job." + mind.job) else "generic"), slots, mind))
		"buy_talk": _act_buy(mind, mem, a, ctx, slots, out)
		"sell_talk": _act_sell(mind, ctx, slots, out)
		"service_talk": _act_service(mind, mem, a, ctx, slots, out)
		"quest_talk": _act_quest(mind, mem, ctx, slots, out)
		"direction_talk": _act_direction(mind, a, ctx, slots, out)
		"rumor_talk": _act_rumor(mind, mem, slots, out)
		"lore_talk": _act_lore(mind, mem, slots, out)
		"danger_talk": _act_danger(mind, ctx, slots, out)
		"advice_talk": _act_advice(mind, ctx, slots, out)
		"compliment_reply": _act_compliment(mind, slots, out)
		"smalltalk": _act_smalltalk(mind, a, ctx, slots, out)
		"threat_react": _act_threat(mind, mem, ctx, slots, out)
		"insult_react": _act_insult(mind, mem, ctx, slots, out)
		"refuse_hostile":
			var banned: bool = int(mem["banned_day"]) >= int(ctx.get("day", 1))
			out["parts"].append(_p("refuse.banned" if banned else "refuse.hostile", slots, mind))
		"pending_yes": _act_pending(true, mind, mem, ctx, slots, out)
		"pending_no": _act_pending(false, mind, mem, ctx, slots, out)
		_: out["parts"].append(_p("smalltalk.generic", slots, mind))


func _act_for_intent(intent: String) -> String:
	match intent:
		"ask_direction": return "direction_talk"
		"ask_danger": return "danger_talk"
		"ask_how": return "how_are_you"
		"ask_identity": return "identity"
		"ask_job": return "job_talk"
		"ask_rumor": return "rumor_talk"
	return ""


# اختيار الفعل: أولويات الأمان والحالة النفسية ثم النية
func _choose_act(mind: NPCMind, a: Dictionary, mem: Dictionary, ctx: Dictionary) -> String:
	var intent: String = a["primary"]
	var day: int = int(ctx.get("day", 1))
	if a["length"] == 0:
		return "silence"
	var pending: Dictionary = mem["pending"]
	if not pending.is_empty() and (a["yes"] or a["no"]) and intent != "apologize":
		return "pending_yes" if (a["yes"] and not a["no"]) else "pending_no"
	if intent == "threat":
		return "threat_react"
	if intent == "insult":
		return "insult_react"
	var banned: bool = int(mem["banned_day"]) >= day
	if banned and intent != "apologize":
		return "refuse_hostile"
	if float(mind.mood["anger"]) > 0.75 and intent != "apologize" and intent != "thanks":
		return "refuse_hostile"
	var act: String = ""
	match intent:
		"buy", "ask_price", "haggle": act = "buy_talk"
		"sell": act = "sell_talk"
		"svc_heal", "svc_bless", "svc_craft": act = "service_talk"
		"ask_quest": act = "quest_talk"
		"ask_direction": act = "direction_talk"
		"ask_identity": act = "identity"
		"ask_job": act = "job_talk"
		"ask_how": act = "how_are_you"
		"ask_rumor": act = "rumor_talk"
		"ask_lore": act = "lore_talk"
		"ask_danger": act = "danger_talk"
		"ask_advice": act = "advice_talk"
		"greet": act = "greet"
		"farewell": act = "farewell"
		"thanks": act = "thanks_reply"
		"apologize": act = "apology_reply"
		"compliment": act = "compliment_reply"
		"smalltalk": act = "smalltalk"
	if act == "":
		# مفيش نية واضحة: الذكي بيفهم غالبًا، البسيط ممكن يتلخبط
		if rng.randf() > mind.comprehension() and a["length"] >= 2:
			return "confusion"
		return "smalltalk"
	if act in COMMERCE_ACTS and float(mem["affinity"]) < -0.6:
		return "refuse_hostile"
	return act


# ═══════════════ سياق الكلام (slots) ═══════════════

func _tone_key(mind: NPCMind, mem: Dictionary) -> String:
	var aff: float = float(mem["affinity"])
	var anger: float = float(mind.mood["anger"])
	var val: float = float(mind.mood["valence"])
	if anger > 0.6 or aff < -0.6:
		return "hostile"
	if aff < -0.2 or val < -0.25:
		return "cold"
	if aff > 0.35 and val > 0.05:
		return "warm"
	return "neutral"


func _soft_tone(mind: NPCMind, mem: Dictionary) -> String:
	var t: String = _tone_key(mind, mem)
	return "cold" if t == "hostile" else t


func _p(key: String, slots: Dictionary, mind: NPCMind) -> String:
	return NPCGrammar.pick(key, slots, mind.recent_replies, rng)


func _slots(mind: NPCMind, mem: Dictionary, ctx: Dictionary) -> Dictionary:
	var female: bool = str(ctx.get("player_gender", "male")) == "female"
	var hour: float = float(ctx.get("hour", 12.0))
	var period: String = _period(hour)
	var pname: String = str(ctx.get("player_name", "")).strip_edges()
	if pname == "":
		pname = "غريبة" if female else "غريب"
	var job_info: Dictionary = NPCLexicon.JOBS.get(mind.job, NPCLexicon.JOBS["villager"])
	return {
		"player": pname,
		"npc": mind.npc_name,
		"job": str(job_info["ar"]),
		"workplace": str(job_info["workplace"]),
		"addr": _address(mind, mem, female),
		"want": "عايزة" if female else "عايز",
		"need": "محتاجة" if female else "محتاج",
		"greeting_time": NPCGrammar.GREETING_TIME[period],
		"time_phrase": NPCGrammar.TIME_PHRASE[period],
		"weather": NPCGrammar.WEATHER_PHRASE.get(str(ctx.get("weather", "clear")), "الجو عادي"),
		"age": str(mind.age),
		"race_phrase": NPCLexicon.RACE_PHRASE.get(mind.race, ""),
		"player_race": NPCLexicon.RACE_PHRASE.get(str(ctx.get("player_race", "human")), ""),
		"topic": str(mem.get("last_topic", "")),
		"wealth": NPCLexicon.format_iron(int(ctx.get("wealth_iron", 0))),
	}


func _address(mind: NPCMind, mem: Dictionary, female: bool) -> String:
	var tone: String = _tone_key(mind, mem)
	var opts: Array = []
	if tone == "hostile":
		opts = ["يا هذه"] if female else ["يا هذا", "إنت"]
	elif float(mind.traits["formality"]) > 0.65 or mind.rank == "king":
		opts = ["سيدتي", "أيتها المسافرة"] if female else ["سيدي", "أيها المسافر"]
	elif tone == "warm":
		opts = ["يا غالية", "يا صاحبتي"] if female else ["يا صاحبي", "يا غالي", "يا بطل"]
	elif mind.eff_age >= 55.0:
		opts = ["يا بنتي"] if female else ["يا ابني"]
	else:
		opts = ["يا غريبة", "يا مسافرة"] if female else ["يا غريب", "يا مسافر"]
	return str(opts[rng.randi() % opts.size()])


static func _period(hour: float) -> String:
	if hour >= 5.0 and hour < 11.0:
		return "morning"
	if hour >= 11.0 and hour < 16.0:
		return "day"
	if hour >= 16.0 and hour < 20.0:
		return "evening"
	return "night"


# ═══════════════ أفعال الحوار ═══════════════

func _act_confusion(mind: NPCMind, a: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	out["parts"].append(_p("confusion.simple" if mind.intelligence < 0.5 else "confusion.elegant", slots, mind))
	if mind.intelligence >= 0.6 and a["items"].size() > 0:
		var info: Dictionary = NPCLexicon.ITEM_INFO[a["items"][0]]
		out["parts"].append("تقصد %s؟" % str(info["ar"]))


func _act_greet(mind: NPCMind, mem: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var tone: String = _tone_key(mind, mem)
	if int(mem["met"]) > 0 and str(mem["last_topic"]) != "" and tone != "hostile":
		out["parts"].append(_p("greet.return." + tone, slots, mind))
	else:
		out["parts"].append(_p("greet." + tone, slots, mind))
	if out["first"] and tone in ["warm", "neutral"]:
		out["parts"].append(_p("greet.first", slots, mind))
	# مهمة مفاجئة: الـ NPC نفسه يفتح الموضوع (بنسب وثيقتك) لو الجو ودّي
	if tone in ["warm", "neutral"] and rng.randf() < 0.35:
		var tier: String = _quest_roll(mind, mem, ctx)
		if tier != "" and int(mem["quest_given_day"]) != int(ctx.get("day", 1)):
			out["parts"].append(_p("quest.proactive", slots, mind))
			_offer_quest(mind, mem, tier, ctx, slots, out)
			return
	if mind.traits["talkativeness"] > 0.55 and rng.randf() < 0.4:
		out["parts"].append(_p("hook.need", slots, mind))


func _act_apology(mind: NPCMind, mem: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var angry: bool = float(mem["affinity"]) < -0.3 or float(mind.mood["anger"]) > 0.3
	if angry and rng.randf() > float(mind.traits["patience"]) + 0.2:
		mind.mood["anger"] = float(mind.mood["anger"]) * 0.8
		out["parts"].append(_p("sorry.grudge", slots, mind))
		return
	mind.mood["anger"] = float(mind.mood["anger"]) * 0.5
	mem["banned_day"] = -1
	mem["affinity"] = clampf(float(mem["affinity"]) + 0.15, -1.0, 1.0)
	out["parts"].append(_p("sorry.forgive", slots, mind))


func _act_how(mind: NPCMind, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	out["parts"].append(_p("how." + mind.emotion(), slots, mind))
	if rng.randf() < float(mind.traits["curiosity"]) * 0.7:
		out["parts"].append(_p("how.ask_back", slots, mind))


func _act_identity(mind: NPCMind, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	out["parts"].append(_p("who.me", slots, mind))
	if float(mind.traits["talkativeness"]) > 0.5 and rng.randf() < 0.5:
		if mind.eff_age >= 55.0:
			out["parts"].append(_p("who.age.old", slots, mind))
		elif mind.eff_age < 24.0:
			out["parts"].append(_p("who.age.young", slots, mind))
	if str(ctx.get("player_name", "")).strip_edges() == "" and rng.randf() < 0.6:
		out["parts"].append(_p("hook.ask_name", slots, mind))


# ── الشراء والمساومة ──
func _items_sold_by(job: String) -> Array:
	var ids: Array = []
	for id in NPCLexicon.ITEM_INFO:
		if job in NPCLexicon.ITEM_INFO[id]["sellers"]:
			ids.append(id)
	return ids


func _act_buy(mind: NPCMind, mem: Dictionary, a: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var items: Array = a["items"]
	var mine: Array = _items_sold_by(mind.job)
	var h0: Dictionary = mem["haggle"]
	if items.is_empty() and a["primary"] == "haggle" and not h0.is_empty():
		items = [str(h0["item"])]
		a["numbers"] = [int(h0.get("qty", 1))]
	if items.is_empty():
		if mine.is_empty():
			slots["trader_place"] = str(NPCLexicon.JOBS["trader"]["workplace"])
			slots["where"] = _where_to("trader", ctx)
			out["parts"].append(_p("buy.noshop", slots, mind))
		else:
			var names: Array = []
			for i in mini(3, mine.size()):
				names.append(str(NPCLexicon.ITEM_INFO[mine[i]]["ar"]))
			slots["sell_list"] = "، ".join(names)
			out["parts"].append(_p("buy.ask_what", slots, mind))
		return

	var item_id: String = str(items[0])
	var info: Dictionary = NPCLexicon.ITEM_INFO[item_id]
	slots["item"] = str(info["ar"])
	if not (mind.job in info["sellers"]):
		var other: String = str(info["sellers"][0])
		slots["other_place"] = str(NPCLexicon.JOBS[other]["workplace"])
		slots["where"] = _where_to(other, ctx)
		out["parts"].append(_p("buy.not_mine", slots, mind))
		return

	var qty: int = 1
	var nums: Array = a["numbers"]
	if nums.size() > 0 and int(nums[0]) >= 1 and int(nums[0]) <= 20:
		qty = int(nums[0])

	var offer: Dictionary = _price_offer(mind, mem, a, item_id, qty)
	var quote: int = int(offer["quote"])
	slots["price"] = NPCLexicon.format_iron(quote)
	if int(ctx.get("wealth_iron", 0)) < quote:
		mem["pending"] = {}
		out["parts"].append(_p("buy.too_poor", slots, mind))
		return
	mem["pending"] = {"type": "buy", "item": item_id, "qty": qty, "price": quote}
	match str(offer["state"]):
		"counter": out["parts"].append(_p("buy.counter", slots, mind))
		"last": out["parts"].append(_p("buy.last_price", slots, mind))
		"refuse": out["parts"].append(_p("buy.refuse_discount", slots, mind))
		_: out["parts"].append(_p("buy.quote", slots, mind))


# مساومة: السعر الأول يتأثر بجشع الـ NPC ومودته معاك، وكل جولة مساومة بتنزّل خطوة لحد الحد الأدنى،
# وصبر الـ NPC بيحدد كام جولة يتحمل.
func _price_offer(mind: NPCMind, mem: Dictionary, a: Dictionary, item_id: String, qty: int) -> Dictionary:
	var info: Dictionary = NPCLexicon.ITEM_INFO[item_id]
	var base: int = int(info["iron"]) * qty
	var greed: float = float(mind.traits["greed"])
	var aff: float = float(mem["affinity"])
	var tone: Dictionary = a["tone"]
	var courtesy: float = float(tone["politeness"]) - float(tone["rudeness"])
	var h: Dictionary = mem["haggle"]
	if h.is_empty() or str(h.get("item", "")) != item_id or int(h.get("qty", 1)) != qty:
		var start_mod: float = 1.0 + greed * 0.20 - aff * 0.10
		var floor_mod: float = 0.80 + greed * 0.15 - maxf(0.0, aff) * 0.10
		h = {"item": item_id, "qty": qty, "base": base,
			"quote": maxi(1, roundi(base * start_mod)), "floor": maxi(1, roundi(base * floor_mod)), "rounds": 0}
		mem["haggle"] = h
		return {"quote": int(h["quote"]), "state": "first"}
	if a["primary"] != "haggle":
		return {"quote": int(h["quote"]), "state": "first"}
	h["rounds"] = int(h["rounds"]) + 1
	var limit: int = 1 + roundi(float(mind.traits["patience"]) * 4.0)
	if int(h["rounds"]) > limit:
		return {"quote": int(h["quote"]), "state": "refuse"}
	var step: int = maxi(1, roundi(float(h["base"]) * (0.05 + 0.05 * maxf(0.0, courtesy + aff))))
	var new_quote: int = maxi(int(h["floor"]), int(h["quote"]) - step)
	h["quote"] = new_quote
	if new_quote <= int(h["floor"]):
		return {"quote": new_quote, "state": "last"}
	return {"quote": new_quote, "state": "counter"}


func _act_sell(mind: NPCMind, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	if mind.job in ["trader", "blacksmith", "farmer"]:
		out["parts"].append(_p("sell.interest", slots, mind))
		if mind.job == "trader":
			out["actions"].append({"type": "open_shop"})
	else:
		slots["trader_place"] = str(NPCLexicon.JOBS["trader"]["workplace"])
		slots["where"] = _where_to("trader", ctx)
		out["parts"].append(_p("sell.refuse", slots, mind))


# ── الخدمات: علاج / بركة / صناعة ──
func _act_service(mind: NPCMind, mem: Dictionary, a: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var greed: float = float(mind.traits["greed"])
	var aff: float = float(mem["affinity"])
	var disc: float = 1.0 - 0.2 * maxf(0.0, aff)
	match str(a["primary"]):
		"svc_heal":
			if not (mind.job in ["healer", "priest"]):
				slots["healer_place"] = str(NPCLexicon.JOBS["healer"]["workplace"])
				slots["where"] = _where_to("healer", ctx)
				out["parts"].append(_p("svc.heal.nobody", slots, mind))
				return
			var missing: int = int(ctx.get("hp_missing", 0))
			if missing <= 0 or float(ctx.get("hp_ratio", 1.0)) >= 0.95:
				out["parts"].append(_p("svc.heal.noneed", slots, mind))
				return
			var price: int = maxi(2, roundi(missing * 0.5 * (0.8 + greed * 0.4) * disc))
			slots["price"] = NPCLexicon.format_iron(price)
			mem["pending"] = {"type": "service", "kind": "heal", "price": price, "amount": missing}
			out["parts"].append(_p("svc.heal.quote", slots, mind))
		"svc_bless":
			if mind.job != "priest":
				slots["priest_place"] = str(NPCLexicon.JOBS["priest"]["workplace"])
				slots["where"] = _where_to("priest", ctx)
				out["parts"].append(_p("svc.bless.nobody", slots, mind))
				return
			var bprice: int = maxi(5, roundi(10.0 * (0.8 + greed * 0.4) * disc))
			slots["price"] = NPCLexicon.format_iron(bprice)
			mem["pending"] = {"type": "service", "kind": "bless", "price": bprice}
			out["parts"].append(_p("svc.bless.quote", slots, mind))
		_:
			if mind.job != "blacksmith":
				slots["smith_place"] = str(NPCLexicon.JOBS["blacksmith"]["workplace"])
				slots["where"] = _where_to("blacksmith", ctx)
				out["parts"].append(_p("svc.craft.nobody", slots, mind))
				return
			var cprice: int = maxi(5, roundi(15.0 * (0.8 + greed * 0.4) * disc))
			slots["price"] = NPCLexicon.format_iron(cprice)
			mem["pending"] = {"type": "service", "kind": "craft", "price": cprice}
			out["parts"].append(_p("svc.craft.quote", slots, mind))


# ── المهام ──
func _quest_roll(mind: NPCMind, mem: Dictionary, ctx: Dictionary) -> String:
	var day: int = int(ctx.get("day", 1))
	if int(mem["quest_day"]) == day:
		return str(mem["quest_tier"])
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%s|%d" % [mind.npc_id, str(ctx.get("player_id", "local")), day])
	var x: float = r.randf()
	var tier: String = ""
	if x < 0.01:
		tier = "legendary"
	elif x < 0.10:
		tier = "rare"
	elif x < 0.30:
		tier = "normal"
	elif x < 0.60:
		tier = "trivial"
	mem["quest_day"] = day
	mem["quest_tier"] = tier
	return tier


func _act_quest(mind: NPCMind, mem: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var day: int = int(ctx.get("day", 1))
	if float(mem["affinity"]) < -0.25 or float(mem["trust"]) < -0.2:
		out["parts"].append(_p("quest.decline_low", slots, mind))
		return
	if int(mem["quest_given_day"]) == day:
		out["parts"].append(_p("quest.already", slots, mind))
		return
	var tier: String = _quest_roll(mind, mem, ctx)
	if tier == "":
		out["parts"].append(_p("quest.none", slots, mind))
		return
	_offer_quest(mind, mem, tier, ctx, slots, out)


func _offer_quest(mind: NPCMind, mem: Dictionary, tier: String, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var q: Dictionary = _build_quest(mind, tier, ctx)
	slots["quest_desc"] = str(q["desc"])
	slots["reward"] = "%d خبرة و%s" % [int(q["xp"]), NPCLexicon.format_iron(int(q["coins_iron"]))]
	mem["pending"] = {"type": "quest", "quest": q}
	mem["quest_given_day"] = int(ctx.get("day", 1))
	out["parts"].append(_p("quest.offer." + tier, slots, mind))
	out["actions"].append({"type": "offer_quest", "quest": q})
	out["flags"].append("quest_offered")


# يبني مهمة بنفس شكل QuestSystem.quests (kill / talk_npc / buy_item)
func _build_quest(mind: NPCMind, tier: String, ctx: Dictionary) -> Dictionary:
	var t: Dictionary = QUEST_TIERS[tier]
	var xp_r: Array = t["xp"]
	var cnt_r: Array = t["count"]
	var xp: int = rng.randi_range(int(xp_r[0]), int(xp_r[1]))
	var count: int = rng.randi_range(int(cnt_r[0]), int(cnt_r[1]))
	var kind: String = "kill"
	var roll: float = rng.randf()
	if tier in ["trivial", "normal"]:
		if roll < 0.25:
			kind = "talk_npc"
		elif roll < 0.45:
			kind = "buy_item"
	var day: int = int(ctx.get("day", 1))
	var q: Dictionary = {
		"id": "npc_%s_%d" % [mind.npc_id, day], "type": kind, "progress": 0, "target": count,
		"xp": xp, "coins_iron": int(t["iron"]), "completed": false, "item": "", "giver": mind.npc_id, "tier": tier,
	}
	var lead: String = str(QUEST_LEAD.get(mind.job, "المنطقة مش مرتاحة"))
	match kind:
		"talk_npc":
			var others: Array = []
			for j in NPCLexicon.STALL_ORDER:
				if j != mind.job:
					others.append(j)
			var target_job: String = str(others[rng.randi() % others.size()])
			var tp: Dictionary = make_profile(target_job)
			q["target_id"] = tp["npc_id"]
			q["target"] = 1
			q["name"] = "رسالة إلى " + str(tp["name"])
			q["desc"] = "وصّل رسالة لـ%s في %s" % [str(tp["name"]), str(NPCLexicon.JOBS[target_job]["workplace"])]
		"buy_item":
			var ids: Array = ["bread", "water_flask", "small_health_potion"]
			var item_id: String = str(ids[rng.randi() % ids.size()])
			q["target_id"] = item_id
			q["target"] = 1
			q["name"] = "مشتريات لـ" + mind.npc_name
			q["desc"] = "%s، اشتريلي %s من السوق" % [lead, str(NPCLexicon.ITEM_INFO[item_id]["ar"])]
		_:
			var pool: Array = QUEST_KILL_BY_TIER[tier]
			var target_id: String = str(pool[rng.randi() % pool.size()])
			q["target_id"] = target_id
			q["name"] = "مهمة " + str(QUEST_KILL_NAMES[target_id])
			q["desc"] = "%s، اقتل %d من %s" % [lead, count, str(QUEST_KILL_NAMES[target_id])]
	return q


# ── الاتجاهات ──
func _act_direction(mind: NPCMind, a: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var pid: String = ""
	var places: Array = a["places"]
	var items: Array = a["items"]
	if places.size() > 0:
		pid = str(places[0])
	elif items.size() > 0:
		pid = str(NPCLexicon.ITEM_INFO[items[0]]["sellers"][0])
	if pid == "":
		out["parts"].append(_p("direction.ask_where", slots, mind))
		return
	if pid in ["forest", "cave", "gate"]:
		out["parts"].append(_p("direction.wild", slots, mind))
		return
	if pid == "square" or not NPCLexicon.JOBS.has(pid):
		out["parts"].append(_p("direction.unknown", slots, mind))
		return
	slots["place"] = str(NPCLexicon.JOBS[pid]["workplace"])
	var zone: Dictionary = ctx.get("zone", {})
	if pid == mind.job and str(zone.get("place", "")) == pid:
		out["parts"].append(_p("direction.here", slots, mind))
		return
	slots["where"] = _where_to(pid, ctx)
	slots["dist"] = _dist_to(pid, ctx)
	out["parts"].append(_p("direction.known", slots, mind))


# ── أخبار وحكايات ──
func _act_rumor(mind: NPCMind, mem: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var told: Array = mem["told"]
	var best: Dictionary = {}
	var best_w: float = -1.0
	for f in world_state["facts"]:
		if f["id"] in told:
			continue
		var w: float = float(f["weight"]) + rng.randf() * 0.3
		if w > best_w:
			best_w = w
			best = f
	if best.is_empty():
		out["parts"].append(_p("rumor.none", slots, mind))
		return
	told.append(best["id"])
	slots["fact"] = str(best["text"])
	out["parts"].append(_p("rumor.fact", slots, mind))


func _act_lore(mind: NPCMind, mem: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	if mind.intelligence < 0.35:
		out["parts"].append(_p("lore.unknown", slots, mind))
		return
	var depth: int = 1
	if mind.intelligence > 0.6:
		depth = 2
	if mind.intelligence > 0.85 or (mind.eff_age >= 55.0 and mind.intelligence > 0.5):
		depth = 3
	var told: Array = mem["told"]
	var pool: Array = []
	for d in range(1, depth + 1):
		var lines: Array = NPCLexicon.LORE[d]
		for i in lines.size():
			var key: String = "lore_%d_%d" % [d, i]
			if not (key in told):
				pool.append([key, lines[i]])
	if pool.is_empty():
		out["parts"].append(_p("lore.unknown", slots, mind))
		return
	var pick: Array = pool[rng.randi() % pool.size()]
	told.append(pick[0])
	out["parts"].append(_p("lore.intro", slots, mind))
	out["parts"].append(str(pick[1]))


func _act_danger(mind: NPCMind, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var zone: Dictionary = ctx.get("zone", {})
	var ztype: String = str(zone.get("type", "square"))
	var night: bool = _period(float(ctx.get("hour", 12.0))) == "night"
	if ztype in ["forest", "wild"]:
		out["parts"].append(_p("danger.forest", slots, mind))
	elif night:
		out["parts"].append(_p("danger.night", slots, mind))
	else:
		out["parts"].append(_p("danger.town", slots, mind))
	if int(ctx.get("level", 1)) < 5 and mind.intelligence > 0.4:
		out["parts"].append(_p("danger.newbie", slots, mind))


func _act_advice(mind: NPCMind, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	if mind.intelligence > 0.45 and float(ctx.get("hp_ratio", 1.0)) < 0.4:
		out["parts"].append(_p("advice.lowhp", slots, mind))
	elif mind.intelligence > 0.45 and float(ctx.get("hunger", 100.0)) < 35.0:
		out["parts"].append(_p("advice.hungry", slots, mind))
	elif int(ctx.get("level", 1)) < 4:
		out["parts"].append(_p("advice.newbie", slots, mind))
	else:
		var tips: Array = NPCLexicon.JOB_TIPS.get(mind.job, NPCLexicon.JOB_TIPS["generic"])
		slots["tip"] = str(tips[rng.randi() % tips.size()])
		out["parts"].append(_p("advice.wrap", slots, mind))


func _act_compliment(mind: NPCMind, slots: Dictionary, out: Dictionary) -> void:
	var key: String = "compliment.warm"
	if float(mind.traits["pride"]) > 0.65:
		key = "compliment.proud"
	elif float(mind.traits["warmth"]) < 0.4:
		key = "compliment.shy"
	out["parts"].append(_p(key, slots, mind))


func _act_smalltalk(mind: NPCMind, a: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	if float(a["tone"]["aggression"]) > 0.4 or float(a["tone"]["rudeness"]) > 0.5:
		out["parts"].append(_p("smalltalk.calm", slots, mind))
		return
	var zone: Dictionary = ctx.get("zone", {})
	var ztype: String = str(zone.get("type", "square"))
	var weather: String = str(ctx.get("weather", "clear"))
	var night: bool = _period(float(ctx.get("hour", 12.0))) == "night"
	var morning: bool = _period(float(ctx.get("hour", 12.0))) == "morning"
	var choices: Array = []   # [مفتاح، وزن]
	choices.append(["smalltalk.zone." + ztype, 1.0])
	choices.append(["smalltalk.weather." + (weather if weather != "wind" else "clear"), 1.3 if weather != "clear" else 0.6])
	if night:
		choices.append(["smalltalk.time.night", 1.0])
	if morning:
		choices.append(["smalltalk.time.morning", 0.7])
	choices.append(["smalltalk.generic", 0.5])
	var total: float = 0.0
	for c in choices:
		total += float(c[1])
	var x: float = rng.randf() * total
	var key: String = "smalltalk.generic"
	for c in choices:
		x -= float(c[1])
		if x <= 0.0:
			key = str(c[0])
			break
	if not NPCGrammar.FRAGS.has(key):
		key = "smalltalk.generic"
	out["parts"].append(_p(key, slots, mind))


func _act_threat(mind: NPCMind, mem: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var bravery: float = float(mind.traits["bravery"])
	var fighter: bool = mind.rank == "fighter" or mind.job in ["warrior", "guard", "king", "leader"]
	if fighter or bravery > 0.65:
		out["parts"].append(_p("threat.brave", slots, mind))
		out["actions"].append({"type": "alert_guards"})
	elif bravery < 0.35:
		out["parts"].append(_p("threat.afraid", slots, mind))
		out["flags"].append("flee")
	else:
		out["parts"].append(_p("threat.firm", slots, mind))
	mem["banned_day"] = int(ctx.get("day", 1))
	mem["pending"] = {}


func _act_insult(mind: NPCMind, mem: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	mem["insults"] = int(mem["insults"]) + 1
	mem["pending"] = {}
	var patience: float = float(mind.traits["patience"])
	if int(mem["insults"]) <= 1 and patience > 0.4:
		out["parts"].append(_p("insult.warn" if float(mind.traits["pride"]) > 0.5 else "insult.disappointed", slots, mind))
	else:
		out["parts"].append(_p("insult.angry", slots, mind))
		mem["banned_day"] = int(ctx.get("day", 1))


# ── رد على "ايوه/لا" لعرض معلّق (شراء/مهمة/خدمة) ──
func _act_pending(yes: bool, mind: NPCMind, mem: Dictionary, ctx: Dictionary, slots: Dictionary, out: Dictionary) -> void:
	var p: Dictionary = mem["pending"]
	mem["pending"] = {}
	if not yes:
		out["parts"].append(_p("quest.declined" if str(p.get("type", "")) == "quest" else "buy.decline", slots, mind))
		return
	match str(p.get("type", "")):
		"buy":
			var info: Dictionary = NPCLexicon.ITEM_INFO[p["item"]]
			slots["item"] = str(info["ar"])
			if _exec_buy(ctx, str(p["item"]), int(p["qty"]), int(p["price"])):
				mem["haggle"] = {}
				out["parts"].append(_p("buy.done", slots, mind))
				out["flags"].append("purchase_done")
			else:
				out["parts"].append(_p("buy.failed", slots, mind))
		"quest":
			var q: Dictionary = p["quest"]
			if _exec_register_quest(ctx, q):
				out["parts"].append(_p("quest.accepted", slots, mind))
				out["flags"].append("quest_accepted")
				out["actions"].append({"type": "quest_registered", "quest_id": q["id"]})
			else:
				out["parts"].append(_p("quest.accepted", slots, mind))
				out["actions"].append({"type": "quest_accepted_unregistered", "quest": q})
		"service":
			var price: int = int(p["price"])
			var kind: String = str(p["kind"])
			if kind == "craft":
				out["parts"].append(_p("svc.craft.done", slots, mind))
				out["actions"].append({"type": "craft_order"})
			elif _exec_service(ctx, kind, price, int(p.get("amount", 0))):
				out["parts"].append(_p("svc.heal.done" if kind == "heal" else "svc.bless.done", slots, mind))
				out["actions"].append({"type": kind, "paid": price})
			else:
				out["parts"].append(_p("buy.failed", slots, mind))
		_:
			out["parts"].append(_p("smalltalk.generic", slots, mind))


# ═══════════════ تعليقات سياقية ═══════════════

func _context_remark(mind: NPCMind, mem: Dictionary, ctx: Dictionary, slots: Dictionary) -> String:
	if mind.intelligence < 0.45:
		return ""
	var cands: Array = []
	if mind.intelligence >= 0.6:
		if float(ctx.get("hp_ratio", 1.0)) < 0.35:
			cands.append("remark.lowhp")
		if float(ctx.get("hunger", 100.0)) < 30.0:
			cands.append("remark.hungry")
	var lvl: int = int(ctx.get("level", 1))
	if lvl <= 3:
		cands.append("remark.newbie")
	elif lvl >= 30:
		cands.append("remark.veteran")
	var zone: Dictionary = ctx.get("zone", {})
	var night: bool = _period(float(ctx.get("hour", 12.0))) == "night"
	if night and str(zone.get("type", "")) in ["forest", "wild"]:
		cands.append("remark.night_forest")
	if str(ctx.get("weather", "clear")) in ["rain", "storm"]:
		cands.append("remark.rain")
	var wealth: int = int(ctx.get("wealth_iron", 0))
	if wealth >= 100000:
		cands.append("remark.rich")
	elif wealth < 5:
		cands.append("remark.poor")
	if str(ctx.get("player_race", "human")) == mind.race:
		cands.append("remark.race.same")
	elif rng.randf() < 0.4:
		cands.append("remark.race.diff")
	if int(mem["met"]) > 1 and str(mem["last_topic"]) != "":
		cands.append("remark.callback")
	if cands.is_empty():
		return ""
	return _p(str(cands[rng.randi() % cands.size()]), slots, mind)


# ═══════════════ تنفيذ آثار جانبية (شراء/علاج/تسجيل مهمة) ═══════════════
# لو مفيش لاعب فعلي في الـ ctx (محاكاة/اختبار) بنعتبر العملية نجحت بدون تعديل أي حاجة.

func _exec_buy(ctx: Dictionary, item_id: String, qty: int, price: int) -> bool:
	var player = ctx.get("player_node", null)
	if player == null or not is_instance_valid(player):
		return true
	var cs := _autoload("CurrencySystem")
	var inv = player.get_node_or_null("Inventory")
	if cs == null or inv == null or not cs.has_method("try_spend_iron_value") or not inv.has_method("add_item"):
		return false
	if not cs.try_spend_iron_value(price):
		return false
	var info: Dictionary = NPCLexicon.ITEM_INFO[item_id]
	if not inv.add_item(item_id, str(info["ar"]), str(info["type"]), qty):
		if cs.has_method("add_iron_value"):
			cs.add_iron_value(price)
		return false
	_report_event(player, "buy_item", item_id)
	return true


func _exec_service(ctx: Dictionary, kind: String, price: int, amount: int) -> bool:
	var player = ctx.get("player_node", null)
	if player == null or not is_instance_valid(player):
		return true
	var cs := _autoload("CurrencySystem")
	if cs == null or not cs.has_method("try_spend_iron_value"):
		return false
	if not cs.try_spend_iron_value(price):
		return false
	if kind == "heal":
		var stats = player.get_node_or_null("PlayerStats")
		if stats != null and stats.has_method("heal"):
			stats.heal(amount)
	return true


func _exec_register_quest(ctx: Dictionary, quest: Dictionary) -> bool:
	var player = ctx.get("player_node", null)
	if player == null or not is_instance_valid(player):
		return true
	var qs = player.get_node_or_null("QuestSystem")
	if qs == null:
		return false
	var q: Dictionary = quest.duplicate(true)
	var qid: String = str(q["id"])
	q.erase("id")
	qs.quests[qid] = q
	quest_offered.emit(str(quest.get("giver", "")), quest)
	return true


func _report_event(player: Node, event_type: String, target_id: String) -> void:
	var qs = player.get_node_or_null("QuestSystem")
	if qs != null and qs.has_method("report_event"):
		qs.report_event(event_type, target_id)


# ═══════════════ المكان والاتجاهات ═══════════════

func _zone_at(pos: Vector3) -> Dictionary:
	var flat := Vector2(pos.x, pos.z)
	var count: int = NPCLexicon.STALL_ORDER.size()
	for i in count:
		var ang: float = (TAU / float(count)) * float(i)
		var sp := Vector2(cos(ang), sin(ang)) * TOWN_RADIUS * STALL_RADIUS_FACTOR
		if flat.distance_to(sp) < 6.0:
			return {"type": "stall", "place": NPCLexicon.STALL_ORDER[i]}
	var d: float = flat.length()
	if d < TOWN_RADIUS:
		return {"type": "square", "place": "square"}
	if d < TOWN_RADIUS + 25.0:
		return {"type": "forest", "place": "forest"}
	return {"type": "wild", "place": "wild"}


func place_position(place_id: String) -> Variant:
	var idx: int = NPCLexicon.STALL_ORDER.find(place_id)
	if idx == -1:
		return null
	var count: int = NPCLexicon.STALL_ORDER.size()
	var ang: float = (TAU / float(count)) * float(idx)
	return Vector3(cos(ang), 0.0, sin(ang)) * TOWN_RADIUS * STALL_RADIUS_FACTOR


func _where_to(place_id: String, ctx: Dictionary) -> String:
	var tp = place_position(place_id)
	if tp == null:
		return "في الساحة"
	var from: Vector3 = ctx.get("player_pos", Vector3.ZERO)
	var basis: Basis = ctx.get("player_basis", Basis.IDENTITY)
	var delta: Vector3 = tp - from
	delta.y = 0.0
	var local: Vector3 = basis.inverse() * delta     # +x يمين، -z قدّام (قواعد Godot)
	var front: bool = local.z < 0.0
	var right: bool = local.x > 0.0
	if absf(local.x) < absf(local.z) * 0.4:
		return "قدامك على طول" if front else "وراك"
	if absf(local.z) < absf(local.x) * 0.4:
		return "على يمينك" if right else "على شمالك"
	var fb: String = "قدامك" if front else "ورا"
	return "%s ناحية %s" % [fb, "اليمين" if right else "الشمال"]


func _dist_to(place_id: String, ctx: Dictionary) -> String:
	var tp = place_position(place_id)
	if tp == null:
		return ""
	var from: Vector3 = ctx.get("player_pos", Vector3.ZERO)
	var dist: float = Vector2(tp.x - from.x, tp.z - from.z).length()
	if dist < 8.0:
		return "خطوات قليلة"
	if dist < 20.0:
		return "مسافة قصيرة"
	return "بعيد شوية"


# ═══════════════ قرارات النشاط (بديل الـ AI لـ NPCBehaviorController) ═══════════════
# Utility AI: كل نشاط له درجة من (جدول شغل المهنة، الوقت، الفضول/الدفء/الشجاعة، قرب اللاعب، الخطر).

func decide_action(profile: Dictionary, ctx: Dictionary) -> Dictionary:
	var mind: NPCMind = mind_for(profile)
	var hour: float = float(ctx.get("hour", 12.0))
	var night: bool = hour < 5.5 or hour > 19.5
	var info: Dictionary = NPCLexicon.JOBS.get(mind.job, NPCLexicon.JOBS["villager"])
	var sched: Array = info["schedule"]
	var on_shift: bool = hour >= float(sched[0]) and hour <= float(sched[1])
	var s: Dictionary = {"idle": 0.25, "wander": 0.20, "work": 0.0, "greet_nearby": 0.0, "flee": 0.0}
	if on_shift:
		s["work"] = 0.55 + float(mind.traits["diligence"]) * 0.35
	if night:
		s["idle"] += 0.5
		s["wander"] -= 0.15
	else:
		s["wander"] += float(mind.traits["curiosity"]) * 0.3
	var pd: float = float(ctx.get("player_dist", 999.0))
	if pd < 9.0 and not night and float(mind.traits["warmth"]) > 0.4:
		s["greet_nearby"] = 0.45 + float(mind.traits["warmth"]) * 0.3
	var danger: float = float(ctx.get("danger", 0.0))
	if danger > 0.0:
		var fear_scale: float = 0.5 if mind.rank == "fighter" else 1.0
		s["flee"] = danger * (1.3 - float(mind.traits["bravery"])) * fear_scale
	for k in s.keys():
		s[k] = float(s[k]) + rng.randf() * 0.15
	var best: String = "idle"
	var best_v: float = -INF
	for k in s.keys():
		if float(s[k]) > best_v:
			best_v = float(s[k])
			best = str(k)
	var line: String = ""
	if best == "greet_nearby" or (pd < 8.0 and rng.randf() < float(mind.traits["talkativeness"]) * 0.25):
		var mem: Dictionary = mind.mem(str(ctx.get("player_id", "local")))
		var slots: Dictionary = _slots(mind, mem, ctx)
		var key: String = "ambient.greet" if best == "greet_nearby" else ("ambient.night" if night else "ambient.generic")
		line = _p(key, slots, mind)
	return {"action": best, "line": line, "emotion": mind.emotion()}


# ═══════════════ سياق اللعبة الفعلي ═══════════════

static func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(node_name)


static func _prop(obj: Object, prop_name: String, default_value: Variant) -> Variant:
	if obj == null:
		return default_value
	var v = obj.get(prop_name)
	return default_value if v == null else v


func _time_info() -> Dictionary:
	var info := {"hour": 12.0, "day": 1, "season": ""}
	var tm := _autoload("TimeManager")
	if tm != null:
		info["hour"] = float(_prop(tm, "game_hour", 12.0))
		info["day"] = int(_prop(tm, "game_day", 1))
		if tm.has_method("get_current_season"):
			info["season"] = str(tm.get_current_season())
	return info


func _player_id() -> String:
	var nm := _autoload("NetworkManager")
	if nm != null:
		var sess = _prop(nm, "session", null)
		if sess != null:
			var uid = sess.get("user_id")
			if uid != null and str(uid) != "":
				return str(uid)
	return "local_player"


func build_context(npc_node: Node, player: Node) -> Dictionary:
	var ti := _time_info()
	var ctx: Dictionary = {
		"player_id": _player_id(),
		"player_name": str(player_info.get("name", "")),
		"player_gender": str(player_info.get("gender", "male")),
		"player_race": str(player_info.get("race", "human")),
		"hour": ti["hour"], "day": ti["day"], "season": ti["season"],
		"weather": str(world_state.get("weather", "clear")),
		"zone": {"type": "square", "place": "square"},
		"level": 1, "hp_ratio": 1.0, "hp_missing": 0, "hunger": 100.0, "wealth_iron": 0,
		"now_sec": Time.get_ticks_msec() / 1000.0,
		"npc_pos": Vector3.ZERO, "player_pos": Vector3.ZERO, "player_basis": Basis.IDENTITY, "danger": 0.0,
	}
	if npc_node is Node3D:
		ctx["npc_pos"] = (npc_node as Node3D).global_position
		ctx["zone"] = _zone_at(ctx["npc_pos"])
		ctx["danger"] = _danger_near(ctx["npc_pos"])
	if player != null:
		if player is Node3D:
			ctx["player_pos"] = (player as Node3D).global_position
			ctx["player_basis"] = (player as Node3D).global_transform.basis
		var stats = player.get_node_or_null("PlayerStats")
		if stats != null:
			ctx["level"] = int(_prop(stats, "level", 1))
			var mh: int = int(_prop(stats, "max_hp", 1))
			var hp: int = int(_prop(stats, "hp", mh))
			ctx["hp_ratio"] = float(hp) / float(maxi(1, mh))
			ctx["hp_missing"] = maxi(0, mh - hp)
			ctx["hunger"] = float(_prop(stats, "hunger", 100.0))
			var rid: String = str(_prop(stats, "race_id", ""))
			if rid != "":
				ctx["player_race"] = rid
	var cs := _autoload("CurrencySystem")
	if cs != null and cs.has_method("total_in_iron"):
		ctx["wealth_iron"] = int(cs.total_in_iron())
	return ctx


func _context_for_profile(profile: Dictionary) -> Dictionary:
	var node := _node_of(profile)
	return build_context(node, _find_player())


func _action_context(profile: Dictionary) -> Dictionary:
	var ti := _time_info()
	var ctx: Dictionary = {
		"hour": ti["hour"], "day": ti["day"], "weather": str(world_state.get("weather", "clear")),
		"player_id": _player_id(), "player_name": "", "player_gender": str(player_info.get("gender", "male")),
		"player_race": str(player_info.get("race", "human")),
		"zone": {"type": "square", "place": "square"}, "player_dist": 999.0, "danger": 0.0,
	}
	var node := _node_of(profile)
	if node is Node3D:
		var pos: Vector3 = (node as Node3D).global_position
		ctx["zone"] = _zone_at(pos)
		ctx["danger"] = _danger_near(pos)
		var player := _find_player()
		if player is Node3D:
			ctx["player_dist"] = pos.distance_to((player as Node3D).global_position)
	return ctx


func _danger_near(pos: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var count: int = 0
	var list: Array = get_tree().get_nodes_in_group("monsters")
	if list.size() > 200:
		return 0.0
	for m in list:
		if not (m is Node3D) or not m.visible:
			continue
		if bool(_prop(m, "is_passive", true)):
			continue
		if pos.distance_to((m as Node3D).global_position) < 8.0:
			count += 1
	return clampf(float(count) * 0.35, 0.0, 1.0)


func _find_player() -> Node:
	if not is_inside_tree():
		return null
	var arr: Array = get_tree().get_nodes_in_group("players")
	if arr.is_empty():
		return null
	return arr[0]


func _node_of(profile: Dictionary) -> Node:
	var id: String = str(profile.get("npc_id", ""))
	if not _nodes.has(id):
		return null
	var n = instance_from_id(int(_nodes[id]))
	if n != null and is_instance_valid(n):
		return n
	return null


func _profile_of(node: Node) -> Dictionary:
	if node.has_meta("profile"):
		return node.get_meta("profile")
	var p: Dictionary = {"npc_id": "node_%d" % node.get_instance_id(), "name": str(_prop(node, "npc_name", node.name)), "job": "villager"}
	if node.is_in_group("traders"):
		p["job"] = "trader"
	node.set_meta("profile", p)
	return p


func _pick_target(player: Node, text: String) -> Node:
	if not (player is Node3D):
		return null
	var ppos: Vector3 = (player as Node3D).global_position
	var norm: String = SpeechAnalyzer.normalize(text)
	var best: Node = null
	var best_d: float = INF
	var named: Node = null
	var seen: Dictionary = {}
	for g in ["npcs", "traders"]:
		for n in get_tree().get_nodes_in_group(g):
			if not (n is Node3D) or not n.is_inside_tree() or seen.has(n.get_instance_id()):
				continue
			seen[n.get_instance_id()] = true
			var d: float = ppos.distance_to((n as Node3D).global_position)
			if d > talk_radius:
				continue
			var nm: String = SpeechAnalyzer.normalize(str(_profile_of(n).get("name", "")))
			if nm != "" and norm.contains(nm):
				named = n
			if d < best_d:
				best_d = d
				best = n
	if named != null:
		return named
	if best == null:
		return null
	var now: float = Time.get_ticks_msec() / 1000.0
	if str(_profile_of(best).get("npc_id", "")) == _convo_npc and now < _convo_until:
		return best
	if best_d <= near_radius:
		return best
	return null


# ═══════════════ التسليم: تأخير طبيعي + فقاعة كلام + شات ═══════════════

func _deliver(target: Node, profile: Dictionary, result: Dictionary) -> void:
	var text: String = str(result["text"])
	var npc_id: String = str(profile.get("npc_id", ""))
	if reply_delay_enabled and is_inside_tree():
		var mind: NPCMind = mind_for(profile)
		var delay: float = clampf(0.35 + text.length() * 0.012 + (1.0 - mind.intelligence) * 0.3, 0.3, 1.8)
		await get_tree().create_timer(delay).timeout
	var nm := _autoload("NetworkManager")
	if nm != null and nm.has_signal("chat_message_received"):
		nm.emit_signal("chat_message_received", str(profile.get("name", "NPC")), text)
	if show_bubbles and is_instance_valid(target):
		_show_bubble(target, text)
	_apply_actions(result, target)
	response_ready.emit(npc_id, text)
	response_detail.emit(npc_id, result)


func _apply_actions(result: Dictionary, target: Node) -> void:
	var player := _find_player()
	for act in result["actions"]:
		match str(act.get("type", "")):
			"open_shop":
				if player != null:
					for tr in get_tree().get_nodes_in_group("traders"):
						if tr.has_method("try_open_shop_for"):
							tr.try_open_shop_for(player)
			"alert_guards":
				for gd in get_tree().get_nodes_in_group("guards"):
					if gd.has_method("alert") and player != null:
						gd.alert(player)


func _show_bubble(node: Node, text: String) -> void:
	if not (node is Node3D):
		return
	var old := node.get_node_or_null("SpeechBubble")
	if old != null:
		old.queue_free()
	var lbl := Label3D.new()
	lbl.name = "SpeechBubble"
	lbl.text = text
	lbl.pixel_size = 0.006
	lbl.font_size = 32
	lbl.width = 520.0
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.outline_size = 10
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 1.9, 0)
	lbl.modulate = Color(1.0, 0.97, 0.85)
	node.add_child(lbl)
	var life: float = 3.0 + float(text.length()) * 0.05
	get_tree().create_timer(life).timeout.connect(_free_node.bind(lbl))


func _free_node(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()


func _emit_response(npc_id: String, result: Dictionary) -> void:
	response_ready.emit(npc_id, str(result["text"]))
	response_detail.emit(npc_id, result)


func _emit_action(npc_id: String, res: Dictionary) -> void:
	action_ready.emit(npc_id, res)


# ═══════════════ حفظ الذاكرة (محلي على الجهاز) ═══════════════

func _autosave() -> void:
	if _dirty:
		_save_memory()


func _save_memory() -> void:
	var data: Dictionary = _saved.duplicate(true)
	for id in minds:
		var m: NPCMind = minds[id]
		if m.memory.size() > 0:
			data[id] = m.to_dict()
	var f := FileAccess.open(MEMORY_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	_dirty = false


func _load_memory() -> void:
	if not FileAccess.file_exists(MEMORY_PATH):
		return
	var f := FileAccess.open(MEMORY_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_saved = parsed
