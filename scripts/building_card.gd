class_name BuildingCard
extends VBoxContainer

signal settlement_requested(id: int)

const EFFECTS := {
	"house":["Жильё на 4 места","Дополнительные места для жителей общины."],
	"townhouse":["Жильё на 8 мест","Каменная застройка увеличивает вместимость поселения."],
	"apartment":["Жильё на 16 мест","Плотная городская застройка для растущего населения."],
	"tower":["Жильё на 32 места","Высотная застройка позволяет разместить больше жителей на небольшом участке."],
	"archive":["Хранение знаний","Позволяет применять хранение записей. Идеи и методы принадлежат всей общине; готовые технологии здание не выдаёт."],
	"store":["Больше места для запасов","Готовый склад добавляет общине 120 мест для еды и 80 для древесины."],
	"farm":["Выращивание пищи","Посев, рост и сбор урожая требуют работы жителей. Погода и освоенные методы влияют на урожай."],
	"workshop":["Ремесло и опыты","Рабочее место для освоения методов. Нужны подходящие специалисты и материалы."],
	"school":["Обучение жителей","Место для освоения методов обучения. Передача навыков требует настоящего наставника и ученика."],
	"pasture":["Место для стада","Загоны позволяют содержать до 12 животных в группе. Корм берётся с местности; сам загон его не создаёт."],
	"kiln":["Изготовление керамики","Мастер перерабатывает материалы на складе. Нужны освоенная керамика и доступные запасы."],
	"loom":["Изготовление ткани","При наличии шерсти ткацкая использует её. Иначе сохраняется изготовление ткани из растительного сырья."],
	"forge":["Выплавка и инструменты","Из руды получают металл, из металла — инструменты. Работа требует металлургии и материалов."],
	"power":["Энергия для города","Работает при освоенном электричестве; расходует 2 древесины в месяц. Энергия поддерживает производство и высотную застройку."],
	"factory":["Промышленное производство","Электроснабжение ускоряет производство. Технологии, специалисты и сырьё остаются необходимыми."],
	"mill":["Обработка урожая","Ускоряет обработку урожая при работающем хозяйстве."],
	"bridge":["Путь через воду","Соединяет доступные берега для пеших путешественников."],
	"irrigation":["Вода для полей","Поддерживает рост полей при засухе."],
	"roadworks":["Обустройство дорог","Дороги снижают усталость жителей в пути."],
	"plaza":["Место встреч","Общественное пространство поселения."],
	"embankment":["Защита берега","Защищает суда у родного берега."],
	"market":["Обмен и торговля","Место для освоения торговли. Доставки выполняют настоящие караваны и корабли."],
	"council":["Общие дела поселения","Место для развития управления общиной."],
	"dock":["Выход к воде","Место для прибрежной навигации и подготовки морских путешествий."],
	"port":["Морские путешествия","Поддерживает мореплавание. Экспедиции требуют экипажа, запасов и подходящего маршрута."],
	"boat":["Прибрежное плавание","Перевозит настоящих жителей и запасы."],
	"sailboat":["Дальние плавания","Путешествия, встречи с другими общинами и морские колонии." ]
}
var state_icon: TextureRect
var state_label: Label
var effect_label: Label
var help_button: Button
var explanation: Label
var materials: HFlowContainer
var work_label: Label
var work_bar: ProgressBar
var output: VBoxContainer
var benefits: HFlowContainer
var settlement: Button
var owner_id := -1
var current_id := -1
var help_text := ""
var touch_ui := false
var target_size := 48.0

static func category(kind: String) -> String:
	if kind in ["house","townhouse","apartment","tower"]: return "ЖИЛЬЁ"
	if kind in ["archive","school","workshop"]: return "ЗНАНИЯ И РЕМЁСЛА"
	if kind in ["farm","store","pasture","mill"]: return "ХОЗЯЙСТВО"
	if kind in ["kiln","loom","forge","factory","power"]: return "ПРОИЗВОДСТВО"
	if kind in ["dock","port","boat","sailboat"]: return "МОРЕПЛАВАНИЕ"
	return "ПОСЕЛЕНИЕ"

