class_name WorldInspector
extends VBoxContainer

signal details_changed
signal selection_changed

const BOLD := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const SUBTLE := Color("685944")
const ALERT := Color("91462f")
var title_label: Label
var subtitle_label: Label
var metrics: GridContainer
var metric_nodes: Array[Dictionary] = []
var notice: PanelContainer
var notice_label: Label
var sections: Dictionary = {}
var identity := ""
var selection_kind := ""
var touch_ui := false
var target_size := 48.0
var revision := 0
var detail_updates := 0
var notice_warning := false
var notice_styles: Array[StyleBoxFlat] = []

func setup(mobile: bool, target: float) -> void:
	touch_ui = mobile
	target_size = target
	add_theme_constant_override("separation", 10)
	title_label = label("Выберите место на карте", 22, AtlasTheme.INK, true)
	add_child(title_label)
	subtitle_label = label("Нажмите на поселение, жителя или клетку.", 13, SUBTLE)
	add_child(subtitle_label)
	metrics = GridContainer.new()
	metrics.columns = 2
	metrics.add_theme_constant_override("h_separation", 8)
	metrics.add_theme_constant_override("v_separation", 8)
	add_child(metrics)
	for i in 4:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", surface(Color("f4e9d0"), Color("bba47e")))
		metrics.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 2)
		card.add_child(body)
		var value := label("", 20, AtlasTheme.INK, true)
		var caption := label("", 14 if mobile else 12, SUBTLE)
		body.add_child(value)
		body.add_child(caption)
		metric_nodes.append({"card": card, "value": value, "caption": caption})
	notice_styles = [surface(Color("d9c7a2"), Color("b59a70")), surface(Color("e8c9ac"), ALERT)]
	notice = PanelContainer.new()
	notice.add_theme_stylebox_override("panel", notice_styles[0])
	add_child(notice)
	notice_label = label("", 14, AtlasTheme.INK)
	notice.add_child(notice_label)
	for item in [["history", "История места"], ["development", "Развитие"], ["technology", "Технологии"], ["economy", "Хозяйство"], ["population", "Жители"], ["civic","Город и общие стройки"], ["network","Связи и переселение"], ["sea", "Морские экспедиции"], ["family", "Семья"], ["skills", "Навыки и характер"], ["relations", "Отношения"], ["building", "Постройка"], ["terrain", "Местность"]]:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		add_child(box)
		var button := Button.new()
		button.text = "▸ " + item[1]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.custom_minimum_size.y = target if mobile else 38.0
		button.add_theme_font_override("font", BOLD)
		button.add_theme_font_size_override("font_size", 16 if mobile else 14)
		box.add_child(button)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 0)
		body.hide()
		box.add_child(body)
		sections[item[0]] = {"box": box, "button": button, "body": body, "title": item[1], "rows": []}
		button.toggled.connect(func(opened: bool): set_expanded(item[0], opened))
	reset()

func label(value: String, font_size: int, color: Color, bold: bool = false) -> Label:
	var node := Label.new()
	node.text = value
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	if bold: node.add_theme_font_override("font", BOLD)
	return node

