extends Node
# =====================================================================
# Asharaya — TimeManager (Autoload)
# =====================================================================
# القلب النابض لكل الأنظمة التانية (اقتصاد/طقس/NPCs): بيحوّل الوقت
# الحقيقي لوقت داخل اللعبة، وبيحرّك الشمس والإضاءة تلقائيًا.
#
# النسبة المطلوبة: ١٠ دقائق حقيقية = ساعة لعبة واحدة.
# يعني: يوم كامل جوه اللعبة (٢٤ ساعة) = ٢٤٠ دقيقة حقيقية = ٤ ساعات حقيقية.
#
# الفصول: افتراضيًا ٧ أيام لعبة لكل فصل (قابل للتعديل من SEASON_LENGTH_DAYS
# تحت — معلش محددتش عدد لأنك مقلتش، ده افتراض قابل للتغيير في ثانية).
# =====================================================================

signal hour_changed(hour: int)
signal day_changed(day: int)
signal season_changed(season_name: String)
signal sunrise
signal sunset

const REAL_SECONDS_PER_GAME_HOUR: float = 600.0  # 10 دقائق حقيقية
const GAME_HOURS_PER_DAY: float = 24.0
const SEASON_LENGTH_DAYS: int = 7  # ← عدّل الرقم ده براحتك لما تحدد مدة الفصل

const SEASONS: Array[String] = ["الربيع", "الصيف", "الخريف", "الشتاء"]

# ألوان السما التقريبية لكل مرحلة من اليوم (تتغيّر بالتدريج بينهم)
const SKY_NIGHT := Color(0.03, 0.03, 0.08)
const SKY_DAWN := Color(0.9, 0.55, 0.35)
const SKY_DAY := Color(0.5, 0.75, 0.95)
const SKY_DUSK := Color(0.85, 0.4, 0.3)

var game_hour: float = 8.0       # نبدأ الساعة ٨ صباحًا (قابل للتغيير)
var game_day: int = 1
var season_index: int = 0
var time_scale: float = 1.0      # لو حبيت توقف/تسرّع الوقت (مفيد وقت الديبج)
var paused: bool = false

var _last_hour_int: int = -1
var _last_day: int = -1
var _last_season: int = -1
var _was_night: bool = false

var _sun: DirectionalLight3D = null
var _world_env: WorldEnvironment = null


func _ready() -> void:
    _find_scene_refs()
    _apply_visuals()  # تطبيق فوري عشان اللعبة متبدأش بإضاءة غلط لحظة الـ Ready


func _find_scene_refs() -> void:
    _sun = get_tree().get_root().find_child("Sun", true, false) as DirectionalLight3D
    _world_env = get_tree().get_root().find_child("WorldEnvironment", true, false) as WorldEnvironment


func _process(delta: float) -> void:
    if paused:
        return

    if _sun == null or _world_env == null:
        # المشهد ممكن يكون لسه بيتحمّل وقت أول فريم أو اتغيّر (تغيير مشهد)
        _find_scene_refs()
        if _sun == null or _world_env == null:
            return

    game_hour += (delta * time_scale) / REAL_SECONDS_PER_GAME_HOUR
    if game_hour >= GAME_HOURS_PER_DAY:
        game_hour -= GAME_HOURS_PER_DAY
        game_day += 1
        emit_signal("day_changed", game_day)

        var new_season := int(((game_day - 1) / SEASON_LENGTH_DAYS)) % SEASONS.size()
        if new_season != _last_season:
            _last_season = new_season
            season_index = new_season
            emit_signal("season_changed", SEASONS[season_index])

    var hour_int := int(game_hour)
    if hour_int != _last_hour_int:
        _last_hour_int = hour_int
        emit_signal("hour_changed", hour_int)

    var is_night := game_hour < 5.5 or game_hour > 19.5
    if is_night != _was_night:
        _was_night = is_night
        emit_signal("sunset" if is_night else "sunrise")

    _apply_visuals()


func _apply_visuals() -> void:
    if _sun == null or _world_env == null or _world_env.environment == null:
        return

    # زاوية الشمس: الساعة ٦ = شروق (أفق شرق)، ١٢ = فوق دماغك، ١٨ = غروب
    var day_fraction := game_hour / GAME_HOURS_PER_DAY
    var sun_angle := (day_fraction * TAU) - (PI * 0.5)
    _sun.rotation.x = sun_angle

    # طاقة الشمس: بتخفت بالليل لحد شبه صفر، بتقوى بالنهار
    var height_factor := sin(sun_angle)
    _sun.light_energy = clamp(height_factor + 0.15, 0.0, 1.0) * 1.2

    # لون السما: بنمزج بين ٤ مراحل حسب وقت اليوم
    var sky_color: Color
    if game_hour < 5.0:
        sky_color = SKY_NIGHT
    elif game_hour < 7.0:
        sky_color = SKY_NIGHT.lerp(SKY_DAWN, (game_hour - 5.0) / 2.0)
    elif game_hour < 9.0:
        sky_color = SKY_DAWN.lerp(SKY_DAY, (game_hour - 7.0) / 2.0)
    elif game_hour < 17.0:
        sky_color = SKY_DAY
    elif game_hour < 19.0:
        sky_color = SKY_DAY.lerp(SKY_DUSK, (game_hour - 17.0) / 2.0)
    elif game_hour < 21.0:
        sky_color = SKY_DUSK.lerp(SKY_NIGHT, (game_hour - 19.0) / 2.0)
    else:
        sky_color = SKY_NIGHT

    _world_env.environment.background_color = sky_color
    _world_env.environment.ambient_light_color = sky_color
    _world_env.environment.ambient_light_energy = clamp(height_factor * 0.5 + 0.15, 0.05, 0.65)


# ---------------------------------------------------------------
# دوال مساعدة للأنظمة التانية (اقتصاد/طقس/NPCs) تستخدمها براحتها
# ---------------------------------------------------------------
func is_night() -> bool:
    return _was_night

func get_current_season() -> String:
    return SEASONS[season_index]

func get_time_string() -> String:
    var h := int(game_hour)
    var m := int((game_hour - h) * 60.0)
    return "%02d:%02d" % [h, m]

func set_time_scale(scale: float) -> void:
    time_scale = max(0.0, scale)
