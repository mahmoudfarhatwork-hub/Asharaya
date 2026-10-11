class_name NPCMind
extends RefCounted
# NPCMind.gd — "عقل" كل NPC: شخصية ثابتة + ذكاء (حسب الرتبة والمهنة والعمر) + مزاج متغير + ذاكرة لكل لاعب.
# الشخصية بتتولد من npc_id (نفس الـ NPC = نفس الطباع دايمًا)، والمزاج والذاكرة بيتغيروا مع الكلام.

const TRAIT_KEYS := ["warmth", "patience", "curiosity", "greed", "bravery", "formality",
	"humor", "talkativeness", "pride", "honesty", "diligence"]

var npc_id: String = ""
var npc_name: String = "مجهول"
var job: String = "villager"
var rank: String = "crowd"
var race: String = "human"
var gender: String = "male"
var age: int = 30            # العمر المعروض
var eff_age: float = 30.0    # العمر بالمكافئ البشري (الإلف عمرهم أطول، إلخ)
var intelligence: float = 0.5
var traits: Dictionary = {}
var mood: Dictionary = {"valence": 0.0, "arousal": 0.2, "fear": 0.0, "anger": 0.0}
var baseline_valence: float = 0.0
var memory: Dictionary = {}          # player_id -> Dictionary
var recent_replies: Array = []       # آخر ردود (لمنع التكرار)
var _last_time_hours: float = -1.0


static func create(profile: Dictionary) -> NPCMind:
	var m := NPCMind.new()
	m.npc_id = str(profile.get("npc_id", "npc_%d" % randi()))
	m.npc_name = str(profile.get("name", "مجهول"))
	m.job = NPCLexicon.job_id(str(profile.get("job", profile.get("role", "villager"))))
	m.race = NPCLexicon.race_id(str(profile.get("race", profile.get("faction", "human"))))
	m.gender = str(profile.get("gender", "male"))

	var r := RandomNumberGenerator.new()
	r.seed = hash(m.npc_id)
	var job_info: Dictionary = NPCLexicon.JOBS.get(m.job, NPCLexicon.JOBS["villager"])
	m.rank = str(profile.get("rank", job_info["rank"]))

	var life: float = float(NPCLexicon.LIFESPAN.get(m.race, 1.0))
	var age_range: Array = job_info["age"]
	var human_age: int = r.randi_range(int(age_range[0]), int(age_range[1]))
	m.age = int(profile.get("age", int(human_age * life)))
	m.eff_age = float(m.age) / life

	# الذكاء: مدى الرتبة (من وثيقتك) + تعديل بسيط بالعمر
	var rr: Array = NPCLexicon.INTEL_RANGE.get(m.rank, [0.3, 0.5])
	var base: float = lerpf(float(rr[0]), float(rr[1]), r.randf())
	var age_adj: float = 0.0
	if m.eff_age < 16.0:
		age_adj = -0.12
	elif m.eff_age < 22.0:
		age_adj = -0.04
	elif m.eff_age >= 45.0 and m.eff_age < 70.0:
		age_adj = 0.03
	elif m.eff_age >= 80.0:
		age_adj = -0.06
	m.intelligence = clampf(base + age_adj, 0.05, 1.0)

	# الطباع: عشوائي ثابت + انحياز المهنة + انحياز العرق + انحياز العمر
	for k in TRAIT_KEYS:
		var v: float = 0.5 + r.randf_range(-0.3, 0.3)
		v += _bias(NPCLexicon.JOB_TRAIT_BIAS, m.job, k)
		v += _bias(NPCLexicon.RACE_TRAIT_BIAS, m.race, k)
		v += _age_bias(m.eff_age, k)
		m.traits[k] = clampf(v, 0.02, 0.98)

	m.baseline_valence = (float(m.traits["warmth"]) - 0.5) * 0.6
	m.mood["valence"] = m.baseline_valence
	return m


static func _bias(table: Dictionary, key: String, trait_key: String) -> float:
	var d: Dictionary = table.get(key, {})
	return float(d.get(trait_key, 0.0))


static func _age_bias(a: float, trait_key: String) -> float:
	if a >= 55.0:
		match trait_key:
			"patience": return 0.15
			"formality": return 0.10
			"talkativeness": return 0.10
	elif a < 22.0:
		match trait_key:
			"patience": return -0.15
			"curiosity": return 0.15
			"formality": return -0.15
	return 0.0


