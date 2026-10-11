extends Area3D
class_name TraderNPC
# TraderNPC.gd — للتاجر "ألدريك" حسب جدول 6.1
# حط الملف ده على Area3D عندها CollisionShape3D، وضبّط اسم اللاعب يدخل نطاقها

@export var npc_name: String = "ألدريك"
@export var discount_percent: float = 0.0  # مثلاً 0.1 لو النوع "إلفز" عنده خصم من التجار

# قايمة البضاعة حسب جدول 5.1/5.2/5.3 في الوثيقة (الأسعار كلها بالحديدية إلا لو محدد)
var shop_items := [
	{"id": "bread", "name": "رغيف خبز", "type": "consumable", "price": 2, "currency": "iron"},
	{"id": "water_flask", "name": "قارورة ماء", "type": "consumable", "price": 3, "currency": "iron"},
	{"id": "small_health_potion", "name": "جرعة شفاء صغيرة", "type": "consumable", "price": 5, "currency": "iron"},
	{"id": "stamina_potion", "name": "جرعة طاقة", "type": "consumable", "price": 4, "currency": "iron"},
	{"id": "iron_sword", "name": "سيف حديدي", "type": "weapon", "price": 20, "currency": "iron"},
	{"id": "leather_armor", "name": "درع جلدي صلب", "type": "armor", "price": 35, "currency": "iron"},
]

var _player_in_range: Node = null


func _ready() -> void:
	add_to_group("traders")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		_player_in_range = body
		# TODO: اعرض UI صغير يقول "اضغط E للتحدث مع ألدريك" — مربوط بـ HUD


func _on_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		close_shop()


func try_open_shop_for(player: Node) -> void:
	if player != _player_in_range:
		return
	open_shop(player)


func open_shop(player: Node) -> void:
	var stats: PlayerStats = player.get_node_or_null("PlayerStats")
	var inv: Inventory = player.get_node_or_null("Inventory")
	if stats == null or inv == null:
		return

	# واجهة بسيطة مبنية بالكود (نفس أسلوب HUD/MobileControls)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 300)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "متجر %s" % npc_name
	vbox.add_child(title)

	for item in shop_items:
		var row := HBoxContainer.new()
		var final_price: int = int(item["price"] * (1.0 - discount_percent))

		var label := Label.new()
		label.text = "%s — %d حديدية" % [item["name"], final_price]
		row.add_child(label)

		var buy_btn := Button.new()
		buy_btn.text = "شراء"
		buy_btn.pressed.connect(func():
			if CurrencySystem.try_spend_iron_value(final_price):
				inv.add_item(item["id"], item["name"], item["type"], 1)
				inv.save_inventory()
		)
		row.add_child(buy_btn)
		vbox.add_child(row)

	var close_btn := Button.new()
	close_btn.text = "إغلاق"
	close_btn.pressed.connect(func(): panel.queue_free())
	vbox.add_child(close_btn)

	get_tree().root.add_child(panel)


func close_shop() -> void:
	pass  # لو محتاج تتبع مرجع البانل وتقفله تلقائي وقت الخروج من النطاق، قولي وأضيفه
