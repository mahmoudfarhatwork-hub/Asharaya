extends Node
class_name PlayerStats
# PlayerStats.gd — يُضاف كـ child node اسمه بالظبط "PlayerStats" تحت اللاعب
# القيم الافتراضية هنا لكلاس "محارب" (Warrior) حسب جدول V5 — غيّرها حسب كلاس اللاعب

@export var class_name_ar: String = "محارب"
@export var max_hp: int = 120
@export var max_stamina: float = 100.0
@export var base_damage: int = 12
@export var base_defense: int = 8
@export var move_speed: float = 5.0

var race_id: String = "human"
var profession_id: String = "warrior"

# القيم الأساسية لكل مهنة حسب جدول 3.1 في الوثيقة (قبل تعديلات العرق)
const PROFESSION_BASE_STATS := {
	"warrior":       {"hp": 120, "stamina": 100.0, "damage": 12, "defense": 8, "speed": 5.0},
	"mage":          {"hp": 80,  "stamina": 80.0,  "damage": 8,  "defense": 3, "speed": 5.0},
	"trader":        {"hp": 90,  "stamina": 90.0,  "damage": 5,  "defense": 4, "speed": 5.0},
	"blacksmith":    {"hp": 100, "stamina": 95.0,  "damage": 7,  "defense": 6, "speed": 4.5},
	"farmer":        {"hp": 95,  "stamina": 95.0,  "damage": 6,  "defense": 5, "speed": 4.5},
	"sorcerer":      {"hp": 75,  "stamina": 85.0,  "damage": 10, "defense": 2, "speed": 5.0},   # مشعوذ
	"priest":        {"hp": 90,  "stamina": 100.0, "damage": 6,  "defense": 5, "speed": 4.8},   # كاهن
	"healer":        {"hp": 85,  "stamina": 100.0, "damage": 4,  "defense": 4, "speed": 5.0},   # معالج
	"beast_tamer":   {"hp": 100, "stamina": 95.0,  "damage": 9,  "defense": 5, "speed": 5.2},   # مروض وحوش
}


# يُستدعى مرة واحدة من GameManager بعد إنشاء/تحميل الشخصية — يطبّق
# إحصائيات المهنة الأساسية ثم يعدّلها بنسب العرق (V6)
func apply_character_data(new_race_id: String, new_profession_id: String) -> void:
	race_id = new_race_id
	profession_id = new_profession_id

	var base: Dictionary = PROFESSION_BASE_STATS.get(profession_id, PROFESSION_BASE_STATS["warrior"])
	var race: Dictionary = RaceData.get_race(race_id)

	max_hp = int(base["hp"] * (1.0 + race.get("hp_mod", 0.0)))
	max_stamina = base["stamina"]
	base_damage = int(base["damage"] * (1.0 + race.get("physical_damage_mod", 0.0)))
	base_defense = int(base["defense"] * (1.0 + race.get("defense_mod", 0.0)))
	move_speed = base["speed"] * (1.0 + race.get("speed_mod", 0.0))

	hp = max_hp
	stamina = max_stamina
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)

var hp: int
var stamina: float
var level: int = 1
var xp: int = 0
var xp_to_next_level: int = 100   # حسب الوثيقة: 100 XP للوصول للمستوى 2

# نظام العملات القديم اتشال — استخدم Autoload الجديد "CurrencySystem" بدلاً منه
# (سبع عملات: حديدية، نحاسية، برونزية، فضية، ذهبية، ذهبية ملكية، ماسية)

var hunger: float = 100.0   # يتناقص 2% كل 5 دقايق حسب الوثيقة
var thirst: float = 100.0   # يتناقص 3% كل 5 دقايق حسب الوثيقة

