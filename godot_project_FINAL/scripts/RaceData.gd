extends Node
# RaceData.gd — Autoload (Singleton) اسمه "RaceData"
# بيانات الأعراق الخمسة بالظبط حسب جدول 3.2 في الوثيقة الأصلية

const RACES := {
	"human": {
		"name_ar": "البشر", "folder": "human",
		"speed_mod": 0.0, "ranged_accuracy_mod": 0.0,
		"defense_mod": 0.0, "magic_resist_mod": 0.0,
		"fire_damage_mod": 0.0, "black_magic_mod": 0.0,
		"hp_mod": 0.0, "physical_damage_mod": 0.0, "intelligence_mod": 0.0,
	},
	"elf": {
		"name_ar": "الإلفز", "folder": "elf",
		"speed_mod": 0.05, "ranged_accuracy_mod": 0.05,
		"defense_mod": 0.0, "magic_resist_mod": 0.0,
		"fire_damage_mod": 0.0, "black_magic_mod": 0.0,
		"hp_mod": 0.0, "physical_damage_mod": 0.0, "intelligence_mod": 0.0,
	},
	"dwarf": {
		"name_ar": "الأقزام", "folder": "dwarf",
		"speed_mod": -0.05, "ranged_accuracy_mod": 0.0,
		"defense_mod": 0.10, "magic_resist_mod": 0.05,
		"fire_damage_mod": 0.0, "black_magic_mod": 0.0,
		"hp_mod": 0.0, "physical_damage_mod": 0.0, "intelligence_mod": 0.0,
	},
	"demon": {
		"name_ar": "الشياطين", "folder": "demon",
		"speed_mod": 0.0, "ranged_accuracy_mod": 0.0,
		"defense_mod": -0.05, "magic_resist_mod": 0.0,
		"fire_damage_mod": 0.10, "black_magic_mod": 0.05,
		"hp_mod": 0.0, "physical_damage_mod": 0.0, "intelligence_mod": 0.0,
	},
	"beast": {
		"name_ar": "الوحوش", "folder": "beast",
		"speed_mod": -0.05, "ranged_accuracy_mod": 0.0,
		"defense_mod": 0.0, "magic_resist_mod": 0.0,
		"fire_damage_mod": 0.0, "black_magic_mod": 0.0,
		"hp_mod": 0.15, "physical_damage_mod": 0.05, "intelligence_mod": -0.05,
	},
}

const RACE_ORDER := ["human", "elf", "dwarf", "demon", "beast"]


func get_race(race_id: String) -> Dictionary:
	return RACES.get(race_id, RACES["human"])


func is_valid_race(race_id: String) -> bool:
	return RACES.has(race_id)