func text_label(text: String, size_value: int = 14) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size",maxi(16,size_value) if touch_ui else size_value)
	node.add_theme_color_override("font_color",AtlasTheme.INK)
	return node

func setup(mobile: bool, target: float) -> void:
	touch_ui = mobile; target_size = target
	add_theme_constant_override("separation",10)
	var state := HBoxContainer.new()
	add_child(state)
	state_icon = InterfaceArt.rect("check",20); state.add_child(state_icon)
	state_label = text_label(""); state.add_child(state_label)
	help_button = Button.new(); help_button.text = "?"; help_button.tooltip_text = "Назначение здания"
	help_button.custom_minimum_size = Vector2.ONE * (target if mobile else 36)
	help_button.pressed.connect(_help)
	state.add_child(help_button)
	effect_label = text_label("",16); add_child(effect_label)
	explanation = text_label(""); explanation.hide(); add_child(explanation)
	materials = HFlowContainer.new(); materials.add_theme_constant_override("h_separation",6); add_child(materials)
	work_label = text_label(""); add_child(work_label)
	work_bar = ProgressBar.new(); work_bar.show_percentage = false; work_bar.custom_minimum_size.y = 8
	work_bar.add_theme_stylebox_override("background",AtlasTheme.frame(Color("d6ccb8"),Color.TRANSPARENT))
	work_bar.add_theme_stylebox_override("fill",AtlasTheme.frame(AtlasTheme.BLUE,Color.TRANSPARENT))
	add_child(work_bar)
	benefits = HFlowContainer.new(); benefits.add_theme_constant_override("h_separation",6); add_child(benefits)
	output = VBoxContainer.new(); output.add_theme_constant_override("separation",6); add_child(output)
	settlement = Button.new(); settlement.alignment = HORIZONTAL_ALIGNMENT_LEFT
	settlement.icon = InterfaceArt.icon("building:camp"); settlement.add_theme_constant_override("icon_max_width",20)
	settlement.custom_minimum_size.y = target if mobile else 40
	settlement.pressed.connect(func(): settlement_requested.emit(owner_id)); add_child(settlement)

func tokens(parent: HFlowContainer, values: Array) -> void:
	while parent.get_child_count() < values.size():
		var button := Button.new(); button.theme_type_variation = "AtlasToken"
		button.custom_minimum_size = Vector2(60,target_size if touch_ui else 36)
		button.add_theme_constant_override("icon_max_width",20)
		button.pressed.connect(func(): explanation.text = str(button.get_meta("meaning")); explanation.show())
		parent.add_child(button)
	for i in parent.get_child_count():
		var button: Button = parent.get_child(i)
		button.visible = i < values.size()
		if i>=values.size(): continue
		var value: Array = values[i]
		button.custom_minimum_size.y = target_size if touch_ui else 36
		button.icon = InterfaceArt.icon(value[0]); button.text = str(value[1])
		button.tooltip_text = value[2]; button.set_meta("meaning",value[2])

