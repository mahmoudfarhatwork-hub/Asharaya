extends Node
class_name QuestSystem
# QuestSystem.gd — يُضاف كـ child node تحت اللاعب اسمه "QuestSystem"
# كل المهام اختيارية 100% حسب الوثيقة (قسم 6.2) — مفيش أي مهمة إجبارية

signal quest_completed(quest_id: String)
signal quest_progress(quest_id: String, current: int, target: int)

var quests := {
	"welcome": {
		"name": "ترحيب المبتدئ", "type": "talk_npc", "target_id": "elara",
		"progress": 0, "target": 1, "xp": 5, "coins_iron": 0, "completed": false, "item": "",
	},
	"supplies": {
		"name": "الإمدادات", "type": "buy_item", "target_id": "bread",
		"progress": 0, "target": 1, "xp": 10, "coins_iron": 1, "completed": false, "item": "",
	},
	"first_extermination": {
		"name": "الإبادة الأولى", "type": "kill", "target_id": "slime",
		"progress": 0, "target": 3, "xp": 50, "coins_iron": 5, "completed": false, "item": "",
	},
	"wolf_hunter": {
		"name": "صياد الذئاب", "type": "kill", "target_id": "gray_wolf",
		"progress": 0, "target": 5, "xp": 100, "coins_iron": 0, "coins_bronze": 1, "completed": false, "item": "",
	},
	"boss_challenge": {
		"name": "تحدي البوس", "type": "kill", "target_id": "goblin_boss",
		"progress": 0, "target": 1, "xp": 300, "coins_bronze": 3, "completed": false, "item": "boss_sword",
	},
}

@onready var owner_player: Node = get_parent()


func _ready() -> void:
	_load_saved_quests()


# ينادى عليه من أي مكان في اللعبة لما حدث يحصل (قتل وحش، شراء، كلام مع NPC)
func report_event(event_type: String, target_id: String) -> void:
	for quest_id in quests.keys():
		var q = quests[quest_id]
		if q["completed"]:
			continue
		if q["type"] == event_type and q["target_id"] == target_id:
			q["progress"] += 1
			quest_progress.emit(quest_id, q["progress"], q["target"])
			if q["progress"] >= q["target"]:
				_complete_quest(quest_id)


func _complete_quest(quest_id: String) -> void:
	var q = quests[quest_id]
	q["completed"] = true

	var stats: PlayerStats = owner_player.get_node_or_null("PlayerStats")
	var inv: Inventory = owner_player.get_node_or_null("Inventory")

	if stats:
		stats.gain_xp(q.get("xp", 0))
		stats.add_coins(q.get("coins_iron", 0), q.get("coins_bronze", 0))
		stats.save_data()

	if q.get("item", "") != "" and inv:
		match q["item"]:
			"boss_sword":
				inv.add_item("boss_sword", "سيف الزعيم", "weapon", 1)
		inv.save_inventory()

	quest_completed.emit(quest_id)
	save_quests()


func is_completed(quest_id: String) -> bool:
	return quests.has(quest_id) and quests[quest_id]["completed"]


# ── حفظ/تحميل ──
func save_quests() -> void:
	var progress_only := {}
	for quest_id in quests.keys():
		progress_only[quest_id] = {"progress": quests[quest_id]["progress"], "completed": quests[quest_id]["completed"]}
	NetworkManager.save_player_data("player_progress", "quests", progress_only)


func _load_saved_quests() -> void:
	var data: Dictionary = await NetworkManager.load_player_data("player_progress", "quests", {})
	for quest_id in data.keys():
		if quests.has(quest_id):
			quests[quest_id]["progress"] = data[quest_id].get("progress", 0)
			quests[quest_id]["completed"] = data[quest_id].get("completed", false)