const STAMINA_DRAIN_PER_SEC := 15.0
const STAMINA_REGEN_PER_SEC := 10.0
const HUNGER_DRAIN_PER_SEC := (2.0 / 100.0) / (5.0 * 60.0) * 100.0  # 2% كل 5 دقايق -> نسبة/ثانية
const THIRST_DRAIN_PER_SEC := (3.0 / 100.0) / (5.0 * 60.0) * 100.0

signal hp_changed(current: int, max: int)
signal stamina_changed(current: float, max: float)
signal xp_changed(current: int, needed: int, level: int)
signal died
signal level_up(new_level: int)


func _ready() -> void:
	hp = max_hp
	stamina = max_stamina
	_load_saved_data()


func _process(delta: float) -> void:
	# تجدد الستامينا (إلا لو بيجري — بيتحكم فيها notify_running)
	hunger = max(0.0, hunger - HUNGER_DRAIN_PER_SEC * delta)
	thirst = max(0.0, thirst - THIRST_DRAIN_PER_SEC * delta)


func can_run() -> bool:
	return stamina > 0


func notify_running(is_running: bool) -> void:
	if is_running:
		stamina = max(0.0, stamina - STAMINA_DRAIN_PER_SEC * get_process_delta_time())
	else:
		stamina = min(max_stamina, stamina + STAMINA_REGEN_PER_SEC * get_process_delta_time())
	stamina_changed.emit(stamina, max_stamina)


func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		died.emit()


func heal(amount: int) -> void:
	hp = min(max_hp, hp + amount)
	hp_changed.emit(hp, max_hp)


func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next_level:
		xp -= xp_to_next_level
		level += 1
		xp_to_next_level = 100 * level  # تدرج بسيط — عدّله لو عايز منحنى مختلف
		max_hp += 10  # زيادة بسيطة لكل مستوى، عدّلها براحتك
		hp = max_hp
		level_up.emit(level)
	xp_changed.emit(xp, xp_to_next_level, level)


func add_coins(iron: int = 0, bronze: int = 0) -> void:
	# متبقية للتوافق مع كود قديم بينادي عليها — بتحول القيمة لنظام CurrencySystem الرسمي
	if iron != 0:
		CurrencySystem.add_iron_value(iron)
	if bronze != 0:
		CurrencySystem.add_coins(CurrencySystem.Coin.BRONZE, bronze)


func get_hp_data() -> Dictionary:
	return {"hp": hp, "max_hp": max_hp, "level": level}


func eat(hunger_restore: float) -> void:
	hunger = min(100.0, hunger + hunger_restore)


func drink(thirst_restore: float) -> void:
	thirst = min(100.0, thirst + thirst_restore)


# ── حفظ/تحميل (بيستخدم NetworkManager اللي مبني على Nakama Storage) ──
func save_data() -> void:
	var data := {
		"hp": hp, "max_hp": max_hp, "level": level, "xp": xp,
		"xp_to_next_level": xp_to_next_level,
		"wallet": CurrencySystem.save_state(),
		"hunger": hunger, "thirst": thirst,
	}
	NetworkManager.save_player_data("player_progress", "stats", data)


func _load_saved_data() -> void:
	var defaults := {
		"hp": max_hp, "max_hp": max_hp, "level": 1, "xp": 0,
		"xp_to_next_level": 100, "wallet": CurrencySystem.save_state(),
		"hunger": 100.0, "thirst": 100.0,
	}
	var data: Dictionary = await NetworkManager.load_player_data("player_progress", "stats", defaults)
	hp = data.get("hp", max_hp)
	max_hp = data.get("max_hp", max_hp)
	level = data.get("level", 1)
	xp = data.get("xp", 0)
	xp_to_next_level = data.get("xp_to_next_level", 100)
	if data.has("wallet"):
		CurrencySystem.load_state(data["wallet"])
	hunger = data.get("hunger", 100.0)
	thirst = data.get("thirst", 100.0)
	hp_changed.emit(hp, max_hp)
	xp_changed.emit(xp, xp_to_next_level, level)
