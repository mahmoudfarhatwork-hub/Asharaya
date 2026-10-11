extends Node
class_name Inventory
# Inventory.gd — يُضاف كـ child node تحت اللاعب اسمه "Inventory"
# شبكة 4×4 = 16 خانة بالظبط حسب قسم 7.1 في الوثيقة

const MAX_SLOTS := 16

# كل عنصر: {"id": "iron_sword", "name": "سيف حديدي", "quantity": 1, "type": "weapon", "data": {...}}
var slots: Array = []

signal inventory_changed

@onready var owner_player: Node = get_parent()


func _ready() -> void:
	slots.resize(MAX_SLOTS)
	_load_saved_inventory()


func add_item(item_id: String, item_name: String, item_type: String, quantity: int = 1, extra_data: Dictionary = {}) -> bool:
	# لو العنصر موجود بالفعل وقابل للتجميع (زي الخبز)، زوّد العدد
	for i in range(slots.size()):
		if slots[i] != null and slots[i]["id"] == item_id and item_type in ["consumable", "resource"]:
			slots[i]["quantity"] += quantity
			inventory_changed.emit()
			return true

	# لاقي أول خانة فاضية
	for i in range(slots.size()):
		if slots[i] == null:
			slots[i] = {"id": item_id, "name": item_name, "quantity": quantity, "type": item_type, "data": extra_data}
			inventory_changed.emit()
			return true

	return false  # المخزون فاضي مكان (16/16)


func remove_item(item_id: String, quantity: int = 1) -> bool:
	for i in range(slots.size()):
		if slots[i] != null and slots[i]["id"] == item_id:
			slots[i]["quantity"] -= quantity
			if slots[i]["quantity"] <= 0:
				slots[i] = null
			inventory_changed.emit()
			return true
	return false


func has_item(item_id: String, quantity: int = 1) -> bool:
	for slot in slots:
		if slot != null and slot["id"] == item_id and slot["quantity"] >= quantity:
			return true
	return false


func use_item(slot_index: int) -> void:
	var item = slots[slot_index]
	if item == null:
		return

	var stats: PlayerStats = owner_player.get_node_or_null("PlayerStats")
	if stats == null:
		return

	match item["id"]:
		"bread":
			stats.eat(20.0)  # حسب جدول 5.3: خبز يشفي الجوع +20%
			remove_item("bread", 1)
		"water_flask":
			stats.drink(30.0)  # قارورة ماء تشفي العطش +30%
			remove_item("water_flask", 1)
		"berry":
			stats.eat(5.0)
			remove_item("berry", 1)
		"small_health_potion":
			stats.heal(30)
			remove_item("small_health_potion", 1)
		"medium_health_potion":
			stats.heal(70)
			remove_item("medium_health_potion", 1)
		"stamina_potion":
			stats.stamina = min(stats.max_stamina, stats.stamina + 40)
			remove_item("stamina_potion", 1)
		_:
			pass  # عناصر تانية (أسلحة/دروع) هتتلبس مش تتاكل — منطق تاني لاحقاً


# ── حفظ/تحميل ──
func save_inventory() -> void:
	var data := {"slots": slots}
	NetworkManager.save_player_data("player_progress", "inventory", data)


func _load_saved_inventory() -> void:
	var defaults := {"slots": []}
	var data: Dictionary = await NetworkManager.load_player_data("player_progress", "inventory", defaults)
	var loaded: Array = data.get("slots", [])
	if loaded.size() > 0:
		slots = loaded
		slots.resize(MAX_SLOTS)
	else:
		# مخزون ابتدائي حسب الوثيقة: نصف رغيف خبز
		add_item("bread", "نصف رغيف خبز", "consumable", 1)
	inventory_changed.emit()
