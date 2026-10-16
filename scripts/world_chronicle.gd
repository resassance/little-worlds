class_name WorldChronicle
extends VBoxContainer

const CATEGORIES := ["Все записи","Знания","Жизнь общин","Природа"]
const SYMBOLS := ["history","book","building:camp","leaf"]
var header: HBoxContainer
var people_label: Label
var towns_label: Label
var expanded_records: Dictionary = {}
var summary_label: Label
var entries: VBoxContainer
var filter: OptionButton
var empty_label: Label
var records: Array[Dictionary] = []
var events: Array = []
var signature := ""
var updates := 0
var touch_ui := false
var target_size := 48.0

func setup(mobile: bool, target: float) -> void:
	touch_ui = mobile; target_size = target
	add_theme_constant_override("separation",10)
	header = HBoxContainer.new(); add_child(header)
	header.add_child(InterfaceArt.rect("history",32))
	var title := make_label("Летопись мира",20,true); header.add_child(title)
	var summary := HBoxContainer.new(); add_child(summary)
	summary.add_child(InterfaceArt.rect("person",18))
	people_label = make_label("",14); people_label.autowrap_mode = TextServer.AUTOWRAP_OFF; people_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; summary.add_child(people_label)
	summary.add_child(InterfaceArt.rect("building:camp",18))
	towns_label = make_label("",14); towns_label.autowrap_mode = TextServer.AUTOWRAP_OFF; towns_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; summary.add_child(towns_label)
	summary_label = make_label("",13); summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; summary.add_child(summary_label)
	filter = OptionButton.new(); filter.custom_minimum_size.y = target if mobile else 40
	for i in CATEGORIES.size(): filter.add_icon_item(InterfaceArt.icon(SYMBOLS[i]),CATEGORIES[i],i)
	filter.add_theme_constant_override("icon_max_width",20)
	filter.item_selected.connect(func(_index: int): rebuild())
	add_child(filter)
	empty_label = make_label("Здесь пока нет событий",14); add_child(empty_label)
	entries = VBoxContainer.new(); entries.add_theme_constant_override("separation",8); add_child(entries)

func make_label(text: String, size_value: int, bold: bool = false) -> Label:
	var node := Label.new(); node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size",maxi(16,size_value) if touch_ui else size_value)
	node.add_theme_color_override("font_color",AtlasTheme.INK)
	if bold: node.add_theme_font_override("font",WorldInspector.BOLD)
	return node

func category(event: Dictionary) -> int:
	var title: String = event.title.to_lower()
	for word in ["технолог","идея","знание","запис","мастер","ремесл","ученик","опыт"]:
		if title.contains(word): return 1
	for word in ["молни","дожд","гроз","пожар","погод","засух","буря","шторм","мороз","жар","землетряс","смерч","павод","вулкан","природ","стад","суша","рождение мира"]:
		if title.contains(word): return 3
	return 2

func event_icon(event: Dictionary) -> String:
	var title: String = event.title.to_lower()
	for pair in [["дожд","rain"],["молни","fire"],["гроз","fire"],["пожар","fire"],["семья","heart"],["дружба","heart"],["ребён","person"],["жител","person"],["стад","wool"],["традиц","flag"],["караван","trade"],["поставк","trade"],["контакт","trade"],["экспедиц","building:sailboat"],["море","building:sailboat"],["потер","warning"],["утра","warning"]]:
		if title.contains(pair[0]): return pair[1]
	return SYMBOLS[category(event)]

func update_summary(world: WorldState) -> void:
	people_label.text = str(world.people.size()); people_label.tooltip_text = "Жителей"
	towns_label.text = str(world.towns.size()); towns_label.tooltip_text = "Поселений"
	summary_label.text = "%d пожаров" % world.fires.size() if not world.fires.is_empty() else ("Засуха" if world.ticks<world.drought_until else "Спокойно")

func reset() -> void:
	signature = ""
	expanded_records.clear()
	events = []

func present(world: WorldState) -> void:
	var next := str(world.history_revision)
	if next == signature: return
	signature = next
	events = world.history
	var retained := {}
	for event in events:
		var key := event_key(event)
		if expanded_records.has(key): retained[key] = expanded_records[key]
	expanded_records = retained
	rebuild()

func append_record() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",AtlasTheme.frame(AtlasTheme.SOFT,AtlasTheme.EDGE))
	entries.add_child(panel)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation",4); panel.add_child(body)
	var date := make_label("",12); date.add_theme_color_override("font_color",AtlasTheme.MUTED); body.add_child(date)
	var button := Button.new(); button.flat = true; button.theme_type_variation = "AtlasToken"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.toggle_mode = true
	button.custom_minimum_size.y = target_size if touch_ui else 40
	button.add_theme_constant_override("icon_max_width",18)
	body.add_child(button)
	var title := make_label("",15,true); title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(title); title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.offset_left = 38; title.offset_right = -24; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var mark := make_label("+",15); mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(mark); mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	mark.offset_left = -20; mark.offset_right = -4; mark.offset_top = -12; mark.offset_bottom = 12
	var message := make_label("",14); message.hide(); body.add_child(message)
	var record := {"panel":panel,"date":date,"button":button,"title":title,"mark":mark,"message":message,"key":""}
	button.toggled.connect(func(opened: bool):
		message.visible = opened; mark.text = "−" if opened else "+"
		if opened: expanded_records[record.key] = true
		else: expanded_records.erase(record.key))
	button.resized.connect(func(): fit_record(button,title))
	records.append(record)

func fit_record(button: Button, title: Label) -> void:
	var height := title.get_theme_font("font").get_multiline_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,maxf(60,button.size.x-62),title.get_theme_font_size("font_size")).y+16
	button.custom_minimum_size.y = maxf(target_size if touch_ui else 40,height)

func event_key(event: Dictionary) -> String:
	return str(event.tick)+":"+event.title+":"+event.message

func rebuild() -> void:
	var shown := 0
	var previous_date := ""
	for event in events:
		var kind := category(event)
		if filter.selected != 0 and kind != filter.selected: continue
		if shown>=20: break
		if shown>=records.size(): append_record()
		var row: Dictionary = records[shown]
		var key := event_key(event)
		row.key = key
		var opened: bool = expanded_records.get(key,false)
		row.button.set_pressed_no_signal(opened); row.message.visible = opened; row.mark.text = "−" if opened else "+"
		row.panel.show()
		row.date.text = "Год %d · месяц %d" % [int(event.tick)/WorldLife.YEAR+1,(int(event.tick)/WorldEconomy.DAY_TICKS)%WorldEconomy.DAYS_PER_YEAR+1]
		row.date.visible = row.date.text != previous_date
		previous_date = row.date.text
		row.title.text = event.title; row.message.text = event.message
		row.button.icon = InterfaceArt.icon(event_icon(event))
		row.button.tooltip_text = event.title+" · раскрыть запись"
		fit_record(row.button,row.title)
		shown += 1
	for i in range(shown,records.size()): records[i].panel.hide()
	empty_label.visible = shown==0
	updates += 1
