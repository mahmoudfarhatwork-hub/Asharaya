extends Node
# =====================================================================
# Asharaya — NPCDialogueBridge (Autoload Singleton, اسمه المقترح: Dialogue)
# =====================================================================
# الهدف: ردود الـ 500 NPC الـ"Advanced AI" (تجار/قادة/ملوك حسب الـ GDD)
# تبقى متغيّرة حسب السياق، مش جمل ثابتة مكتوبة مسبقًا.
#
# ازاي؟ السكريبت ده بيبعت طلب HTTP لسيرفر LLM محلي شغال جنب اللعبة
# (llama.cpp server أو text-generation-inference من Hugging Face)،
# وبيدي له سياق حقيقي: مين الـ NPC، مزاجه، مين قدامه، وايه اللي حصل.
#
# ⚠️ نقطة مهمة وصريحة: طلب HTTP لكل رد فيه تأخير (100-800ms حسب
# الموديل والجهاز اللي شغال عليه السيرفر)، فمينفعش يتستخدم في كل
# حركة أو كل فريم — يتستخدم بس وقت فتح حوار فعلي مع NPC. ده سبب
# تاني إن الـ 3500 NPC الـ Ambient (Zombie/Mass Entity) متربطوش
# بالنظام ده خالص — بس الـ 500 Advanced AI.
#
# الخادم مش لازم يكون على نفس الجهاز — ممكن يكون سيرفر مركزي واحد
# كل اللاعبين (PC + Android) بيكلموه، وده الأنسب فعلياً لأن موبايل
# ضعيف مش هيقدر يشغل LLM محلي أصلاً.
#
# التثبيت: Project Settings > Autoload > اسم "Dialogue"
# =====================================================================

signal response_ready(npc_id: String, text: String)
signal response_failed(npc_id: String, error: String)

# طلبات "تصرف" (Action) — منفصلة عن الحوار: بترجع JSON قصير بدل جملة
# طبيعية، وبتستخدم من NPCBehaviorController لكل الـ NPCs (مش الحوار
# المباشر بس)، عشان النموذج يتحكم في نشاطهم مش بس كلامهم
signal action_ready(npc_id: String, action: Dictionary)
signal action_failed(npc_id: String, error: String)

@export var llm_server_url: String = "http://127.0.0.1:8080/v1/chat/completions"
# ★ لو هتستخدم Cloudflare Workers AI بدل سيرفر محلي، حط رابطه هنا مثلاً:
# "https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/ai/run/@cf/meta/llama-3.1-8b-instruct"
# (أو رابط AI Gateway بتاعك لو فعّلته قدامه للـ Caching)
@export var llm_auth_token: String = ""  # توكن Cloudflare API — سيبه فاضي لو سيرفر محلي مفيهوش auth
@export var request_timeout_sec: float = 8.0
@export var max_concurrent_requests: int = 3
@export var fallback_lines_path: String = "res://data/npc_fallback_lines.json"

var _active_requests: int = 0
var _fallback_lines: Dictionary = {}
var _http_pool: Array = []   # نعيد استخدام أوبجكتات HTTPRequest بدل ما ننشئ واحد لكل طلب

func _ready():
	_load_fallback_lines()

func _build_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if llm_auth_token != "":
		headers.append("Authorization: Bearer %s" % llm_auth_token)
	return headers