# ───────── الذاكرة لكل لاعب ─────────
func mem(player_id: String) -> Dictionary:
	if not memory.has(player_id):
		memory[player_id] = {
			"met": 0, "affinity": 0.0, "trust": 0.0, "last_day": -1, "last_topic": "",
			"topics": {}, "insults": 0, "banned_day": -1, "pending": {}, "quest_day": -1,
			"quest_tier": "", "quest_given_day": -1, "haggle": {}, "session_until": 0.0,
			"last_text": "", "told": [],
		}
	return memory[player_id]


# ───────── المزاج ─────────
func decay_to(day: int, hour: float) -> void:
	var now_h: float = float(day) * 24.0 + hour
	if _last_time_hours < 0.0:
		_last_time_hours = now_h
		return
	var elapsed: float = maxf(0.0, now_h - _last_time_hours)
	_last_time_hours = now_h
	var f: float = exp(-elapsed * 0.35)
	mood["valence"] = lerpf(baseline_valence, float(mood["valence"]), f)
	mood["arousal"] = lerpf(0.2, float(mood["arousal"]), f)
	mood["fear"] = lerpf(0.0, float(mood["fear"]), f)
	mood["anger"] = lerpf(0.0, float(mood["anger"]), f)


func emotion() -> String:
	if float(mood["fear"]) > 0.55:
		return "afraid"
	if float(mood["anger"]) > 0.55:
		return "angry"
	if float(mood["valence"]) > 0.35:
		return "good"
	if float(mood["valence"]) < -0.3:
		return "bad"
	return "ok"


# أثر كلام اللاعب على الـ NPC. بيرجّع ملخص للديبج. a = نتيجة SpeechAnalyzer
func apply_stimulus(a: Dictionary, m: Dictionary) -> Dictionary:
	var tone: Dictionary = a["tone"]
	var primary: String = a["primary"]
	var pos: float = float(tone["warmth"]) * 0.10 + float(tone["politeness"]) * 0.08
	var neg: float = float(tone["rudeness"]) * 0.18 + float(tone["aggression"]) * 0.22
	match primary:
		"compliment":
			pos += 0.10 * (1.0 - 0.3 * float(traits["pride"]))
		"thanks":
			pos += 0.06
		"apologize":
			pos += 0.08
		"insult":
			neg += 0.20
		"threat":
			neg += 0.35
	# حساسية الإهانة بتزيد لو الصبر قليل، والإيجابيات بتتأثر بدفء الشخصية
	var sens: float = 1.0 + (1.0 - float(traits["patience"])) * 0.8
	var warmth_gain: float = 0.6 + float(traits["warmth"])
	var d: float = pos * warmth_gain - neg * sens
	# تكرار نفس الرسالة (سبام) بيضايق
	if a["norm"] != "" and a["norm"] == m["last_text"]:
		d -= 0.05 * sens
	m["last_text"] = a["norm"]

	mood["valence"] = clampf(float(mood["valence"]) + d * 1.2, -1.0, 1.0)
	mood["arousal"] = clampf(float(mood["arousal"]) + float(tone["aggression"]) * 0.4 + float(tone["urgency"]) * 0.2 - 0.02, 0.0, 1.0)
	mood["anger"] = clampf(float(mood["anger"]) + (neg * 0.6 if neg > 0.0 else -0.08), 0.0, 1.0)
	if primary == "threat":
		mood["fear"] = clampf(float(mood["fear"]) + 0.5 * (1.0 - float(traits["bravery"])), 0.0, 1.0)
	else:
		mood["fear"] = clampf(float(mood["fear"]) - 0.05, 0.0, 1.0)

	m["affinity"] = clampf(float(m["affinity"]) + d, -1.0, 1.0)
	if neg <= 0.0 and pos > 0.0:
		m["trust"] = clampf(float(m["trust"]) + 0.02, -1.0, 1.0)
	elif primary == "insult" or primary == "threat":
		m["trust"] = clampf(float(m["trust"]) - 0.08, -1.0, 1.0)
	return {"delta": d, "pos": pos, "neg": neg}


# فرصة فهم الجملة المبهمة (ذكي = يفهم أكتر)
func comprehension() -> float:
	return clampf(0.50 + intelligence * 0.50, 0.0, 1.0)


func remember_reply(text: String) -> void:
	recent_replies.append(text)
	while recent_replies.size() > 6:
		recent_replies.pop_front()


# ───────── حفظ/تحميل ─────────
func to_dict() -> Dictionary:
	return {"mood": mood, "memory": memory, "recent": recent_replies}


func load_dict(d: Dictionary) -> void:
	var mo: Dictionary = d.get("mood", {})
	for k in mo:
		mood[k] = mo[k]
	memory = d.get("memory", {})
	recent_replies = d.get("recent", [])
