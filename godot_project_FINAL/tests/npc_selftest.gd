extends SceneTree
# tests/npc_selftest.gd — اختبار عقل الـ NPCs بدون واجهة:
#   godot --headless --path godot_project_FINAL --script res://tests/npc_selftest.gd
# بيرجّع exit code = 1 لو أي اختبار فشل (بيتشغل تلقائي في GitHub Actions).

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	var brain := NPCBrain.new()
	brain.rng.seed = 20260101
	_test_language()
	_test_conversation_and_haggle(brain)
	_test_variation(brain)
	_test_hostility_and_apology(brain)
	_test_politeness_effect(brain)
	_test_intelligence_table(brain)
	_test_quest_odds(brain)
	_test_location_and_time(brain)
	_test_behavior(brain)
	_test_memory_roundtrip(brain)
	print("NPC SELFTEST: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _ctx(now: float, day: int = 1, hour: float = 10.0) -> Dictionary:
	return {"player_id": "tester", "player_name": "سالم", "player_gender": "male", "player_race": "human",
		"hour": hour, "day": day, "weather": "clear", "zone": {"type": "stall", "place": "blacksmith"},
		"level": 5, "hp_ratio": 1.0, "hp_missing": 0, "hunger": 100.0, "wealth_iron": 500, "now_sec": now,
		"player_pos": Vector3.ZERO, "player_basis": Basis.IDENTITY}


func _test_language() -> void:
	var cases := {
		"اهلا يا معلم": "greet", "بكام السيف ده؟": "ask_price", "عايز اشتري سيف": "buy",
		"السيف غالي قوي نزل شويه": "haggle", "فين الحداد؟": "ask_direction", "انت مين؟": "ask_identity",
		"محتاج علاج": "svc_heal", "انت غبي يا حمار": "insult", "هقتلك": "threat", "شكرا ليك": "thanks",
		"مع السلامة": "farewell", "اهلااااا": "greet", "بكااااام السيف": "ask_price", "عندك مهمة ليا؟": "ask_quest",
		"where is the blacksmith": "ask_direction", "احكيلي عن الملوك": "ask_lore", "المنطقة دي امنه؟": "ask_danger",
	}
	for text in cases:
		var a: Dictionary = SpeechAnalyzer.analyze(text)
		check(a["primary"] == cases[text], "intent '%s' expected %s got %s" % [text, cases[text], a["primary"]])
	check(SpeechAnalyzer.analyze("مش عايز اشتري حاجة")["primary"] != "buy", "negated buy not treated as buy")
	var rude: Dictionary = SpeechAnalyzer.analyze("انت غبي يا حمار!!")
	var polite: Dictionary = SpeechAnalyzer.analyze("لو سمحت ممكن تساعدني")
	check(float(rude["tone"]["rudeness"]) > 0.5, "rude tone detected")
	check(float(polite["tone"]["politeness"]) > 0.5, "polite tone detected")


func _test_conversation_and_haggle(brain: NPCBrain) -> void:
	var prof: Dictionary = brain.make_profile("blacksmith")
	var r: Dictionary = brain.respond(prof, "اهلا", _ctx(0.0))
	check(r["act"] == "greet" and str(r["text"]) != "", "blacksmith greets")
	r = brain.respond(prof, "عايز اشتري سيف", _ctx(5.0))
	check(r["act"] == "buy_talk" and (str(r["text"]).contains("حديدية") or str(r["text"]).contains("نحاسية")), "quote mentions price")
	var mem: Dictionary = brain.mind_for(prof).mem("tester")
	check(str(mem["pending"].get("type", "")) == "buy", "buy offer pending")
	var q1: int = int(mem["haggle"]["quote"])
	r = brain.respond(prof, "غالي قوي نزل شويه", _ctx(10.0))
	var q2: int = int(mem["haggle"]["quote"])
	check(q2 <= q1, "haggling does not raise price (%d -> %d)" % [q1, q2])
	r = brain.respond(prof, "تمام", _ctx(15.0))
	check(r["act"] == "pending_yes" and "purchase_done" in r["flags"], "yes completes purchase")
	var r2: Dictionary = brain.respond(prof, "عايز اشتري خبز", _ctx(20.0))
	check(str(r2["text"]) != "" and r2["act"] == "buy_talk", "item not sold by blacksmith redirected")


func _test_variation(brain: NPCBrain) -> void:
	var prof: Dictionary = {"npc_id": "var_test", "name": "ناصر", "job": "farmer", "race": "human"}
	var seen: Dictionary = {}
	for i in 20:
		var r: Dictionary = brain.respond(prof, "ازيك عامل ايه", _ctx(1000.0 + i * 200.0))
		seen[r["text"]] = true
	check(seen.size() >= 8, "replies vary (%d unique of 20)" % seen.size())


func _test_hostility_and_apology(brain: NPCBrain) -> void:
	var prof: Dictionary = {"npc_id": "hostile_test", "name": "جابر", "job": "trader", "race": "human"}
	var r: Dictionary = brain.respond(prof, "هقتلك", _ctx(0.0))
	check(r["act"] == "threat_react", "threat reaction")
	r = brain.respond(prof, "اهلا", _ctx(5.0))
	check(r["act"] == "refuse_hostile", "NPC refuses after threat")
	var m: NPCMind = brain.mind_for(prof)
	var got_forgiven: bool = false
	for i in 12:
		brain.respond(prof, "انا اسف معلش سامحني", _ctx(10.0 + i))
		if int(m.mem("tester")["banned_day"]) == -1:
			got_forgiven = true
			break
	check(got_forgiven, "apology can lift the ban")


func _test_politeness_effect(brain: NPCBrain) -> void:
	var a: Dictionary = {"npc_id": "pol_a", "name": "أ", "job": "farmer"}
	var b: Dictionary = {"npc_id": "pol_b", "name": "ب", "job": "farmer"}
	for i in 4:
		brain.respond(a, "لو سمحت ممكن تساعدني يا حضرتك شكرا", _ctx(i * 5.0))
		brain.respond(b, "يا ياض اخرس انت تافه", _ctx(i * 5.0))
	check(float(brain.mind_for(a).mem("tester")["affinity"]) > float(brain.mind_for(b).mem("tester")["affinity"]), "polite player gets better affinity")


func _test_intelligence_table(brain: NPCBrain) -> void:
	var king: NPCMind = brain.mind_for({"npc_id": "k1", "job": "king"})
	var crowd: NPCMind = brain.mind_for({"npc_id": "c1", "job": "crowd"})
	var smith: NPCMind = brain.mind_for({"npc_id": "s1", "job": "blacksmith"})
	check(king.intelligence >= 0.9, "king intelligence >= 0.9 (%f)" % king.intelligence)
	check(crowd.intelligence <= 0.45, "crowd intelligence <= 0.45 (%f)" % crowd.intelligence)
	check(smith.intelligence >= 0.62 and smith.intelligence <= 0.85, "blacksmith intelligence in band (%f)" % smith.intelligence)


func _test_quest_odds(brain: NPCBrain) -> void:
	var m: NPCMind = brain.mind_for({"npc_id": "odds_test", "job": "farmer"})
	var mem: Dictionary = m.mem("tester")
	var counts: Dictionary = {"": 0, "trivial": 0, "normal": 0, "rare": 0, "legendary": 0}
	var n: int = 4000
	for day in n:
		var tier: String = brain._quest_roll(m, mem, {"day": day + 1, "player_id": "tester"})
		counts[tier] += 1
	var none_p: float = float(counts[""]) / n
	var legend_p: float = float(counts["legendary"]) / n
	check(none_p > 0.35 and none_p < 0.45, "no-quest ~40%% (%f)" % none_p)
	check(legend_p < 0.03, "legendary ~1%% (%f)" % legend_p)


func _test_location_and_time(brain: NPCBrain) -> void:
	var prof: Dictionary = {"npc_id": "loc_test", "name": "رامي", "job": "trader", "race": "human"}
	var c1: Dictionary = _ctx(0.0)
	c1["zone"] = {"type": "square", "place": "square"}
	var r1: Dictionary = brain.respond(prof, "فين الحداد؟", c1)
	var c2: Dictionary = _ctx(0.0)
	c2["zone"] = {"type": "square", "place": "square"}
	c2["player_pos"] = Vector3(-30.0, 0.0, 0.0)
	var prof2: Dictionary = {"npc_id": "loc_test2", "name": "كمال", "job": "trader", "race": "human"}
	var r2: Dictionary = brain.respond(prof2, "فين الحداد؟", c2)
	check(r1["act"] == "direction_talk" and r2["act"] == "direction_talk", "direction act")
	check(str(r1["text"]).contains("شمال") and str(r2["text"]).contains("يمين"), "directions depend on player position: '%s' / '%s'" % [r1["text"], r2["text"]])
	var night: Dictionary = _ctx(0.0, 1, 23.0)
	night["zone"] = {"type": "square", "place": "square"}
	var prof3: Dictionary = {"npc_id": "loc_test3", "name": "هادي", "job": "farmer", "race": "human"}
	var rn: Dictionary = brain.respond(prof3, "المنطقة دي امنه؟", night)
	check(rn["act"] == "danger_talk" and str(rn["text"]).contains("بالليل"), "night-aware danger answer: " + str(rn["text"]))


func _test_behavior(brain: NPCBrain) -> void:
	var prof: Dictionary = {"npc_id": "beh_farmer", "name": "عم سيد", "job": "farmer", "race": "human"}
	var work: int = 0
	var idle_night: int = 0
	for i in 60:
		var day: Dictionary = brain.decide_action(prof, {"hour": 10.0, "player_dist": 999.0, "danger": 0.0})
		if day["action"] == "work":
			work += 1
		var night: Dictionary = brain.decide_action(prof, {"hour": 2.0, "player_dist": 999.0, "danger": 0.0})
		if night["action"] == "idle":
			idle_night += 1
	check(work >= 35, "farmer mostly works by day (%d/60)" % work)
	check(idle_night >= 35, "farmer rests at night (%d/60)" % idle_night)
	var flee: int = 0
	var timid: Dictionary = {"npc_id": "timid_one", "name": "خايف", "job": "villager", "race": "human"}
	for i in 30:
		if brain.decide_action(timid, {"hour": 10.0, "player_dist": 999.0, "danger": 1.0})["action"] == "flee":
			flee += 1
	check(flee >= 15, "villagers flee from danger (%d/30)" % flee)


func _test_memory_roundtrip(brain: NPCBrain) -> void:
	var prof: Dictionary = {"npc_id": "mem_test", "name": "حسام", "job": "healer", "race": "elf"}
	brain.respond(prof, "اهلا", _ctx(0.0))
	brain.respond(prof, "شكرا ليك يا حبيبي", _ctx(5.0))
	var m: NPCMind = brain.mind_for(prof)
	var txt: String = JSON.stringify(m.to_dict())
	var parsed = JSON.parse_string(txt)
	check(parsed is Dictionary, "memory serializes to JSON")
	var m2 := NPCMind.create(prof)
	m2.load_dict(parsed)
	check(int(m2.mem("tester")["met"]) == int(m.mem("tester")["met"]), "memory survives save/load")
