extends CanvasLayer
# HUD.gd — Autoload (Singleton) اسمه "HUD"
# ملحوظة: لا يوجد class_name هنا عمداً — الاسم "HUD" مستخدم بالفعل كاسم
# للـ Autoload في project.godot، ووجود class_name بنفس الاسم في نفس الوقت
# يعمل تعارض بيخلي Godot يرفض تحليل الملف (Parse error)
# مبني بالكود بالكامل (نودز جاهزة زي ProgressBar، مفيش خطر تنسيق ملفات .tscn يدوية)
# ينادى عليه الـ Player المحلي بالسطر: HUD.bind_to_stats(stats)

var hp_bar: ProgressBar
var stamina_bar: ProgressBar
var xp_bar: ProgressBar
var level_label: Label
var coins_label: Label
var hunger_label: Label
var thirst_label: Label

var _bound_stats: PlayerStats = null


func _ready() -> void:
	layer = 50
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var container := VBoxContainer.new()
	container.position = Vector2(20, 20)
	container.custom_minimum_size = Vector2(250, 0)
	root.add_child(container)

	level_label = Label.new()
	level_label.text = "Level 1"
	container.add_child(level_label)

	hp_bar = ProgressBar.new()
	hp_bar.max_value = 120
	hp_bar.value = 120
	hp_bar.modulate = Color(1, 0.2, 0.2)
	container.add_child(hp_bar)

	stamina_bar = ProgressBar.new()
	stamina_bar.max_value = 100
	stamina_bar.value = 100
	stamina_bar.modulate = Color(0.2, 1, 0.2)
	container.add_child(stamina_bar)

	xp_bar = ProgressBar.new()
	xp_bar.max_value = 100
	xp_bar.value = 0
	xp_bar.modulate = Color(0.2, 0.5, 1)
	container.add_child(xp_bar)

	coins_label = Label.new()
	coins_label.text = "🪙 0 حديدية | 0 برونزية"
	container.add_child(coins_label)

	hunger_label = Label.new()
	hunger_label.text = "🍞 جوع: 100%"
	container.add_child(hunger_label)

	thirst_label = Label.new()
	thirst_label.text = "💧 عطش: 100%"
	container.add_child(thirst_label)


func bind_to_stats(stats: PlayerStats) -> void:
	_bound_stats = stats
	stats.hp_changed.connect(_on_hp_changed)
	stats.stamina_changed.connect(_on_stamina_changed)
	stats.xp_changed.connect(_on_xp_changed)

	_on_hp_changed(stats.hp, stats.max_hp)
	_on_stamina_changed(stats.stamina, stats.max_stamina)
	_on_xp_changed(stats.xp, stats.xp_to_next_level, stats.level)


func _process(_delta: float) -> void:
	if _bound_stats:
		coins_label.text = "🪙 %s" % CurrencySystem.get_display_string()
		hunger_label.text = "🍞 جوع: %d%%" % int(_bound_stats.hunger)
		thirst_label.text = "💧 عطش: %d%%" % int(_bound_stats.thirst)


func _on_hp_changed(current: int, max_val: int) -> void:
	hp_bar.max_value = max_val
	hp_bar.value = current


func _on_stamina_changed(current: float, max_val: float) -> void:
	stamina_bar.max_value = max_val
	stamina_bar.value = current


func _on_xp_changed(current: int, needed: int, level: int) -> void:
	xp_bar.max_value = needed
	xp_bar.value = current
	level_label.text = "Level %d" % level
