extends Node
# =====================================================================
# Asharaya — PerformanceManager (Autoload Singleton)
# =====================================================================
# الهدف: نظام واحد يتحكم في كل إعدادات الأداء تلقائياً حسب الجهاز،
# بدل ما تكتب كود منفصل لكل منصة. اللعبة تكتشف الجهاز وتضبط نفسها.
#
# التثبيت (خطوة واحدة):
#   Project > Project Settings > Autoload > أضف هذا الملف باسم "Perf"
#
# الاستخدام في أي سكريبت تاني:
#   if Perf.tier >= Perf.Tier.MEDIUM: ... إظهار تفاصيل إضافية
#   var max_npcs = Perf.get_active_npc_limit()
# =====================================================================

enum Tier { POTATO, LOW, MEDIUM, HIGH, ULTRA }

var tier: Tier = Tier.MEDIUM
var platform: String = ""
var is_windows_exclusive_allowed: bool = false

# --- إعدادات كل مستوى (Tier Profiles) ---
# القيم دي مش عشوائية — كل واحدة مبنية على القيود الحقيقية للأجهزة
var _profiles = {
	Tier.POTATO: {
		"name": "Potato (هواتف 2-3GB RAM)",
		"shadow_enabled": false,
		"max_shadow_size": 0,
		"draw_distance": 35.0,
		"fog_enabled": true,           # الضباب بيغطي قص المسافة، يوفر رسم كامل
		"max_active_npcs": 15,
		"max_lights": 4,
		"multimesh_grass_count": 60,
		"multimesh_tree_count": 15,
		"particle_multiplier": 0.0,    # إيقاف الجسيمات تماماً
		"physics_fps": 30,
		"texture_max_size": 512,
		"msaa": 0,
		"glow_enabled": false,
	},
	Tier.LOW: {
		"name": "Low (هواتف 3-4GB RAM)",
		"shadow_enabled": false,
		"max_shadow_size": 0,
		"draw_distance": 55.0,
		"fog_enabled": true,
		"max_active_npcs": 30,
		"max_lights": 8,
		"multimesh_grass_count": 150,
		"multimesh_tree_count": 30,
		"particle_multiplier": 0.3,
		"physics_fps": 45,
		"texture_max_size": 1024,
		"msaa": 0,
		"glow_enabled": false,
	},
	Tier.MEDIUM: {
		"name": "Medium (هواتف 6GB+ / PC 8GB)",
		"shadow_enabled": true,
		"max_shadow_size": 1024,
		"draw_distance": 90.0,
		"fog_enabled": true,
		"max_active_npcs": 60,
		"max_lights": 16,
		"multimesh_grass_count": 300,
		"multimesh_tree_count": 60,
		"particle_multiplier": 0.7,
		"physics_fps": 60,
		"texture_max_size": 2048,
		"msaa": 1,
		"glow_enabled": true,
	},
	Tier.HIGH: {
		"name": "High (PC 16GB+)",
		"shadow_enabled": true,
		"max_shadow_size": 2048,
		"draw_distance": 150.0,
		"fog_enabled": true,
		"max_active_npcs": 120,
		"max_lights": 32,
		"multimesh_grass_count": 600,
		"multimesh_tree_count": 120,
		"particle_multiplier": 1.0,
		"physics_fps": 60,
		"texture_max_size": 4096,
		"msaa": 2,
		"glow_enabled": true,
	},
	Tier.ULTRA: {
		"name": "Ultra (PC قوي — Windows حصرياً)",
		"shadow_enabled": true,
		"max_shadow_size": 4096,
		"draw_distance": 250.0,
		"fog_enabled": true,
		"max_active_npcs": 250,
		"max_lights": 64,
		"multimesh_grass_count": 1200,
		"multimesh_tree_count": 250,
		"particle_multiplier": 1.0,
		"physics_fps": 60,
		"texture_max_size": 4096,
		"msaa": 3,
		"glow_enabled": true,
	},
}

func _ready():
	platform = OS.get_name()
	_detect_tier()
	_apply_tier_settings()
	print("[Perf] المنصة: %s | المستوى: %s" % [platform, _profiles[tier]["name"]])