func surface(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

func reset() -> void:
	identity = ""
	selection_kind = ""
	title_label.text = "Выберите место на карте"
	subtitle_label.text = "Нажмите на поселение, жителя или клетку. Повторное нажатие перебирает жителей в одной точке."
	metrics.hide()
	notice.hide()
	for section in sections.values():
		section.box.hide()
		section.button.set_pressed_no_signal(false)
		section.button.text = "▸ " + section.title
		section.body.hide()

func set_expanded(key: String, opened: bool) -> void:
	var section: Dictionary = sections[key]
	section.button.set_pressed_no_signal(opened)
	section.button.text = ("▾ " if opened else "▸ ") + section.title
	section.body.visible = opened
	details_changed.emit()

func expanded(key: String) -> bool:
	return sections[key].box.visible and sections[key].button.button_pressed

func put(node: Label, value: String) -> void:
	if node.text != value: node.text = value

func metric(index: int, value: String, caption: String, warning: bool = false) -> void:
	var item: Dictionary = metric_nodes[index]
	item.card.show()
	put(item.value, value)
	put(item.caption, caption)
	item.value.add_theme_color_override("font_color", ALERT if warning else AtlasTheme.INK)

func rows(key: String, values: Array) -> void:
	var section: Dictionary = sections[key]
	for i in values.size():
		if i >= section.rows.size():
			var panel := PanelContainer.new()
			var style := surface(Color("eddfc1") if i % 2 == 0 else Color("e7d8b6"), Color.TRANSPARENT)
			style.set_border_width_all(0)
			panel.add_theme_stylebox_override("panel", style)
			section.body.add_child(panel)
			var stack := VBoxContainer.new()
			stack.add_theme_constant_override("separation", 3)
			panel.add_child(stack)
			var heading := label("", 16 if touch_ui else 13, AtlasTheme.INK, true)
			var value := label("", 16 if touch_ui else 13, SUBTLE)
			stack.add_child(heading)
			stack.add_child(value)
			section.rows.append({"panel": panel, "heading": heading, "value": value})
		var item: Dictionary = section.rows[i]
		item.panel.show()
		put(item.heading, str(values[i][0]))
		put(item.value, str(values[i][1]))
		item.value.visible = not str(values[i][1]).is_empty()
	for i in range(values.size(), section.rows.size()): section.rows[i].panel.hide()
	detail_updates += 1

func present(world: WorldState, cell: Vector2i, person: Dictionary, home: Dictionary, building: Dictionary) -> void:
	var site := world.heritage.at(cell)
	var kind := "person" if not person.is_empty() else ("town" if not home.is_empty() else ("site" if not site.is_empty() else "terrain"))
	var key := kind + ":" + (str(person.id) if kind == "person" else (str(home.id) if kind == "town" else (str(site.id) if kind == "site" else str(cell))))
	if identity != key:
		reset()
		identity = key
		selection_kind = kind
		selection_changed.emit()
	metrics.show()
	notice.show()
	var visible_sections: Array = ["terrain"]
	var warning := false
	if kind == "town":
		visible_sections.append_array(["development","technology","economy","population","civic","network","sea"])
		put(title_label, home.name)
		put(subtitle_label, "Поселение · %d, %d" % [home.x, home.y])
		var residents := WorldEconomy.members(world, home).size()
		var housing := WorldEconomy.housing(world, home)
		var runway := WorldEconomy.food_days(world, home)
		metric(0, str(residents), "жителей")
		metric(1, "%d / %d" % [residents, housing], "мест занято", residents > housing)
		metric(2, "%.1f мес." % runway, "запас еды", runway < 2)
		metric(3, str(home.wood), "древесина")
		warning = runway < 2 or residents > housing
		put(notice_label, "Заканчивается еда · запас меньше 2 месяцев" if runway < 2 else ("Не хватает жилья" if residents > housing else WorldEconomy.status(world, home)))
	elif kind == "person":
		visible_sections.append_array(["family", "skills", "relations"])
		put(title_label, "%s · %d лет" % [person.name, WorldLife.years(world, person)])
		put(subtitle_label, WorldLife.STAGES[WorldLife.stage(world, person)] + " · " + WorldEconomy.JOBS[person.job])
		metric(0, "%d%%" % person.health, "здоровье", person.health < 60)
		metric(1, "%d%%" % person.energy, "силы", person.energy < 25)
		metric(2, "%d%%" % person.hunger, "голод", person.hunger >= 40)
		metric(3, str(person.rations), "еды с собой")
		var activity := WorldEconomy.describe(person) if WorldLife.adult(world, person) else ("Под присмотром опекуна" if person.guardian != -1 else "Нуждается в опекуне")
		if not person.lesson.is_empty(): activity = "Учится: " + WorldSocial.SKILLS[person.lesson.skill]
		if person.task.get("kind", "") == "research": activity = "Исследует: " + WorldSociety.TECH[person.task.tech].name
		put(notice_label, activity)
		warning = person.health < 60 or person.hunger >= 40
	elif kind == "site":
		put(title_label,site.name)
		var period: Dictionary = site.periods.back()
		put(subtitle_label,("Опустело · " + world.heritage.date(period.end)) if period.end >= 0 else "Заселено вновь")
		metric(0,str(site.finds.size()),"находок")
		metric(1,str(site.visitors.size()),"общин")
		metric_nodes[2].card.hide()
		metric_nodes[3].card.hide()
		put(notice_label,str(site.periods.back().cause).replace("Последняя потеря жителя:","Последняя потеря:") if site.current == -1 else "Место заселено вновь")
	else:
		put(title_label, WorldState.TERRAIN_NAMES[world.terrain_at(cell)])
		put(subtitle_label, "Клетка · %d, %d" % [cell.x, cell.y])
		metric(0, str(world.food_at(cell)), "еда")
		metric(1, str(world.wood_at(cell)), "древесина")
		metric_nodes[2].card.hide()
		metric_nodes[3].card.hide()
		put(notice_label, WorldClimate.describe(world, cell))
	if not site.is_empty(): visible_sections.append("history")
	if not building.is_empty() and building.kind != "camp": visible_sections.append("building")
	if notice_warning != warning:
		notice_warning = warning
		notice.add_theme_stylebox_override("panel", notice_styles[int(warning)])
	for section_key in sections:
		sections[section_key].box.visible = visible_sections.has(section_key)
		if expanded(section_key): rows(section_key, details(section_key, world, cell, person, home, building))
	revision += 1

func details(key: String, world: WorldState, cell: Vector2i, person: Dictionary, home: Dictionary, building: Dictionary) -> Array:
	var result: Array = []
	match key:
		"history":
			var site := world.heritage.at(cell)
			if not site.is_empty(): result = world.heritage.details(site)
		"development":
			var society := WorldSociety.get_society(world, home.id)
			if society.is_empty(): return [["Община формируется", "Развитие начинается с повседневной практики."]]
			if not society.project.is_empty(): result.append(["Сейчас исследуют", WorldSociety.TECH[society.project].name + "\n" + society.project_reason])
			var profile := WorldDevelopment.profile(world, home)
			for domain in profile:
				var value: Dictionary = profile[domain]
				if value.known == 0 and value.practice == 0: continue
				result.append([WorldDevelopment.DOMAINS[domain], "%d освоено · %d в деле" % [value.mastered, value.operating] if value.known > 0 else "Накапливают практический опыт"])
			if result.is_empty(): result.append(["Первые шаги", "Жители приобретают опыт и обмениваются знаниями."])
		"technology":
			var society := WorldSociety.get_society(world, home.id)
			for tech in society.get("tech", {}):
				var state: Dictionary = society.tech[tech]
				if not state.known: continue
				var why := WorldSociety.reason(world, home, tech, state.mastered)
				var status := ""
				if state.mastered: status = ("Применяется" if state.used > 0 else "Готово к применению") if why.is_empty() else "Освоено · " + why
				elif not why.is_empty(): status = why
				elif WorldEconomy.food_days(world, home) < 6: status = "Нужен запас еды на 6 месяцев"
				else: status = "Опыты: %d шагов · попытка %d" % [state.work_done, state.attempts]
				result.append([WorldSociety.TECH[tech].name, status])
			if result.is_empty(): result.append(["Открытий пока нет", "Идеи появляются благодаря работе, обучению и встречам."])
		"economy":
			result.append(["Еда", "%d / %d · запас на %.1f мес." % [home.food, WorldEconomy.food_capacity(world, home), WorldEconomy.food_days(world, home)]])
			result.append(["Древесина", "%d / %d" % [home.wood, WorldEconomy.wood_capacity(world, home)]])
			var stock: Dictionary = world.civilization.get(home.id, {}).get("stock", {})
			for good in WorldCivilization.GOODS:
				result.append([WorldCivilization.GOODS[good], str(stock.get(good, 0))])
			for kind in WorldEconomy.NAMES:
				var ready := WorldEconomy.count(world, home, kind)
				var total := WorldEconomy.count(world, home, kind, false)
				if total > 0: result.append([WorldEconomy.NAMES[kind], str(ready) + (" · строится: %d" % (total - ready) if total > ready else "")])
		"population":
			var ages := [0, 0, 0]
			var jobs := {}
			var crafts := {}
			for skill in WorldSocial.SKILLS: crafts[skill] = [0, 0]
			for member in WorldEconomy.members(world, home):
				var age := WorldLife.years(world, member)
				ages[0 if age < 18 else (2 if age >= 60 else 1)] += 1
				jobs[member.job] = int(jobs.get(member.job, 0)) + 1
				for skill in crafts:
					if age >= 18 and WorldSocial.level(member, skill) >= 2: crafts[skill][0] += 1
					if age < 18 and member.skills[skill] > 0: crafts[skill][1] += 1
			result.append(["Возраст", "Дети: %d · взрослые: %d · пожилые: %d" % ages])
			for job in jobs: result.append([WorldEconomy.JOBS[job], str(jobs[job])])
			for skill in crafts: result.append([WorldSocial.SKILLS[skill], "Опытных: %d · учеников: %d" % crafts[skill]])
			var leader := int(world.civilization.get(home.id, {}).get("leader", -1))
			if leader != -1: result.append(["Старейшина", WorldLife.label(world, leader)])
		"civic":
			var state: Dictionary = world.networks.town_index.get(home.id,{})
			result.append([WorldNetworks.STAGES[int(state.get("stage",0))],"Жильё: %d мест · жителей: %d" % [WorldEconomy.housing(world,home),WorldEconomy.members(world,home).size()]])
			if not state.get("parent_name","").is_empty(): result.append(["Основано переселенцами",state.parent_name])
			if WorldEconomy.count(world,home,"power")>0: result.append(["Электроснабжение","Работает · расход 2 древесины в месяц" if world.networks.powered(world,home) else "Остановлено · нужны топливо и освоенное электричество"])
			for kind in ["bridge","irrigation","roadworks","plaza","embankment","mill","factory","power","townhouse","apartment","tower"]:
				var total := WorldEconomy.count(world,home,kind,false)
				if total==0: continue
				var ready := WorldEconomy.count(world,home,kind)
				var effects := {"bridge":"Пеший путь через воду","irrigation":"Поля растут при засухе","roadworks":"Меньше усталости в пути","plaza":"Место встреч жителей","embankment":"Защита судов у родного берега","mill":"Быстрее обработка урожая","factory":"Быстрее производство при электроснабжении","power":"Энергия для производства и высотной застройки","townhouse":"8 мест в каждом доме","apartment":"16 мест в каждом доме","tower":"32 места в каждом доме"}
				result.append([WorldEconomy.NAMES[kind],"Готово: %d · строится: %d\n%s" % [ready,total-ready,effects[kind]]])
		"network":
			var state: Dictionary = world.networks.town_index.get(home.id,{})
			var pressure: int = int(state.get("pressure",0))
			result.append(["Переселение","Ищут место с едой и жильём" if pressure>=24 else ("Нужны еда или свободное жильё" if pressure>=12 else "Община устроена на месте")])
			for journey in world.journeys:
				if journey.home!=home.id and journey.target!=home.id: continue
				var titles := {"trade":"Торговый караван","aid":"Помощь соседям","migrate":"Переселение семьи","colony":"Новая община"}
				var destination := WorldEconomy.town(world,journey.target)
				var cargo: String = {"food":"еда","wood":"древесина"}.get(journey.cargo_kind,WorldCivilization.GOODS.get(journey.cargo_kind,"без груза"))
				result.append([titles[journey.purpose],"%s · %d чел.\nГруз: %d · %s" % [destination.get("name","Новый очаг"),journey.crew.size(),journey.cargo,cargo]])
			for link in world.networks.neighbors.get(home.id,[]):
				var other := WorldEconomy.town(world,link.b if link.a==home.id else link.a)
				if other.is_empty(): continue
				var transport: String = "море" if link.mode=="sea" else "суша"
				result.append([other.name+" · "+world.networks.status(link,world.ticks),"Доверие: %d/100 · %s\nДоставок: %d · помощи: %d\n%s" % [link.trust,transport,link.deliveries,link.aid,link.reason]])
			if world.networks.neighbors.get(home.id,[]).is_empty(): result.append(["Соседи пока неизвестны","Связь появляется после настоящей встречи путешественников."])
		"sea":
			for ship in world.voyages:
				if ship.home != home.id: continue
				var phase: String = {"boarding": "Сбор экипажа", "outbound": "В пути", "returning": "Возвращение", "unload": "Разгрузка"}[ship.phase]
				result.append([WorldEconomy.NAMES[ship.kind] + " · " + phase, "Экипаж: %d · еда: %d · путь: %d%%" % [ship.crew.size(), ship.food, ship.progress * 100 / maxi(1, int(ship.duration))]])
			if result.is_empty(): result.append(["В море нет кораблей", ""])
			for contact in world.contacts:
				if home.id not in [contact.a, contact.b]: continue
				var target := WorldEconomy.town(world, contact.b if contact.a == home.id else contact.a)
				if not target.is_empty(): result.append([target.name, "Встреч: %d" % contact.visits])
		"family":
			result = text_rows(WorldLife.family_description(world, person))
		"skills":
			result = text_rows(WorldVocation.describe(person))
			var levels := ["Новичок", "Практик", "Опытный", "Мастер"]
			for skill in WorldSocial.SKILLS:
				var description: String = "%s · %d" % [levels[WorldSocial.level(person, skill)], person.skills[skill]]
				if person.trained_by.has(skill): description += "\nУчитель: " + WorldLife.label(world, person.trained_by[skill])
				result.append([WorldSocial.SKILLS[skill], description])
			var traits: Array[String] = []
			if person.traits.sociability == 2: traits.append("Общительный")
			if person.traits.sociability == 0: traits.append("Сдержанный")
			if person.traits.diligence == 2: traits.append("Усердный")
			if person.traits.curiosity == 2: traits.append("Любознательный")
			if not traits.is_empty(): result.append(["Характер", " · ".join(traits)])
		"relations":
			for link in person.links:
				if link.bond >= WorldSocial.FRIEND: result.append(["Друг", WorldLife.label(world, link.id)])
			if result.is_empty(): result.append(["Друзья", "Знакомится с соседями"])
			for rival in person.rivals: result.append(["Разлад", "%s · %d/100" % [WorldLife.label(world, rival.id), rival.resentment]])
			if not person.lesson.is_empty(): result.append(["Наставник", WorldLife.label(world, person.lesson.mentor)])
			if person.task.get("kind", "") == "teach": result.append(["Ученик", WorldLife.label(world, person.task.dependent)])
		"building":
			result.append([WorldEconomy.NAMES[building.kind], "Готово" if building.ready else "Материалы: %d/%d · работа: %d/%d" % [building.delivered, WorldEconomy.COST[building.kind], building.work, WorldEconomy.WORK[building.kind]]])
			if building.kind == "farm" and building.ready:
				var grow_steps := 50 if WorldSociety.active(world, WorldEconomy.town(world, building.town), "rotation") else 60
				result.append(["Поле", "Урожай: %d" % building.stock if building.stock > 0 else ("Рост: %d%%" % (building.growth * 100 / grow_steps) if building.planted else "Ждёт посева")])
		"terrain":
			result.append(["Координаты", "%d, %d" % [cell.x, cell.y]])
			result.append([WorldState.TERRAIN_NAMES[world.terrain_at(cell)], "Еда: %d · древесина: %d" % [world.food_at(cell), world.wood_at(cell)]])
			result.append(["Природа", WorldClimate.describe(world, cell)])
	return result

func text_rows(value: String) -> Array:
	var result: Array = []
	for line in value.strip_edges().split("\n", false):
		var parts := line.split(": ", true, 1)
		result.append([parts[0], parts[1] if parts.size() > 1 else ""])
	return result

func readable_text() -> String:
	var parts: Array[String] = [title_label.text, subtitle_label.text]
	for item in metric_nodes:
		if item.card.visible: parts.append(item.value.text + " " + item.caption.text)
	if notice.visible: parts.append(notice_label.text)
	for section in sections.values():
		if not section.box.visible: continue
		parts.append(section.title)
		if section.body.visible:
			for item in section.rows:
				if item.panel.visible: parts.append(item.heading.text + ": " + item.value.text)
	return "\n".join(parts)