func _load_fallback_lines():
	# لو الشبكة وقعت أو السيرفر بعيد، النظام لازم يرجع لجمل احتياطية
	# جاهزة بدل ما الـ NPC يفضل صامت أو تطلع رسالة خطأ للاعب
	if FileAccess.file_exists(fallback_lines_path):
		var f = FileAccess.open(fallback_lines_path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_fallback_lines = parsed
	if _fallback_lines.is_empty():
		_fallback_lines = {
			"default": ["أهلاً بيك أيها المسافر.", "الطريق خطير هنا، خد بالك."]
		}

# =====================================================================
# الدالة الرئيسية اللي بتتنادى من كود الحوار في اللعبة
# npc_profile مثال:
# {
#   "npc_id": "merchant_haddad_01",
#   "role": "تاجر", "name": "حداد", "faction": "البشر",
#   "mood": "ودود",           # يتغير حسب أحداث اللعبة (سمعة اللاعب، إلخ)
#   "location": "قرية البداية",
#   "memory_summary": "باع للاعب سيف بالأمس"   # اختياري، سياق مستمر
# }
# =====================================================================
func request_npc_response(npc_profile: Dictionary, player_message: String, speaker_name: String = "اللاعب"):
	if _active_requests >= max_concurrent_requests:
		# حماية من إغراق السيرفر لو فتحوا حوارات كتير بسرعة
		_use_fallback(npc_profile.get("npc_id", "unknown"), npc_profile.get("role", "default"))
		return

	var system_prompt = _build_system_prompt(npc_profile)
	var body = {
		"model": "asharaya-npc",   # اسم الموديل زي ما هيكون معرّف في سيرفر llama.cpp
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": "%s قال: %s" % [speaker_name, player_message]}
		],
		"max_tokens": 120,
		"temperature": 0.8,
	}

	var http = _get_pooled_http_request()
	_active_requests += 1

	var err = http.request(
		llm_server_url,
		_build_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if err != OK:
		_active_requests -= 1
		_use_fallback(npc_profile.get("npc_id", "unknown"), npc_profile.get("role", "default"))
		return

	# نربط الاستجابة مرة واحدة بس (one-shot) عشان منكررش نفس الرد لطلبات سابقة
	var npc_id = npc_profile.get("npc_id", "unknown")
	var role = npc_profile.get("role", "default")
	http.request_completed.connect(
		func(result, code, _headers, body_bytes):
			_on_response(http, result, code, body_bytes, npc_id, role),
		CONNECT_ONE_SHOT
	)

func _build_system_prompt(p: Dictionary) -> String:
	# السياق هنا هو "الذكاء" الحقيقي — نفس الموديل الصغير بيدي ردود
	# مختلفة تمامًا حسب الدور والمزاج والمكان، من غير ما نكتب سكريبت
	# منفصل لكل شخصية
	var parts = []
	parts.append("انت شخصية NPC في لعبة MMORPG اسمها Asharaya.")
	parts.append("اسمك: %s. دورك: %s. عرقك/فصيلك: %s." % [
		p.get("name", "مجهول"), p.get("role", "شخصية عادية"), p.get("faction", "بلا انتماء")
	])
	parts.append("مزاجك الحالي: %s. مكانك: %s." % [
		p.get("mood", "عادي"), p.get("location", "غير محدد")
	])
	if p.has("memory_summary") and p["memory_summary"] != "":
		parts.append("تتذكر: %s" % p["memory_summary"])
	parts.append("رد بجملة أو جملتين بالعامية المصرية فقط، بدون أوصاف أفعال، وبما يتماشى مع دورك ومزاجك. متخرجش عن شخصيتك أبدًا.")
	return " ".join(parts)

func _on_response(http: HTTPRequest, result: int, response_code: int, body_bytes: PackedByteArray, npc_id: String, role: String):
	_active_requests -= 1
	_release_pooled_http_request(http)

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		response_failed.emit(npc_id, "http_error_%d" % response_code)
		_use_fallback(npc_id, role)
		return

	var text = body_bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed.has("choices") or parsed["choices"].is_empty():
		response_failed.emit(npc_id, "bad_json")
		_use_fallback(npc_id, role)
		return

	var reply: String = parsed["choices"][0]["message"]["content"]
	response_ready.emit(npc_id, reply.strip_edges())

func _use_fallback(npc_id: String, role: String):
	var pool: Array = _fallback_lines.get(role, _fallback_lines.get("default", ["..."]))
	var line = pool[randi() % pool.size()]
	response_ready.emit(npc_id, line)

# =====================================================================
# تجميع HTTPRequest — بنعيد استخدام العقد بدل ما ننشئ/نهدم كل مرة،
# ده بيوفر تجزئة ذاكرة (memory fragmentation) على المدى الطويل
# =====================================================================
func _get_pooled_http_request() -> HTTPRequest:
	for h in _http_pool:
		if not h.get_meta("in_use", false):
			h.set_meta("in_use", true)
			h.timeout = request_timeout_sec
			return h
	var new_http = HTTPRequest.new()
	new_http.timeout = request_timeout_sec
	new_http.set_meta("in_use", true)
	add_child(new_http)
	_http_pool.append(new_http)
	return new_http

func _release_pooled_http_request(h: HTTPRequest):
	h.set_meta("in_use", false)

# =====================================================================
# طلب "تصرف" — نفس السيرفر ونفس الموديل، لكن الرد هنا مش جملة حرة،
# ده JSON قصير بيحدد نشاط الـ NPC (يمشي / يشتغل / يهرب / يسلّم...).
# max_tokens صغير عمدًا (النشاط قرار بسيط، مش حوار) عشان الرد يرجع
# أسرع، وده مهم أكتر هنا لأن الطلبات دي بتتكرر لكل الـ NPCs بمرور الوقت
# مش بس وقت فتح حوار فعلي زي request_npc_response.
#
# npc_profile نفس شكل request_npc_response، بالإضافة (اختياري):
#   "available_actions": Array مخصصة لو الـ NPC ده عنده نشاطات مختلفة
#   عن الافتراضي (تاجر مثلاً عنده "sell"، حداد عنده "forge"...)
# =====================================================================
const DEFAULT_ACTIONS = ["idle", "wander", "work", "greet_nearby", "flee"]

func request_npc_action(npc_profile: Dictionary, world_context: String = "") -> void:
	if _active_requests >= max_concurrent_requests:
		# السيرفر مشغول — مفيش داعي نكسر تصرف الـ NPC، سيبه على قراره
		# المحلي الحالي لحد الفرصة الجاية (كل NPC بييجي دوره تاني بعد شوية)
		action_failed.emit(npc_profile.get("npc_id", "unknown"), "queue_full")
		return

	var system_prompt = _build_action_system_prompt(npc_profile)
	var body = {
		"model": "asharaya-npc",
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": world_context if world_context != "" else "قرر تصرفك دلوقتي."}
		],
		"max_tokens": 50,
		"temperature": 0.9,
	}

	var http = _get_pooled_http_request()
	_active_requests += 1

	var err = http.request(
		llm_server_url,
		_build_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if err != OK:
		_active_requests -= 1
		action_failed.emit(npc_profile.get("npc_id", "unknown"), "request_failed")
		return

	var npc_id = npc_profile.get("npc_id", "unknown")
	http.request_completed.connect(
		func(result, code, _headers, body_bytes):
			_on_action_response(http, result, code, body_bytes, npc_id),
		CONNECT_ONE_SHOT
	)

func _build_action_system_prompt(p: Dictionary) -> String:
	var allowed: Array = p.get("available_actions", DEFAULT_ACTIONS)
	var parts = []
	parts.append("انت تتحكم في تصرف NPC اسمه %s، دوره: %s، مكانه: %s، مزاجه: %s." % [
		p.get("name", "NPC"), p.get("role", "عادي"), p.get("location", "غير محدد"), p.get("mood", "عادي")
	])
	parts.append("رد بصيغة JSON فقط بدون أي نص خارجها: {\"action\": \"اختار واحدة بالظبط من [%s]\", \"line\": \"جملة قصيرة جدًا اختيارية بالعامية المصرية أو نص فاضي\"}" % ", ".join(allowed))
	return " ".join(parts)

func _on_action_response(http: HTTPRequest, result: int, response_code: int, body_bytes: PackedByteArray, npc_id: String):
	_active_requests -= 1
	_release_pooled_http_request(http)

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		action_failed.emit(npc_id, "http_error_%d" % response_code)
		return

	var text = body_bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed.has("choices") or parsed["choices"].is_empty():
		action_failed.emit(npc_id, "bad_json")
		return

	var content: String = parsed["choices"][0]["message"]["content"]
	var action_dict = JSON.parse_string(content.strip_edges())
	if action_dict == null or not (action_dict is Dictionary) or not action_dict.has("action"):
		# موديلات صغيرة/ضعيفة أحيانًا بترجع نص عادي مش JSON نضيف —
		# منسيبش الـ NPC من غير قرار، نديله "idle" بدل ما نكسر النظام
		action_dict = {"action": "idle", "line": ""}
	action_ready.emit(npc_id, action_dict)