# =====================================================================
# اكتشاف المستوى المناسب تلقائياً
# =====================================================================
func _detect_tier():
	# Windows/Linux/macOS = مكتب، بنبدأ من MEDIUM ونطلع لو الرام كفاية
	# Android/iOS = محمول، بنبدأ من LOW ونطلع حسب الرام المتاحة فعلياً
	var mem_info = OS.get_memory_info()
	# "physical" بالبايت — نحوله لجيجا للمقارنة
	var total_ram_gb = float(mem_info.get("physical", 4294967296)) / (1024.0 * 1024.0 * 1024.0)

	if platform == "Android" or platform == "iOS":
		is_windows_exclusive_allowed = false
		if total_ram_gb <= 2.5:
			tier = Tier.POTATO
		elif total_ram_gb <= 4.0:
			tier = Tier.LOW
		elif total_ram_gb <= 6.5:
			tier = Tier.MEDIUM
		else:
			tier = Tier.HIGH  # هاتف قوي بس ULTRA نفسه محجوز للـ Windows فقط
	else:
		# Windows / Linux / macOS
		is_windows_exclusive_allowed = (platform == "Windows")
		if total_ram_gb <= 6.0:
			tier = Tier.MEDIUM
		elif total_ram_gb <= 12.0:
			tier = Tier.HIGH
		else:
			tier = Tier.ULTRA if is_windows_exclusive_allowed else Tier.HIGH

	# السماح بتعديل يدوي من إعدادات اللاعب (لو حفظ تفضيل قبل كده)
	var saved_tier = _load_saved_tier_override()
	if saved_tier != -1:
		tier = saved_tier as Tier

func _load_saved_tier_override() -> int:
	var path = "user://graphics_settings.cfg"
	if not FileAccess.file_exists(path):
		return -1
	var cfg = ConfigFile.new()
	if cfg.load(path) != OK:
		return -1
	return cfg.get_value("graphics", "tier_override", -1)

func save_tier_override(new_tier: Tier):
	var cfg = ConfigFile.new()
	cfg.set_value("graphics", "tier_override", new_tier)
	cfg.save("user://graphics_settings.cfg")
	tier = new_tier
	_apply_tier_settings()

# =====================================================================
# تطبيق الإعدادات فعلياً على المحرك (Godot 4.7 APIs حقيقية)
# =====================================================================
func _apply_tier_settings():
	var p = _profiles[tier]

	# --- الفيزياء: تقليل معدل التحديث على الأجهزة الضعيفة ---
	Engine.physics_ticks_per_second = p["physics_fps"]

	# --- حد أقصى للـ FPS (يوفر بطارية على الموبايل) ---
	if platform == "Android" or platform == "iOS":
		Engine.max_fps = 30 if tier <= Tier.LOW else 60
	else:
		Engine.max_fps = 0  # بدون حد على PC (أو اربطه بمعدل الشاشة لو حبيت)

	# --- الـ MSAA (Anti-Aliasing) ---
	get_viewport().msaa_3d = p["msaa"] as Viewport.MSAA

	# --- الظلال: تُطفأ تماماً على الأجهزة الضعيفة (أكبر موفر أداء منفرد) ---
	RenderingServer.directional_shadow_atlas_set_size(
		p["max_shadow_size"], p["max_shadow_size"] > 2048
	)

	emit_signal_settings_changed()

signal settings_changed
func emit_signal_settings_changed():
	settings_changed.emit()

# =====================================================================
# دوال مساعدة يستخدمها باقي كود اللعبة
# =====================================================================
func get_draw_distance() -> float:
	return _profiles[tier]["draw_distance"]

func get_active_npc_limit() -> int:
	return _profiles[tier]["max_active_npcs"]

func get_max_lights() -> int:
	return _profiles[tier]["max_lights"]

func get_grass_instance_count() -> int:
	return _profiles[tier]["multimesh_grass_count"]

func get_tree_instance_count() -> int:
	return _profiles[tier]["multimesh_tree_count"]

func get_particle_multiplier() -> float:
	return _profiles[tier]["particle_multiplier"]

func are_shadows_enabled() -> bool:
	return _profiles[tier]["shadow_enabled"]

func is_glow_enabled() -> bool:
	return _profiles[tier]["glow_enabled"]

# --- ميزات حصرية على Windows (مثال: راهد كبير، محاكاة طقس متقدمة) ---
func is_feature_available(feature_name: String) -> bool:
	var windows_only_features = ["large_scale_raid", "advanced_weather_particles", "volumetric_fog"]
	if feature_name in windows_only_features:
		return is_windows_exclusive_allowed and tier >= Tier.HIGH
	return true
