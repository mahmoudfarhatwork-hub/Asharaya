extends Node
# AssetAutoLoader.gd — Autoload اسمه "Assets"
# =========================================================================
# نسخة مدمجة: بتغطي المجسمات (زي الأصل) + الصوتيات الجديدة، من غير ما
# تلغي أي حاجة شغالة في الأنظمة التانية — كل الأنظمة برضه بترجع للأشكال
# البدائية/بدون صوت لو الفولدر فاضي، مفيش أي كسر لحاجة موجودة.
#
#   Assets.get_random_mesh("trees")        -> Mesh أو null (لـ MultiMesh)
#   Assets.instantiate_random("village")   -> Node3D جاهز يتضاف كـ child
#   Assets.get_random_sound("sword_hit")   -> AudioStream أو null
#   Assets.play_random(node, "sword_hit")  -> بيشغّل صوت على أي Node مباشرة

const MODELS_ROOT := "res://assets/models/"
const SOUNDS_ROOT := "res://assets/sounds/"
const MUSIC_ROOT := "res://assets/music/"

const MODEL_CATEGORIES := [
	"blocks", "terrain", "trees", "plants", "village", "resources", "weapons",
	"characters", "monsters", "animals", "dungeon",
]

# فئات الصوت — أسماء المجلدات دي هي اللي أي كود تاني هيستخدمها كمفتاح
const SOUND_CATEGORIES := [
	"footsteps", "sword_hit", "impact", "ui", "ambient", "magic",
	"voice_male", "voice_female", "voice_child",
]

# ★ الموسيقى منفصلة عن sounds/ عمدًا — بتتشغّل بمنطق مختلف (لوب طويل/
# قطعة كاملة تتسمع من الأول للآخر) مش "شغّل صوت عشوائي قصير".
const MUSIC_CATEGORIES := ["jingles", "loops"]

var _model_catalog: Dictionary = {}   # category -> Array[PackedScene]
var _sound_catalog: Dictionary = {}   # category -> Array[AudioStream]
var _music_catalog: Dictionary = {}   # category -> Array[AudioStream]


func _ready() -> void:
	reload_catalog()


func reload_catalog() -> void:
	_reload_models()
	_reload_sounds()
	_reload_music()


func _reload_music() -> void:
	_music_catalog.clear()
	var total := 0
	for category in MUSIC_CATEGORIES:
		var streams := _scan_folder(MUSIC_ROOT + category + "/", ["ogg", "wav", "mp3"], func(p): return _load_as_stream(p))
		_music_catalog[category] = streams
		total += streams.size()
		_log_category("music", category, streams.size())
	print("[Assets] إجمالي مقاطع الموسيقى المحمّلة: %d" % total)


func _reload_models() -> void:
	_model_catalog.clear()
	var total := 0
	for category in MODEL_CATEGORIES:
		var scenes := _scan_folder(MODELS_ROOT + category + "/", ["glb", "gltf", "tscn", "fbx"], func(p): return _load_as_scene(p))
		_model_catalog[category] = scenes
		total += scenes.size()
		_log_category("models", category, scenes.size())
	print("[Assets] إجمالي المجسمات المحمّلة: %d" % total)


func _reload_sounds() -> void:
	_sound_catalog.clear()
	var total := 0
	for category in SOUND_CATEGORIES:
		var streams := _scan_folder(SOUNDS_ROOT + category + "/", ["ogg", "wav", "mp3"], func(p): return _load_as_stream(p))
		_sound_catalog[category] = streams
		total += streams.size()
		_log_category("sounds", category, streams.size())
	print("[Assets] إجمالي الأصوات المحمّلة: %d" % total)


func _log_category(kind: String, category: String, count: int) -> void:
	if count == 0:
		print("[Assets] %s/'%s': فاضي — النظام هيستخدم fallback." % [kind, category])
	else:
		print("[Assets] %s/'%s': %d اتحمّل." % [kind, category, count])


func _scan_folder(dir_path: String, extensions: Array, loader: Callable) -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return result
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var lower := file_name.to_lower()
			for ext in extensions:
				if lower.ends_with("." + ext):
					var loaded = loader.call(dir_path + file_name)
					if loaded:
						result.append(loaded)
					break
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _load_as_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path)
	return res if res is PackedScene else null


func _load_as_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path)
	return res if res is AudioStream else null


# ---------------------------------------------------------------
# واجهة المجسمات
# ---------------------------------------------------------------
func has_model_category(category: String) -> bool:
	return _model_catalog.has(category) and not _model_catalog[category].is_empty()

func get_random_model(category: String) -> PackedScene:
	if not has_model_category(category):
		return null
	var arr: Array = _model_catalog[category]
	return arr[randi() % arr.size()]

func instantiate_random(category: String) -> Node3D:
	var packed := get_random_model(category)
	if packed == null:
		return null
	return packed.instantiate() as Node3D

func get_random_mesh(category: String) -> Mesh:
	var packed := get_random_model(category)
	if packed == null:
		return null
	var temp := packed.instantiate()
	var mesh := _find_first_mesh(temp)
	temp.queue_free()
	return mesh

func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh != null:
		return node.mesh
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found:
			return found
	return null


# ---------------------------------------------------------------
# واجهة الصوت
# ---------------------------------------------------------------
func has_sound_category(category: String) -> bool:
	return _sound_catalog.has(category) and not _sound_catalog[category].is_empty()

func get_random_sound(category: String) -> AudioStream:
	if not has_sound_category(category):
		return null
	var arr: Array = _sound_catalog[category]
	return arr[randi() % arr.size()]

# بيشغّل صوت عشوائي من فئة معيّنة على أي Node3D — بيعمل AudioStreamPlayer3D
# مؤقت وبيمسح نفسه لوحده لما يخلص، عشان محدش يحتاج يدير الـ Node يدوي.
func play_random(at_node: Node3D, category: String, volume_db: float = 0.0) -> void:
	var stream := get_random_sound(category)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	at_node.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


# ---------------------------------------------------------------
# واجهة الموسيقى
# ---------------------------------------------------------------
func get_random_music(category: String = "jingles") -> AudioStream:
	if not _music_catalog.has(category) or _music_catalog[category].is_empty():
		return null
	var arr: Array = _music_catalog[category]
	return arr[randi() % arr.size()]

# بيشغّل موسيقى على AudioStreamPlayer عادي (مش 3D — الموسيقى مالهاش
# مكان في العالم، لازم تتسمع بنفس الصوت أيًا كان اللاعب فين)
func play_music_on(player: AudioStreamPlayer, category: String = "jingles") -> void:
	var stream := get_random_music(category)
	if stream:
		player.stream = stream
		player.play()
