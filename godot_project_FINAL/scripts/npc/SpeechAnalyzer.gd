class_name SpeechAnalyzer
extends RefCounted
# SpeechAnalyzer.gd — يحلل كلام اللاعب (عامية مصرية / فصحى / إنجليزي / فرانكو بسيط)
# ويطلّع: النية، النبرة (أدب/عدوانية/ود/خوف/استعجال)، الأصناف والأماكن والأرقام المذكورة،
# وهل هو سؤال أو صراخ أو ضحك. مفيش AI: قواميس + تطبيع إملائي + مطابقة تقريبية للأخطاء.

const PHRASE_WEIGHT := 2.2
const WORD_WEIGHT := 1.0
const FUZZY_WEIGHT := 0.85
const FUZZY_CACHE_MAX := 3000
const EXTRA_PATH := "res://data/npc_lexicon_extra.json"

# أفضلية بسيطة لما نيّتين متقاربتين (الأخطر/الأوضح يكسب)
const PRIORITY := {
	"threat": 0.6, "insult": 0.4, "svc_heal": 0.2, "svc_bless": 0.2, "svc_craft": 0.2,
	"haggle": 0.3, "buy": 0.15, "sell": 0.15, "ask_price": 0.1, "ask_quest": 0.1,
}

static var _ready_flag: bool = false
static var _word_intent: Dictionary = {}
static var _phrases: Array = []
static var _sets: Dictionary = {}
static var _items: Dictionary = {}
static var _places: Dictionary = {}
static var _fuzzy_cache: Dictionary = {}
static var _elong_re: RegEx = null


# ───────── تطبيع النص: تشكيل/همزات/تاء مربوطة/ألف مقصورة/تكرار حروف/أرقام هندية ─────────
static func normalize(s: String) -> String:
	var low := s.to_lower()
	var out := ""
	var prev: int = -1
	var run: int = 0
	for i in low.length():
		var c: int = low.unicode_at(i)
		if (c >= 0x064B and c <= 0x065F) or c == 0x0640 or c == 0x0670:
			continue
		match c:
			0x0623, 0x0625, 0x0622, 0x0671:
				c = 0x0627
			0x0649:
				c = 0x064A
			0x0629:
				c = 0x0647
			0x0624:
				c = 0x0648
			0x0626:
				c = 0x064A
		if c >= 0x0660 and c <= 0x0669:
			c = c - 0x0660 + 48
		elif c >= 0x06F0 and c <= 0x06F9:
			c = c - 0x06F0 + 48
		var is_letter: bool = (c >= 0x0621 and c <= 0x064A) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57)
		if not is_letter:
			c = 32
		if c == 32:
			if out != "" and not out.ends_with(" "):
				out += " "
			prev = 32
			run = 0
			continue
		if c == prev:
			run += 1
			if run >= 3:
				if run == 3:
					out = out.substr(0, out.length() - 1)
				continue
		else:
			run = 1
		out += String.chr(c)
		prev = c
	return out.strip_edges()


static func strip_prefix(t: String) -> String:
	for p in ["بال", "وال", "فال", "كال", "لل", "ال"]:
		if t.begins_with(p) and t.length() > p.length() + 1:
			return t.substr(p.length())
	return t


# ───────── تهيئة القواميس (مرة واحدة) ─────────
static func _ensure() -> void:
	if _ready_flag:
		return
	_ready_flag = true
	for intent in NPCLexicon.INTENT_WORDS:
		for w in NPCLexicon.INTENT_WORDS[intent]:
			_add_word(normalize(w), intent, WORD_WEIGHT)
	for intent in NPCLexicon.INTENT_PHRASES:
		for p in NPCLexicon.INTENT_PHRASES[intent]:
			_phrases.append([normalize(p), intent, PHRASE_WEIGHT])
	for set_name in NPCLexicon.WORD_SETS:
		_sets[set_name] = {}
		for w in NPCLexicon.WORD_SETS[set_name]:
			_sets[set_name][normalize(w)] = true
	for w in NPCLexicon.ITEM_WORDS:
		_items[normalize(w)] = NPCLexicon.ITEM_WORDS[w]
	for w in NPCLexicon.PLACE_WORDS:
		_places[normalize(w)] = NPCLexicon.PLACE_WORDS[w]
	_load_extra()


