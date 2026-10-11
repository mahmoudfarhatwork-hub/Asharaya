extends CanvasLayer
class_name TitleScreen
# TitleScreen.gd — الشاشة الأولى اللي بتظهر لما اللعبة تفتح
#
# التصميم حسب طلبك بالظبط:
# - نص "تسجيل الدخول" في النص، بيتحرك (نبض + توهج)
# - حواليها مؤثرات ضوئية متحركة (شرارات سحرية، لهب خافت) من أصولنا الحقيقية
# - موسيقى خلفية تلقائية (لو لقت ملف موسيقى بين الأصول)
# - مؤشر "أونلاين/أوفلاين" صغير وثابت أسفل يمين الشاشة، من غير أي حركة أو مؤثرات

signal login_confirmed

const VFX_PATH := "res://assets/vfx/particles/"
const SOUND_PATH := "res://assets/sounds/"

var _login_label: Button
var _pulse_time: float = 0.0
var _particles: Array = []


func _ready() -> void:
	layer = 100
	_build_background()
	_build_particles()
	_build_center_login()
	_build_online_indicator()
	_play_theme_music()
	set_process(true)


func _process(delta: float) -> void:
	# نبض بسيط لنص "تسجيل الدخول" (تكبير/تصغير + توهج تدريجي)
	_pulse_time += delta
	if _login_label:
		var pulse: float = 1.0 + sin(_pulse_time * 2.0) * 0.04
		_login_label.scale = Vector2(pulse, pulse)
		var glow: float = 0.7 + (sin(_pulse_time * 2.0) * 0.5 + 0.5) * 0.3
		_login_label.modulate = Color(1.0, 0.84, 0.55) * glow + Color(0, 0, 0, 1) * (1 - glow) * 0
		_login_label.modulate.a = 1.0

	for p in _particles:
		if is_instance_valid(p):
			p.rotation += delta * 0.15


func _build_background() -> void:
	# خلفية متدرجة داكنة (مفيش صورة خلفية جاهزة عندنا لسه — لو حبيت تضيف
	# صورة "starting image" حقيقية، حطها في res://assets/ui/title_bg.png
	# والكود هيلاقيها تلقائي)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.02, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var bg_image_path := "res://assets/ui/title_bg.png"
	if ResourceLoader.exists(bg_image_path):
		var bg_tex := TextureRect.new()
		bg_tex.texture = load(bg_image_path)
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg_tex)

	# فينيت داكن فوق أي خلفية (يخلي النص في النص بارز)
	var vignette := ColorRect.new()
	vignette.color = Color(0, 0, 0, 0.35)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)


func _build_particles() -> void:
	# شرارات سحرية + لهب خافت حوالين النص — من أصولنا الحقيقية (magic_*, flame_*)
	var screen_size := DisplayServer.screen_get_size()
	var center := Vector2(screen_size.x / 2.0, screen_size.y / 2.0)

	var particle_files: Array[String] = ["magic_01.png", "magic_03.png", "flame_02.png", "flare_01.png", "light_02.png"]
	for i in range(particle_files.size()):
		var path := VFX_PATH + particle_files[i]
		if not ResourceLoader.exists(path):
			continue
		var tex := TextureRect.new()
		tex.texture = load(path)
		tex.custom_minimum_size = Vector2(90, 90)
		tex.size = Vector2(90, 90)
		var angle := (TAU / particle_files.size()) * i
		var radius := 260.0
		tex.position = center + Vector2(cos(angle), sin(angle)) * radius - Vector2(45, 45)
		tex.modulate = Color(1, 1, 1, 0.55)
		tex.pivot_offset = Vector2(45, 45)
		add_child(tex)
		_particles.append(tex)


func _build_center_login() -> void:
	var screen_size := DisplayServer.screen_get_size()
	var center_container := VBoxContainer.new()
	center_container.set_anchors_preset(Control.PRESET_CENTER)
	center_container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(center_container)

	var game_title := Label.new()
	game_title.text = "Asharaya"
	game_title.add_theme_font_size_override("font_size", 42)
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_title.modulate = Color(0.9, 0.75, 0.5)
	center_container.add_child(game_title)

	_login_label = Button.new()
	_login_label.text = "🔑  تسجيل الدخول"
	_login_label.add_theme_font_size_override("font_size", 26)
	_login_label.custom_minimum_size = Vector2(280, 56)
	_login_label.pressed.connect(_on_login_pressed)
	_login_label.mouse_entered.connect(_on_login_hover)
	center_container.add_child(_login_label)


func _build_online_indicator() -> void:
	# مؤشر ثابت، صغير، أسفل يمين، بدون أي حركة أو تأثيرات — زي ما طلبت بالظبط
	var indicator := HBoxContainer.new()
	indicator.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	indicator.position -= Vector2(140, 40)
	add_child(indicator)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.color = Color(0.4, 0.4, 0.4)  # رمادي لحد ما نتأكد من حالة الاتصال الفعلية
	indicator.add_child(dot)

	var label := Label.new()
	label.text = " أوفلاين" if GameConfig.offline_mode else " أونلاين"
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(0.7, 0.7, 0.7)
	indicator.add_child(label)

	if not GameConfig.offline_mode:
		dot.color = Color(0.3, 0.8, 0.3)


func _play_theme_music() -> void:
	# بيدور على أي ملف اسمه فيه "theme" أو "menu" أو "title" في مجلد الصوت،
	# لو لقى حاجة يشغّلها؛ لو لأ، بيسيبها هادي من غير ما يكسر أي حاجة
	var dir := DirAccess.open(SOUND_PATH)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var found_track := ""
	while file_name != "":
		var lower := file_name.to_lower()
		if (lower.contains("theme") or lower.contains("menu") or lower.contains("title")) \
			and (lower.ends_with(".ogg") or lower.ends_with(".wav")):
			found_track = SOUND_PATH + file_name
			break
		file_name = dir.get_next()
	dir.list_dir_end()

	if found_track != "" and ResourceLoader.exists(found_track):
		var player := AudioStreamPlayer.new()
		player.stream = load(found_track)
		player.volume_db = -8.0
		add_child(player)
		player.play()
	# ملحوظة: لو مفيش تراك بعنوان يحتوي theme/menu/title، مفيش موسيقى هتشتغل.
	# أسهل حل: سمّي أي تراك موجود عندك "title_theme.ogg" وحطه في assets/sounds/


func _on_login_hover() -> void:
	# نغمة خفيفة عند المرور على الزرار (ملف حقيقي موجود عندنا فعلاً في assets/sounds/ui)
	var hover_sound := SOUND_PATH + "ui/select_001.ogg"
	if ResourceLoader.exists(hover_sound):
		var p := AudioStreamPlayer.new()
		p.stream = load(hover_sound)
		p.volume_db = -12.0
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)


func _on_login_pressed() -> void:
	login_confirmed.emit()
	queue_free()
