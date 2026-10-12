class_name QuaterniusCharacter
extends RefCounted
# QuaterniusCharacter.gd — شخصية Quaternius (Universal Base Characters) + حركات UAL 1 و2.
# الجسم والحركات بنفس الهيكل (65 عظمة)، فالحركات بتركّب مباشرة بدون إعادة ربط.
# CC0 — الأصول في res://assets/characters/quaternius/

const DIR := "res://assets/characters/quaternius/"
const BODY := {
	"male": DIR + "Superhero_Male_FullBody.gltf",
	"female": DIR + "Superhero_Female_FullBody.gltf",
}
const ANIM_FILES := [
	DIR + "animations/UAL1_Standard.glb",
	DIR + "animations/UAL2_Standard.glb",
]
const LIBRARY := "ual"
const SPRINT_SPEED := 9.0   # الجري العادي ≈ 8، فالـ Sprint لسرعات أعلى (بفّات مستقبلاً)

# الحركات اللي لازم تتكرر (Quaternius بيسيب loop مقفول لأن الأسماء من غير لاحقة _loop)
const LOOPING := [
	"Idle", "Walk", "Jog_Fwd", "Sprint", "Walk_Formal", "Walk_Carry", "Jump",
	"Sword_Idle", "Crouch_Idle", "Crouch_Fwd", "Swim_Fwd", "Swim_Idle",
	"Sitting_Idle", "Idle_Talking", "Idle_Torch", "Idle_Shield", "Idle_Lantern",
	"Idle_FoldArms", "Spell_Simple_Idle", "Pistol_Idle", "Zombie_Idle",
	"Zombie_Walk_Fwd", "Dance", "Driving", "NinjaJump_Idle",
]

static var _library_cache: AnimationLibrary = null


static func has_assets() -> bool:
	for path in BODY.values():
		if not ResourceLoader.exists(path):
			return false
	for path in ANIM_FILES:
		if not ResourceLoader.exists(path):
			return false
	return true


# بيبني الجسم + AnimationPlayer فيه مكتبة "ual" ويضيفه تحت parent باسم HumanBody
static func build(parent: Node3D, gender: String, _appearance_seed: int = 0) -> Node3D:
	var key := "female" if gender == "female" else "male"
	if not ResourceLoader.exists(BODY[key]):
		return null
	var scene: PackedScene = load(BODY[key])
	var body: Node3D = scene.instantiate()
	body.name = "HumanBody"
	parent.add_child(body)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	body.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library(LIBRARY, _get_library())
	return body


static func _get_library() -> AnimationLibrary:
	if _library_cache != null:
		return _library_cache
	var lib := AnimationLibrary.new()
	for path in ANIM_FILES:
		if not ResourceLoader.exists(path):
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		var src: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		if src != null:
			for anim_name in src.get_animation_list():
				if anim_name == "A_TPose" or lib.has_animation(anim_name):
					continue
				var anim: Animation = src.get_animation(anim_name).duplicate()
				anim.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPING else Animation.LOOP_NONE
				lib.add_animation(anim_name, anim)
		inst.free()
	_library_cache = lib
	return lib


static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := find_skeleton(child)
		if found != null:
			return found
	return null


static func get_animation_player(body: Node) -> AnimationPlayer:
	return body.get_node_or_null("AnimationPlayer") as AnimationPlayer


# يختار الحركة المناسبة: speed = سرعة الأرض، backward = ماشي لورا
static func pick(speed: float, running: bool, backward: bool, on_floor: bool) -> Dictionary:
	if not on_floor:
		return {"name": "Jump", "speed": 1.0}
	if speed < 0.1:
		return {"name": "Idle", "speed": 1.0}
	if backward:
		return {"name": "Walk", "speed": -1.0}   # مفيش مشي لورا في UAL: نعكس المشي
	if running:
		return {"name": "Sprint" if speed >= SPRINT_SPEED else "Jog_Fwd", "speed": 1.0}
	return {"name": "Walk", "speed": 1.0}


# بيشغّل الحركة المختارة بس لو اتغيّرت (عشان ما نعيدش تشغيل نفس الحركة كل فريم).
# بيرجّع المفتاح الحالي ("اسم|اتجاه") ويتخزّن في اللاعب.
static func play_pick(ap: AnimationPlayer, picked: Dictionary, current_key: String) -> String:
	var anim_name: String = picked["name"]
	var spd: float = picked["speed"]
	var key := "%s|%d" % [anim_name, signi(int(spd * 10.0))]
	if key == current_key:
		return current_key
	var full := LIBRARY + "/" + anim_name
	if not ap.has_animation(full):
		return current_key
	ap.play(full, 0.2, spd)
	return key
