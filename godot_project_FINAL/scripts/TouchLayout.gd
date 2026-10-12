class_name TouchLayout
extends RefCounted
# TouchLayout.gd — تخطيط أزرار اللمس. دوال static بس (بدون عقد) عشان تتختبر بسهولة.
# كل المقاسات متحسوبة نسبةً لارتفاع الشاشة (مرجع 720) فالأزرار بتكبر مع الشاشة والكثافة.

const REFERENCE_HEIGHT := 720.0


static func scale_for(size: Vector2) -> float:
	return clampf(minf(size.x, size.y) / REFERENCE_HEIGHT, 0.6, 3.0)


# بيرجّع {scale, joystick:{center,radius}, buttons:{attack,jump,run,interact: {center,radius}}}
static func compute(size: Vector2) -> Dictionary:
	var s := scale_for(size)
	var margin := 40.0 * s
	var jr := 95.0 * s
	var joystick_center := Vector2(margin + jr + 20.0 * s, size.y - margin - jr)
	var a := Vector2(size.x - margin - 80.0 * s, size.y - margin - 80.0 * s)   # مركز زر الهجوم
	return {
		"scale": s,
		"joystick": {"center": joystick_center, "radius": jr},
		"buttons": {
			"attack": {"center": a, "radius": 75.0 * s},
			"jump": {"center": a + Vector2(-20.0, -150.0) * s, "radius": 55.0 * s},
			"run": {"center": a + Vector2(-165.0, 5.0) * s, "radius": 50.0 * s},
			"interact": {"center": a + Vector2(-150.0, -130.0) * s, "radius": 50.0 * s},
		},
	}


# أي عنصر اتلمس؟ بيرجّع "attack" / "jump" / "run" / "interact" / "joystick" أو "" لو لا حاجة
static func hit_test(layout: Dictionary, pos: Vector2) -> String:
	for k in ["attack", "jump", "run", "interact"]:
		var b: Dictionary = layout["buttons"][k]
		if pos.distance_to(b["center"]) <= float(b["radius"]) * 1.15:
			return k
	var j: Dictionary = layout["joystick"]
	if pos.distance_to(j["center"]) <= float(j["radius"]) * 1.6:
		return "joystick"
	return ""