# ملف JSON اختياري لزيادة كلمات بدون تعديل كود. الشكل:
# {"intent_words": {"greet": ["يا باشا"]}, "intent_phrases": {...}, "sets": {"rude": [...]}, "items": {"كلمة": "item_id"}}
static func _load_extra() -> void:
	if not FileAccess.file_exists(EXTRA_PATH):
		return
	var f := FileAccess.open(EXTRA_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	var iw: Dictionary = data.get("intent_words", {})
	for intent in iw:
		for w in iw[intent]:
			_add_word(normalize(str(w)), str(intent), WORD_WEIGHT)
	var ip: Dictionary = data.get("intent_phrases", {})
	for intent in ip:
		for p in ip[intent]:
			_phrases.append([normalize(str(p)), str(intent), PHRASE_WEIGHT])
	var st: Dictionary = data.get("sets", {})
	for set_name in st:
		if not _sets.has(set_name):
			_sets[set_name] = {}
		for w in st[set_name]:
			_sets[set_name][normalize(str(w))] = true
	var it: Dictionary = data.get("items", {})
	for w in it:
		_items[normalize(str(w))] = str(it[w])


static func _add_word(w: String, intent: String, weight: float) -> void:
	if w == "":
		return
	if not _word_intent.has(w):
		_word_intent[w] = []
	_word_intent[w].append([intent, weight])


static func _in_set(set_name: String, t: String) -> bool:
	var st: Dictionary = _sets.get(set_name, {})
	return st.has(t) or st.has(strip_prefix(t))


# ───────── مطابقة تقريبية (تتحمل غلطة/غلطتين إملائية) ─────────
static func _lookup(t: String) -> Array:
	if _word_intent.has(t):
		return _word_intent[t]
	var s := strip_prefix(t)
	if s != t and _word_intent.has(s):
		return _word_intent[s]
	if t.length() >= 5 and t.ends_with("لي"):
		var base := t.substr(0, t.length() - 2)
		if _word_intent.has(base):
			return _word_intent[base]
	if t.length() < 5:
		return []        # الكلمات القصيرة ماتتصححش (عشان "عندي" ماتبقاش "عندك")
	if _fuzzy_cache.has(t):
		return _fuzzy_cache[t]
	var maxd: int = 1 if t.length() < 8 else 2
	var best: Array = []
	var best_d: int = 99
	for w in _word_intent.keys():
		var wl: int = w.length()
		if wl < 4 or absi(wl - t.length()) > maxd:
			continue
		if t.length() < 8 and w[0] != t[0]:
			continue
		var d: int = _lev(t, w, maxd)
		if d <= maxd and d < best_d:
			best_d = d
			best = []
			for pair in _word_intent[w]:
				best.append([pair[0], float(pair[1]) * FUZZY_WEIGHT])
	if _fuzzy_cache.size() > FUZZY_CACHE_MAX:
		_fuzzy_cache.clear()
	_fuzzy_cache[t] = best
	return best


static func _lev(a: String, b: String, maxd: int) -> int:
	var la: int = a.length()
	var lb: int = b.length()
	if absi(la - lb) > maxd:
		return maxd + 1
	var prev: Array = []
	for j in lb + 1:
		prev.append(j)
	for i in range(1, la + 1):
		var cur: Array = [i]
		var row_min: int = i
		for j in range(1, lb + 1):
			var cost: int = 0 if a[i - 1] == b[j - 1] else 1
			var v: int = mini(mini(int(prev[j]) + 1, int(cur[j - 1]) + 1), int(prev[j - 1]) + cost)
			cur.append(v)
			if v < row_min:
				row_min = v
		if row_min > maxd:
			return maxd + 1
		prev = cur
	return int(prev[lb])


# هل في كلمة نفي (مش/لا/ما...) قبل العبارة بكلمتين على الأكتر؟
static func _negated_before(norm: String, at: int) -> bool:
	var before: PackedStringArray = norm.substr(0, at).strip_edges().split(" ", false)
	var n: int = before.size()
	for i in range(maxi(0, n - 2), n):
		if _in_set("negation", before[i]):
			return true
	return false


static func _empty_tone() -> Dictionary:
	return {"politeness": 0.0, "rudeness": 0.0, "aggression": 0.0, "warmth": 0.0,
		"fear": 0.0, "urgency": 0.0, "formality": 0.0, "humor": 0.0}


static func _squash(v: float) -> float:
	return 1.0 - exp(-v * 0.7)


# ───────── التحليل الرئيسي ─────────
static func analyze(text: String, known_names: Array = []) -> Dictionary:
	_ensure()
	var raw := text.strip_edges()
	var norm := normalize(raw)
	var tokens: Array = []
	for t in norm.split(" ", false):
		tokens.append(t)

	var res := {
		"raw": raw, "norm": norm, "tokens": tokens, "length": tokens.size(),
		"primary": "none", "primary_score": 0.0, "secondary": "none", "secondary_score": 0.0,
		"scores": {}, "tone": _empty_tone(), "valence": 0.0, "is_question": false,
		"shout": false, "elongated": false, "humor": false,
		"items": [], "places": [], "numbers": [], "yes": false, "no": false, "mentions_name": false,
	}
	if tokens.is_empty():
		return res

	# علامات سطحية
	var low_raw := raw.to_lower()
	if _elong_re == null:
		_elong_re = RegEx.new()
		_elong_re.compile("(.)\\1{2,}")
	res["elongated"] = _elong_re.search(low_raw) != null
	res["shout"] = raw.count("!") >= 2 or raw.count("؟!") > 0
	res["humor"] = low_raw.contains("هههه") or low_raw.contains("haha") or low_raw.contains("lol") or low_raw.contains("😂") or low_raw.contains("🤣")
	var q_mark: bool = raw.contains("؟") or raw.contains("?")
	var q_word: bool = false
	for i in mini(3, tokens.size()):
		if _in_set("question", tokens[i]):
			q_word = true
	res["is_question"] = q_mark or q_word

	# النوايا + النبرة في مرور واحد
	var scores: Dictionary = {}
	var raw_tone := _empty_tone()
	var pos_n: float = 0.0
	var neg_n: float = 0.0
	for i in tokens.size():
		var t: String = tokens[i]
		var boost: float = 1.0
		if i > 0 and _in_set("intensifier", tokens[i - 1]):
			boost = 1.5
		var negated: bool = (i > 0 and _in_set("negation", tokens[i - 1])) or (i > 1 and _in_set("negation", tokens[i - 2]))

		for pair in _lookup(t):
			var w: float = float(pair[1])
			if negated and pair[0] != "greet" and pair[0] != "thanks":
				w *= 0.2
			scores[pair[0]] = float(scores.get(pair[0], 0.0)) + w

		if _in_set("polite", t):
			if negated:
				raw_tone["rudeness"] += 0.8 * boost
			else:
				raw_tone["politeness"] += boost
		if _in_set("rude", t):
			raw_tone["rudeness"] += 1.2 * boost
		if _in_set("aggressive", t):
			raw_tone["aggression"] += 1.5 * boost
		if _in_set("warm", t):
			if negated:
				raw_tone["rudeness"] += 0.5
			else:
				raw_tone["warmth"] += boost
		if _in_set("fear", t):
			raw_tone["fear"] += boost
		if _in_set("urgent", t):
			raw_tone["urgency"] += boost
		if _in_set("formal", t):
			raw_tone["formality"] += 1.0
		if _in_set("slang", t):
			raw_tone["formality"] -= 0.5
		if _in_set("positive", t):
			if negated:
				neg_n += boost
			else:
				pos_n += boost
		if _in_set("negative", t):
			if negated:
				pos_n += 0.5
			else:
				neg_n += boost

	for ph in _phrases:
		var at: int = norm.find(ph[0])
		if at != -1:
			var w2: float = float(ph[2])
			if ph[1] != "greet" and ph[1] != "thanks" and _negated_before(norm, at):
				w2 *= 0.2
			scores[ph[1]] = float(scores.get(ph[1], 0.0)) + w2

	# صراخ/تكرار: يزود العدوانية لو في إهانة، أو الاستعجال لو مفيش
	var excl: int = mini(raw.count("!"), 3)
	if raw_tone["rudeness"] > 0.0 or raw_tone["aggression"] > 0.0:
		raw_tone["aggression"] += excl * 0.25
	else:
		raw_tone["urgency"] += excl * 0.15
	if res["humor"]:
		raw_tone["humor"] += 1.0
		raw_tone["warmth"] += 0.4
	if res["elongated"] and raw_tone["rudeness"] <= 0.0:
		raw_tone["warmth"] += 0.2

	# تحويل لـ 0..1
	var tone := _empty_tone()
	for k in raw_tone:
		if k == "formality":
			tone[k] = clampf(float(raw_tone[k]) * 0.25, -1.0, 1.0)
		else:
			tone[k] = _squash(maxf(0.0, float(raw_tone[k])))
	res["tone"] = tone
	res["valence"] = clampf(
		float(tone["warmth"]) + 0.7 * float(tone["politeness"]) + 0.4 * _squash(pos_n)
		- float(tone["rudeness"]) - 1.2 * float(tone["aggression"]) - 0.4 * _squash(neg_n), -1.0, 1.0)

	# ترتيب النوايا
	var arr: Array = []
	for k in scores:
		var sc: float = float(scores[k])
		if sc > 0.0:
			sc += float(PRIORITY.get(k, 0.0))
		arr.append({"intent": k, "score": sc})
	arr.sort_custom(func(x, y): return x["score"] > y["score"])
	res["scores"] = scores
	if arr.size() > 0 and float(arr[0]["score"]) >= 0.8:
		res["primary"] = arr[0]["intent"]
		res["primary_score"] = arr[0]["score"]
	if arr.size() > 1 and float(arr[1]["score"]) >= 0.8:
		res["secondary"] = arr[1]["intent"]
		res["secondary_score"] = arr[1]["score"]

	# أصناف/أماكن/أرقام
	var items: Array = []
	var places: Array = []
	var numbers: Array = []
	for t in tokens:
		var key: String = strip_prefix(t)
		if _items.has(key) and not items.has(_items[key]):
			items.append(_items[key])
		elif _items.has(t) and not items.has(_items[t]):
			items.append(_items[t])
		if _places.has(key) and not places.has(_places[key]):
			places.append(_places[key])
		elif _places.has(t) and not places.has(_places[t]):
			places.append(_places[t])
		if t.is_valid_int():
			numbers.append(int(t))
	res["items"] = items
	res["places"] = places
	res["numbers"] = numbers

	# نعم/لا (بس لو الرسالة قصيرة، عشان "لا" و"تمام" جوه جمل طويلة مش ردود)
	if tokens.size() <= 4:
		for t in tokens:
			if _in_set("yes", t):
				res["yes"] = true
			if _in_set("no", t):
				res["no"] = true

	for n in known_names:
		var nn := normalize(str(n))
		if nn != "" and norm.contains(nn):
			res["mentions_name"] = true
	return res