func present(world: WorldState, building: Dictionary, home: Dictionary) -> void:
	if current_id != int(building.id):
		current_id = building.id; explanation.hide()
	owner_id = int(home.get("id",-1))
	settlement.visible = owner_id != -1
	settlement.text = str(home.get("name","Поселение")) + "  →"
	var effect: Array = EFFECTS.get(building.kind,[WorldEconomy.NAMES[building.kind],"Постройка поселения."])
	help_text = effect[1]; help_button.tooltip_text = help_text
	effect_label.text = effect[0]
	if explanation.visible and explanation.text.is_empty(): explanation.text = help_text
	if explanation.text == "" or not explanation.visible: explanation.text = help_text
	var ready: bool = building.ready
	state_label.text = "Готово" if ready else "Строится"
	state_label.add_theme_color_override("font_color",AtlasTheme.GOOD if ready else AtlasTheme.COPPER)
	state_icon.texture = InterfaceArt.icon("check" if ready else "work")
	materials.visible = not ready; work_label.visible = not ready; work_bar.visible = not ready
	benefits.visible = ready; output.visible = ready
	if not ready:
		var supplies: Array = [["wood","%d/%d" % [building.delivered,WorldEconomy.COST[building.kind]],"Древесина доставлена / требуется"]]
		for good in WorldCivilization.EXTRA.get(building.kind,{}):
			supplies.append([good,"%d/%d" % [int(building.get("materials",{}).get(good,0)),int(WorldCivilization.EXTRA[building.kind][good])],InterfaceArt.resource_name(good)+": доставлено / требуется"])
		tokens(materials,supplies)
		work_label.text = "Работа  %d / %d" % [building.work,WorldEconomy.WORK[building.kind]]
		work_bar.max_value = WorldEconomy.WORK[building.kind]; work_bar.value = building.work
		tokens(benefits,[])
		for child in output.get_children(): child.hide()
		return
	var values: Array = []
	match str(building.kind):
		"house","townhouse","apartment","tower":
			values.append(["person",str({"house":4,"townhouse":8,"apartment":16,"tower":32}[building.kind])+" мест","Вместимость этого дома. Места учитываются в общем жилье поселения."])
		"store":
			values = [["food","+120","Дополнительная вместимость склада для еды"],["wood","+80","Дополнительная вместимость склада для древесины"]]
		"archive":
			var known := 0; var mastered := 0
			for tech in WorldSociety.get_society(world,home.get("id",-1)).get("tech",{}).values():
				known += int(tech.known); mastered += int(tech.mastered)
			values = [["book",str(known)+" идей","Все известные идеи общины"],["check",str(mastered)+" освоено","Методы, освоенные общиной. Применение зависит от специалистов и материалов."]]
		"farm":
			var grow_steps := 50 if not home.is_empty() and WorldSociety.active(world,home,"rotation") else 60
			values = [["food",str(building.stock),"Урожай на этом поле"]]
			state_label.text = "Урожай готов" if building.stock>0 else ("Растёт" if building.planted else "Ждёт посева")
			work_label.visible = building.planted; work_bar.visible = building.planted
			work_label.text = "Рост  %d%%" % clampi(building.growth*100/grow_steps,0,100)
			work_bar.max_value = grow_steps; work_bar.value = building.growth
		"pasture":
			values = [["wool","до 12","Вместимость группы животных возле загона. Для роста стада нужен корм на местности."]]
		"power":
			values = [["wood","2 / мес.","Расход древесины работающей электростанцией"]]
			var powered := not home.is_empty() and world.networks.powered(world,home)
			state_label.text = "Есть питание" if powered else "Нет питания"
			state_icon.texture = InterfaceArt.icon("energy" if powered else "warning")
			state_label.add_theme_color_override("font_color",AtlasTheme.GOOD if powered else Color("91462f"))
	tokens(benefits,values)
	var recipes: Array = []
	for good in WorldCivilization.RECIPES:
		var recipe: Dictionary = WorldCivilization.RECIPES[good]
		if recipe.building != building.kind: continue
		var inputs: Dictionary = {"wool":1} if good=="cloth" and int(world.civilization.get(home.get("id",-1),{}).get("stock",{}).get("wool",0))>0 else recipe.inputs
		var line: Array = []
		for material in inputs: line.append([material,str(inputs[material]),InterfaceArt.resource_name(material)+": расход на партию"])
		line.append(["arrow","","Материалы превращаются в готовую продукцию после работы мастера"])
		line.append([good,str(recipe.yield),InterfaceArt.resource_name(good)+": выпуск за партию"])
		recipes.append(line)
	while output.get_child_count()<recipes.size():
		output.add_child(HFlowContainer.new())
	for i in output.get_child_count():
		output.get_child(i).visible = i<recipes.size()
		if i<recipes.size(): tokens(output.get_child(i),recipes[i])

func _help() -> void:
	var opened := not explanation.visible or explanation.text != help_text
	explanation.text = help_text
	explanation.visible = opened

func readable_text() -> String:
	var parts: Array[String] = [state_label.text,effect_label.text]
	if explanation.visible: parts.append(explanation.text)
	for flow in [materials,benefits]:
		if not flow.visible: continue
		for item in flow.get_children():
			if item.visible: parts.append(item.tooltip_text+": "+item.text)
	if work_label.visible: parts.append(work_label.text)
	return "\n".join(parts)
