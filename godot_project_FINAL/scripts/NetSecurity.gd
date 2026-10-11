class_name NetSecurity
extends RefCounted
# NetSecurity.gd — دوال أمان الشبكة (static، بدون أي اعتماد على autoloads عشان تتختبر بسهولة).
# المبدأ: ما نثقش في أي بيانات جاية من لاعب تاني. الهوية بتتحدد من رقم المُرسِل في ENet،
# والأرقام بتتقيّد، والنصوص بتتنضّف قبل ما تتعرض.

const MAX_COORD := 100000.0
const MAX_HP := 100000
const MAX_LEVEL := 999
const MAX_NAME := 24
const MAX_CHAT := 200


# معرّف جهاز عشوائي (192 bit) — مش قابل للتخمين، عكس القديم اللي كان مبني على الوقت
static func make_device_id() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()


# هل المعرّف شكله سليم (hex طويل)؟ المعرّفات القديمة المبنية على الوقت بترجع false وبتتجدّد
static func is_strong_device_id(id: String) -> bool:
	return id.length() >= 32 and id.is_valid_hex_number(false)


# هوية لاعب LAN من رقم الـ peer اللي أرسل فعلاً (مش من اللي بيدّعيه)
static func lan_uid(sender_id: int) -> String:
	if sender_id <= 0:
		return ""
	return "lan_%d" % sender_id


static func _num(v: Variant, default_value: float) -> float:
	var t := typeof(v)
	if t != TYPE_FLOAT and t != TYPE_INT:
		return default_value
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return default_value
	return f


static func _clamped(v: Variant, lo: float, hi: float, default_value: float) -> float:
	return clampf(_num(v, default_value), lo, hi)


# بيرجّع نسخة نظيفة من حالة لاعب جاية من الشبكة: مفاتيح معروفة بس، وأرقام مقيّدة
static func sanitize_lan_state(raw: Dictionary) -> Dictionary:
	var out := {}
	for k in ["x", "y", "z"]:
		if raw.has(k):
			out[k] = _clamped(raw[k], -MAX_COORD, MAX_COORD, 0.0)
	if raw.has("rotY"):
		out["rotY"] = _clamped(raw["rotY"], -1000.0, 1000.0, 0.0)
	var max_hp := MAX_HP
	if raw.has("maxHp"):
		max_hp = int(_clamped(raw["maxHp"], 0.0, float(MAX_HP), 0.0))
		out["maxHp"] = max_hp
	if raw.has("hp"):
		out["hp"] = int(_clamped(raw["hp"], 0.0, float(max_hp), 0.0))
	if raw.has("level"):
		out["level"] = int(_clamped(raw["level"], 1.0, float(MAX_LEVEL), 1.0))
	return out


# بيهرّب أقواس BBCode عشان النص يتعرض زي ما هو من غير ما ينفّذ وسوم
static func escape_bbcode(s: String) -> String:
	var out := ""
	for ch in s:
		if ch == "[":
			out += "[lb]"
		elif ch == "]":
			out += "[rb]"
		else:
			out += ch
	return out


static func _strip_controls(s: String) -> String:
	var out := ""
	for ch in s:
		var code := ch.unicode_at(0)
		if code < 32 or code == 127:
			out += " "
		else:
			out += ch
	return out


static func sanitize_username(s: String) -> String:
	var t := _strip_controls(s).replace("[", "").replace("]", "").strip_edges()
	if t.length() > MAX_NAME:
		t = t.substr(0, MAX_NAME).strip_edges()
	return t if t != "" else "Player"


static func sanitize_chat(s: String) -> String:
	var t := _strip_controls(s).strip_edges()
	if t.length() > MAX_CHAT:
		t = t.substr(0, MAX_CHAT)
	return t
