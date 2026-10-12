class_name MeleeTargeting
extends RefCounted
# MeleeTargeting.gd — اختيار هدف الضربة: أقرب عدو قدّام اللاعب جوه المدى والزاوية.
# اللاعب بيلف بـ atan2(x, z)، فالأمام عنده هو +Z المحلي (مش -Z).

const MAX_HEIGHT_DIFF := 2.0


static func facing_of(basis: Basis) -> Vector3:
	return basis.z.normalized()


# targets = مواقع الأعداء. بيرجّع index أقرب هدف صالح أو -1
static func pick(origin: Vector3, facing: Vector3, targets: Array, attack_range: float, half_arc_deg: float) -> int:
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length() < 0.001:
		return -1
	f = f.normalized()
	var best := -1
	var best_dist := INF
	for i in targets.size():
		var t: Vector3 = targets[i]
		if absf(t.y - origin.y) > MAX_HEIGHT_DIFF:
			continue
		var d := Vector3(t.x - origin.x, 0.0, t.z - origin.z)
		var dist := d.length()
		if dist > attack_range:
			continue
		if dist > 0.001 and rad_to_deg(f.angle_to(d / dist)) > half_arc_deg:
			continue
		if dist < best_dist:
			best = i
			best_dist = dist
	return best
