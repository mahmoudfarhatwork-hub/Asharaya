extends CanvasLayer
# CharacterCreationUI.gd — Autoload (Singleton) اسمه "CharacterCreationUI"
# ملحوظة: لا يوجد class_name هنا عمداً — نفس سبب HUD.gd (تعارض الاسم مع الـ Autoload)
# بتظهر مرة واحدة بس لأي حساب جديد — بعدها العرق/المهنة/الشكل بيتحفظوا ثابتين

signal character_created(race_id: String, gender: String, profession: String, appearance_seed: int)

var _panel: Control
var _selected_race: String = "human"
var _selected_gender: String = "male"
var _selected_profession: String = "warrior"

const PROFESSIONS := [
	{"id": "warrior", "name_ar": "محارب"},
	{"id": "mage", "name_ar": "ساحر"},
	{"id": "sorcerer", "name_ar": "مشعوذ"},
	{"id": "priest", "name_ar": "كاهن"},
	{"id": "healer", "name_ar": "معالج"},
	{"id": "blacksmith", "name_ar": "حداد"},
	{"id": "trader", "name_ar": "تاجر"},
	{"id": "farmer", "name_ar": "مزارع"},
	{"id": "beast_tamer", "name_ar": "مروض وحوش"},
]


func show_creation_screen() -> void:
	layer = 90
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(450, 400)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "🎭 اصنع شخصيتك في Asharaya"
	vbox.add_child(title)

	# ── اختيار العرق ──
	var race_label := Label.new()
	race_label.text = "العرق:"
	vbox.add_child(race_label)

	var race_option := OptionButton.new()
	for race_id in RaceData.RACE_ORDER:
		race_option.add_item(RaceData.get_race(race_id)["name_ar"])
	race_option.item_selected.connect(func(idx): _selected_race = RaceData.RACE_ORDER[idx])
	vbox.add_child(race_option)

	# ── اختيار الجنس ──
	var gender_label := Label.new()
	gender_label.text = "الجنس:"
	vbox.add_child(gender_label)

	var gender_option := OptionButton.new()
	gender_option.add_item("ذكر")
	gender_option.add_item("أنثى")
	gender_option.item_selected.connect(func(idx): _selected_gender = "male" if idx == 0 else "female")
	vbox.add_child(gender_option)

	# ── اختيار المهنة ──
	var prof_label := Label.new()
	prof_label.text = "المهنة:"
	vbox.add_child(prof_label)

	var prof_option := OptionButton.new()
	for p in PROFESSIONS:
		prof_option.add_item(p["name_ar"])
	prof_option.item_selected.connect(func(idx): _selected_profession = PROFESSIONS[idx]["id"])
	vbox.add_child(prof_option)

	# ── تأكيد ──
	var confirm_btn := Button.new()
	confirm_btn.text = "ابدأ المغامرة"
	confirm_btn.pressed.connect(_on_confirm)
	vbox.add_child(confirm_btn)


func _on_confirm() -> void:
	var user_id: String = NetworkManager.session.user_id if NetworkManager.session else str(randi())
	# seed ثابت مبني على user_id + وقت الإنشاء، عشان حتى لو نفس العرق/الجنس/المهنة
	# اتكررت، الشكل التفصيلي (الألوان والاختلافات) يفضل مختلف
	var appearance_seed: int = CharacterAssembly.seed_from_user_id(user_id + str(Time.get_unix_time_from_system()))

	var data := {
		"race": _selected_race,
		"gender": _selected_gender,
		"profession": _selected_profession,
		"appearance_seed": appearance_seed,
	}
	NetworkManager.save_player_data("player_progress", "character", data)

	character_created.emit(_selected_race, _selected_gender, _selected_profession, appearance_seed)
	queue_free()
