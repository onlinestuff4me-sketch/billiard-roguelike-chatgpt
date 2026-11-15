class_name Items
extends RefCounted
## Loot generation. Simplified for mobile: three slots, a handful of stats,
## and gear that auto-equips when it is an upgrade.

enum Rarity { WORN, TEMPERED, GILDED, ASHBORN }

const RARITY_NAMES := ["Worn", "Tempered", "Gilded", "Ashborn"]
const RARITY_COLORS := [
	Color(0.78, 0.76, 0.72),
	Color(0.45, 0.75, 1.0),
	Color(1.0, 0.82, 0.3),
	Color(1.0, 0.4, 0.15),
]
const SLOTS := ["weapon", "armor", "charm"]
const BASES := {
	"weapon": ["Notched Cleaver", "Gloam Blade", "Warden's Maul", "Thornhook", "Pale Glaive"],
	"armor": ["Sackcloth Hauberk", "Ribbed Cuirass", "Mourning Plate", "Lantern Coat"],
	"charm": ["Ember Locket", "Saint's Knucklebone", "Moth Sigil", "Cracked Reliquary"],
}
const PREFIXES := ["Smoldering", "Grim", "Vigilant", "Hollow", "Bitter", "Lamplit", "Sorrowed"]
const SUFFIXES := ["of the Mire", "of Last Light", "of Ash", "of the Gloam", "of Thorns", "of Vigil"]


static func roll_rarity(rng: RandomNumberGenerator, depth: int, luck := 0.0) -> int:
	var r := rng.randf() - depth * 0.012 - luck
	if r < 0.03:
		return Rarity.ASHBORN
	if r < 0.14:
		return Rarity.GILDED
	if r < 0.42:
		return Rarity.TEMPERED
	return Rarity.WORN


static func generate(rng: RandomNumberGenerator, depth: int, luck := 0.0) -> Dictionary:
	var slot: String = SLOTS[rng.randi() % SLOTS.size()]
	var rarity := roll_rarity(rng, depth, luck)
	var power: float = (1.0 + depth * 0.35) * [1.0, 1.4, 1.9, 2.7][rarity]
	var stats := {}
	match slot:
		"weapon":
			stats["damage"] = int(round((6 + rng.randi_range(0, 4)) * power))
		"armor":
			stats["armor"] = int(round((3 + rng.randi_range(0, 3)) * power))
			stats["max_hp"] = int(round(8 * power))
		"charm":
			stats["crit"] = snappedf(0.03 * power, 0.01)
	var extra_pool := ["max_hp", "lifesteal", "attack_speed", "crit", "damage"]
	for i in rarity:
		var k: String = extra_pool[rng.randi() % extra_pool.size()]
		match k:
			"max_hp":
				stats[k] = stats.get(k, 0) + int(round(6 * power))
			"lifesteal":
				stats[k] = snappedf(stats.get(k, 0.0) + 0.02 * (1 + rarity), 0.01)
			"attack_speed":
				stats[k] = snappedf(stats.get(k, 0.0) + 0.06 * (1 + rarity), 0.01)
			"crit":
				stats[k] = snappedf(stats.get(k, 0.0) + 0.02 * power, 0.01)
			"damage":
				stats[k] = stats.get(k, 0) + int(round(2 * power))
	var base: String = BASES[slot][rng.randi() % BASES[slot].size()]
	var item_name := base
	if rarity >= Rarity.TEMPERED:
		item_name = "%s %s" % [PREFIXES[rng.randi() % PREFIXES.size()], base]
	if rarity >= Rarity.GILDED:
		item_name += " " + SUFFIXES[rng.randi() % SUFFIXES.size()]
	return {"slot": slot, "rarity": rarity, "name": item_name, "stats": stats}


## A single number used to decide whether a drop is an upgrade.
static func score(item: Dictionary) -> float:
	if item.is_empty():
		return -1.0
	var s: Dictionary = item["stats"]
	return (s.get("damage", 0) * 1.0 + s.get("armor", 0) * 1.2 + s.get("max_hp", 0) * 0.35
		+ s.get("crit", 0.0) * 120.0 + s.get("lifesteal", 0.0) * 150.0 + s.get("attack_speed", 0.0) * 90.0)


static func describe(item: Dictionary) -> String:
	var parts: PackedStringArray = []
	var s: Dictionary = item["stats"]
	for k in s:
		var v = s[k]
		match k:
			"damage": parts.append("+%d dmg" % v)
			"armor": parts.append("+%d armor" % v)
			"max_hp": parts.append("+%d life" % v)
			"crit": parts.append("+%d%% crit" % int(v * 100))
			"lifesteal": parts.append("+%d%% leech" % int(v * 100))
			"attack_speed": parts.append("+%d%% speed" % int(v * 100))
	return ", ".join(parts)
