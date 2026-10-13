class_name WorldSettlementIdentity
extends RefCounted

const NAMES := {
	"coast": ["Гавань ветров", "Солёный мыс", "Три бухты", "Парусный берег", "Дальний рейд", "Медный причал"],
	"dry": ["Красный уступ", "Песчаный стан", "Сухой ключ", "Янтарная долина", "Южный рубеж", "Три колодца"],
	"cold": ["Северный порог", "Белый перевал", "Снежная долина", "Серый берег", "Зимний стан", "Каменный кряж"],
	"rock": ["Каменброд", "Медный холм", "Высокий уступ", "Три скалы", "Красный кряж", "Рудный стан"],
	"land": ["Речной брод", "Золотые поля", "Ветряный холм", "Новый стан", "Дальний рубеж", "Дубовый порог", "Тихая долина", "Светлый ключ"]
}

static func name_for(world, cell: Vector2i, nav: Dictionary) -> String:
	var biome := WorldClimate.biome(world, cell)
	var group := "land"
	if biome >= 3: group = "cold"
	elif biome == 1: group = "dry"
	elif not nav.get("coasts", []).is_empty(): group = "coast"
	elif not nav.get("quarries", []).is_empty(): group = "rock"
	var pool: Array = NAMES[group]
	var name_value: String = pool[posmod(hash(Vector3i(cell.x, cell.y, world.world_seed)), pool.size())]
	var used := {}
	for home in world.towns: used[home.name] = true
	if not used.has(name_value): return name_value
	for i in range(2, world.towns.size() + 3):
		var candidate := "%s %d" % [name_value, i]
		if not used.has(candidate): return candidate
	return name_value
