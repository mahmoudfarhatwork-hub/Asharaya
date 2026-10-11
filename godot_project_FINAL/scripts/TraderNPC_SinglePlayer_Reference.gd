extends CharacterBody3D
# =====================================================================
# Asharaya — TraderNPC (مثال جاهز: تاجر بيستخدم النموذج للنشاط + المفاصلة)
# =====================================================================
# ده مثال كامل تقدر تنسخه/تعدّله لأي NPC. فيه استخدامين مختلفين للنموذج:
#
# 1) apply_ai_action(action) — بتتنادى تلقائيًا من NPCBehaviorController
#    كل ما يجيله دوره (كل 15 ثانية لحد كذا دقيقة حسب قربه من اللاعب).
#    دي بتحدد هو بيعمل إيه دلوقتي: واقف يبيع، بيسلم على حد قريب، ماشي.
#
# 2) negotiate_price() — بتتنادى بس وقت ما اللاعب فعليًا يفتح واجهة
#    البيع/الشراء ويعرض سعر. دي حوار مباشر (زي request_npc_response
#    العادي)، مش جزء من الدورة التلقائية، عشان منستهلكش السيرفر على
#    مفاصلة محدش بيلعبها دلوقتي.
# =====================================================================

@export var npc_id: String = "merchant_01"
@export var npc_name: String = "تاجر"
@export var base_price: int = 100

var _mood: String = "ودود"

func _ready() -> void:
	var profile = _build_profile()
	# Behavior و Ambient اتنين Autoload (متسجلين في project.godot)، مش
	# نودز جوه المشهد — بيتوصلولهم مباشرة بالاسم من أي سكريبت في اللعبة
	Behavior.register_npc(self, profile)
	Ambient.register_npc(self)

func _build_profile() -> Dictionary:
	return {
		"npc_id": npc_id,
		"name": npc_name,
		"role": "تاجر",
		"faction": "البشر",
		"mood": _mood,
		"location": "السوق",
		# نشاطات مخصصة للتاجر بدل القائمة الافتراضية — النموذج بيختار
		# من بينها بس، مش بيخترع نشاط عشوائي
		"available_actions": ["idle", "work", "greet_nearby", "wander"],
	}

# =====================================================================
# 1) النشاط الدوري — بتتنادى من NPCBehaviorController تلقائيًا
# =====================================================================
func apply_ai_action(action: Dictionary) -> void:
	var chosen: String = action.get("action", "idle")
	var line: String = action.get("line", "")

	match chosen:
		"work":
			_play_animation("selling_gesture")
		"greet_nearby":
			_play_animation("wave")
		"wander":
			_wander_step()
		_:
			_play_animation("idle")

	if line != "":
		_show_speech_bubble(line)

func _play_animation(anim_name: String) -> void:
	var anim_player = get_node_or_null("AnimationPlayer")
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)

func _wander_step() -> void:
	# النموذج بس بيحدد "النية" (يتمشى) — حساب المسار فريم بفريم بيفضل
	# كود محلي عادي زي أي لعبة، مش مربوط بطلب HTTP، لأن ده مستحيل
	# يحصل بمعدل 60 فريم/ثانية عبر الشبكة مهما كان السيرفر سريع.
	# اربط النقطة دي بـ NavigationAgent3D أو أي نظام حركة عندك:
	var _target = global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	pass

func _show_speech_bubble(text: String) -> void:
	var label = get_node_or_null("SpeechBubble") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "SpeechBubble"
		label.font_size = 28
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 2.2, 0)
		add_child(label)
	label.text = text
	var tw = create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		if is_instance_valid(label):
			label.text = ""
	)

# =====================================================================
# 2) المفاصلة على السعر — استدعيها من واجهة البيع/الشراء بتاعتك:
#    trader.negotiate_price(80, func(result): ... تعامل مع النتيجة)
# =====================================================================
func negotiate_price(player_offer: int, callback: Callable) -> void:
	var profile = _build_profile()
	profile["memory_summary"] = "السعر الأساسي للسلعة %d ذهب. اللاعب عرض %d." % [base_price, player_offer]

	var message = (
		"اللاعب بيعرض عليك %d ذهب في السلعة دي. رد بصيغة JSON فقط بدون أي نص خارجها: "
		+ "{\"accept\": true او false, \"counter_offer\": رقم صحيح, \"line\": \"جملة تفاوض قصيرة بالعامية المصرية\"}"
	) % player_offer

	Dialogue.response_ready.connect(
		func(responding_id: String, text: String):
			_on_negotiation_response(responding_id, text, callback),
		CONNECT_ONE_SHOT
	)
	Dialogue.request_npc_response(profile, message)

func _on_negotiation_response(responding_npc_id: String, text: String, callback: Callable) -> void:
	if responding_npc_id != npc_id:
		return
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary) or not parsed.has("accept"):
		# الموديل رجّع نص عادي مش JSON صافي (بيحصل مع الموديلات الصغيرة
		# أحيانًا) — نرجع لعرض متحفّظ افتراضي بدل ما نكسر واجهة البيع
		parsed = {"accept": false, "counter_offer": int(base_price * 0.9), "line": text}
	callback.call(parsed)
