extends Control

const FONT := preload("res://assets/fonts/DejaVuSans.ttf")
const BOLD := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const ACCENT := AtlasTheme.COPPER
const MUTED := AtlasTheme.MUTED
var world: WorldState
var view: WorldView
var accumulator := 0.0
var speed := 1
var paused := false
var day_label: Label
var pause_button: Button
var speed_button: Button
var world_menu: MenuButton
var tools_button: Button
var info_button: Button
var hud: Control
var reveal_button: Button
var tool_panel: PanelContainer
var sidebar: PanelContainer
var toolbar: VBoxContainer
var tool_title: Label
var tool_description: Label
var tool_group_picker: OptionButton
var land_group: GridContainer
var life_tool: Button
var power_group: HBoxContainer
var tool_buttons: Dictionary = {}
var brush_label: Label
var brush_slider: HSlider
var brush_row: VBoxContainer
var stats_label: Label
var inspector: WorldInspector
var world_info: VBoxContainer
var object_tab: Button
var world_tab: Button
var info_world := false
var info_scroll_positions := [0, 0]
var history_box: VBoxContainer
var history_scroll: ScrollContainer
var status_label: Label
var status_panel: PanelContainer
var toast_tween: Tween
var top_time: HBoxContainer
var bottom_controls: HBoxContainer
var tool_tween: Tween
var info_tween: Tween
var tools_open := false
var info_open := false
var hud_hidden := false
var hidden_tool := "inspect"
var inspected_person_id := -1
var selected_cell := WorldState.NO_CELL
var history_signature := ""
var weather_sequence := 0
var autosave_timer := 0.0
var message_time := 0.0
var generation_dialog: ConfirmationDialog
var settings_dialog: AcceptDialog
var seed_input: LineEdit
var navigation_dialog: ConfirmationDialog
var coordinate_x: SpinBox
var coordinate_y: SpinBox
var destination_picker: OptionButton
var modal_scrim: ColorRect
var preferences := GamePreferences.new()
var sound: GameAudio
var platform: GamePlatform
var suspended := false
var platform_suspended := false
var app_suspended := false
var biome_group: GridContainer
var climate_dialog: AcceptDialog
var climate_mode: OptionButton
var climate_biome: OptionButton
var climate_scale: SpinBox
var climate_equator: SpinBox
var climate_seasons: CheckButton
var climate_weather: OptionButton
var help_dialog: AcceptDialog
var sculpt_dialog: ConfirmationDialog
var sculpt_width: SpinBox
var sculpt_height: SpinBox
var sculpt: WorldSculpt
var sculpt_stop: Button
var touch_ui := false
var ui_scale := 1.0
var system_ui_scale := 1.0
var ui_scale_picker: OptionButton
var safe_rect := Rect2()
var step_job: WorldStepJob
var pending_actions: Array[Callable] = []
var pending_inspection := WorldState.NO_CELL
var pending_inspection_cycles := 0
var inspector_dirty := true
var inspector_timer := 0.0
var inspector_updates := 0
var save_job: WorldSaveJob
var save_automatic := false
var climate_update_job: WorldClimateConfigureJob
var input_popups: Array[PopupMenu] = []

func _ready() -> void:
	WorldRegions.deferred_cleanup = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_window().content_scale_size = Vector2i.ZERO
	preferences.load_preferences()
	_configure_display()
	sound=GameAudio.new(); add_child(sound); sound.setup(preferences)
	_build_theme()
	_build_ui()
	_watch_input_popups(self)
	if touch_ui: _prepare_touch_ui(self)
	var initial := SaveStore.load_world()
	if initial == null:
		initial = WorldState.new()
		initial.generate(42817)
		initial.populate_demo()
	_set_world(initial)
	_select_tool("inspect")
	resized.connect(_responsive)
	_responsive()
	view.reduce_motion=preferences.reduce_motion
	view.show_minimap=preferences.minimap
	platform=GamePlatform.new()
	platform.suspension_changed.connect(func(value: bool): platform_suspended=value; _update_suspension())
	platform.message.connect(show_message)
	platform.cloud_loaded.connect(func(value: WorldState): _at_boundary(func(): _set_world(value); show_message("Мир загружен из облака.")))
	platform.reward_received.connect(func(): _at_boundary(func(): world.rain(view.local_to_cell(view.size*0.5),8); show_message("Дождь за просмотр видео: огонь погас, земля восстановилась.")))
	add_child(platform)
	platform.gameplay(true)
	if not preferences.tutorial_done: show_message("Создавайте землю, поселите жителей и наблюдайте за поколениями. Подсказки: Мир → Как играть.")
	get_tree().auto_accept_quit = false

func _configure_display() -> void:
	touch_ui = OS.has_feature("android") or OS.has_feature("ios")
	if OS.has_feature("web"):
		touch_ui = bool(JavaScriptBridge.eval("matchMedia('(pointer: coarse)').matches"))
	system_ui_scale = 1.0
	if OS.has_feature("android"):
		system_ui_scale = _android_density()
	elif OS.has_feature("ios"):
		system_ui_scale = maxf(1.0, DisplayServer.screen_get_scale())
	elif OS.has_feature("web"):
		system_ui_scale = float(JavaScriptBridge.eval("document.querySelector('canvas').width / Math.max(1, document.querySelector('canvas').getBoundingClientRect().width)"))
	for argument in OS.get_cmdline_user_args():
		if argument == "--touch-ui": touch_ui = true
		if argument.begins_with("--ui-scale="):
			system_ui_scale = argument.trim_prefix("--ui-scale=").to_float()
	_apply_ui_scale()

func _android_density() -> float:
	if Engine.has_singleton("AndroidRuntime"):
		var runtime := Engine.get_singleton("AndroidRuntime")
		var activity: Object = runtime.call("getActivity")
		if activity != null:
			var resources: Object = activity.call("getResources")
			if resources != null:
				var metrics: Object = resources.call("getDisplayMetrics")
				if metrics != null:
					var density: Variant = metrics.get("density")
					if (density is float or density is int) and is_finite(float(density)) and float(density) > 0:
						return float(density)
	return maxf(1.0, float(mini(get_window().size.x,get_window().size.y)) / 480.0)

func _touch_target() -> float:
	return 48.0 * maxf(1.0,system_ui_scale / ui_scale)

func _apply_ui_scale() -> void:
	ui_scale = clampf(system_ui_scale * preferences.ui_scale, 1.0, 4.0)
	ui_scale = minf(ui_scale, maxf(1.0, float(mini(get_window().size.x,get_window().size.y)) / 320.0))
	get_window().content_scale_factor = ui_scale

func _set_ui_scale(index: int) -> void:
	preferences.ui_scale = [0.85,1.0,1.15,1.3][index]
	preferences.save_preferences()
	_apply_ui_scale()
	_build_theme()
	if touch_ui: _prepare_touch_ui(self)
	call_deferred("_responsive")
	if settings_dialog.visible:
		settings_dialog.hide()
		call_deferred("_popup_dialog",settings_dialog,Vector2i(400,380))

func _prepare_touch_ui(node: Node) -> void:
	if node is Label:
		node.add_theme_font_size_override("font_size", maxi(16, node.get_theme_font_size("font_size")))
	elif node is BaseButton:
		if not node.has_meta("touch_minimum"): node.set_meta("touch_minimum",node.custom_minimum_size)
		node.custom_minimum_size = Vector2(node.get_meta("touch_minimum")).max(Vector2.ONE * _touch_target())
		node.add_theme_font_size_override("font_size", 16)
		if node is Button: node.add_theme_constant_override("icon_max_width", 22)
	elif node is LineEdit or node is Range:
		node.custom_minimum_size.y = maxf(_touch_target(), node.custom_minimum_size.y)
		if node is LineEdit: node.add_theme_font_size_override("font_size", 16)
	if node is ScrollContainer: node.scroll_deadzone = 12
	if node is PopupMenu:
		node.add_theme_font_size_override("font_size", 16)
		node.add_theme_constant_override("v_separation", 28)
	for child in node.get_children(true): _prepare_touch_ui(child)

func _watch_input_popups(node: Node) -> void:
	if node is PopupMenu and not input_popups.has(node):
		input_popups.append(node)
		node.about_to_popup.connect(view.cancel_input)
	for child in node.get_children(true): _watch_input_popups(child)

func _input_popup_open() -> bool:
	for popup in input_popups:
		if is_instance_valid(popup) and popup.visible: return true
	return false

func _screen_rect() -> Rect2:
	var area := Rect2(Vector2.ZERO, size)
	if OS.has_feature("android") or OS.has_feature("ios"):
		var physical := DisplayServer.get_display_safe_area()
		if physical.has_area():
			area = area.intersection(Rect2(Vector2(physical.position) / ui_scale, Vector2(physical.size) / ui_scale))
	return area.grow(-12.0 if touch_ui else -16.0)

func _at_boundary(action: Callable) -> void:
	if world.stepping or view.has_pending_edits() or save_job != null or climate_update_job != null: pending_actions.append(action)
	else: action.call()

func _style(color: Color, border: Color = Color.TRANSPARENT, radius: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.set_corner_radius_all(mini(radius, 2))
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

func _build_theme() -> void:
	var ui := Theme.new()
	ui.default_font = FONT
	ui.default_font_size = 16 if touch_ui else 13
	if touch_ui:
		ui.set_constant("buttons_min_height", "AcceptDialog", ceili(_touch_target()))
		ui.set_constant("buttons_min_width", "AcceptDialog", 120)
	ui.set_color("font_color", "Label", AtlasTheme.INK)
	ui.set_color("font_color", "Button", AtlasTheme.INK)
	ui.set_color("font_pressed_color", "Button", Color("fff0cf"))
	ui.set_color("font_hover_color", "Button", AtlasTheme.INK)
	ui.set_color("icon_pressed_color", "Button", Color("75472f"))
	ui.set_stylebox("normal", "Button", AtlasTheme.frame(AtlasTheme.PAPER, Color("8d7759")))
	ui.set_stylebox("hover", "Button", AtlasTheme.frame(Color("f0e3c7"), AtlasTheme.COPPER))
	ui.set_stylebox("pressed", "Button", AtlasTheme.frame(ACCENT, Color("b99b65")))
	ui.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, AtlasTheme.COPPER, 6))
	var panel := AtlasTheme.frame(AtlasTheme.PAPER, Color("827052"))
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	ui.set_stylebox("panel", "PanelContainer", panel)
	ui.set_stylebox("normal", "LineEdit", _style(Color("f1e5c8"), Color("ad9571")))
	ui.set_stylebox("focus", "LineEdit", _style(Color("f1e5c8"), ACCENT))
	ui.set_color("font_color", "LineEdit", AtlasTheme.INK)
	ui.set_stylebox("panel", "PopupMenu", AtlasTheme.frame(AtlasTheme.PAPER, Color("8d7759")))
	ui.set_stylebox("hover", "PopupMenu", _style(Color("cbb996")))
	ui.set_color("font_color", "PopupMenu", AtlasTheme.INK)
	ui.set_stylebox("panel", "TooltipPanel", _style(Color("cab792"), AtlasTheme.COPPER))
	ui.set_color("font_color", "TooltipLabel", AtlasTheme.INK)
	ui.set_stylebox("panel", "AcceptDialog", _style(AtlasTheme.PAPER, AtlasTheme.COPPER, 8))
	var window_border := _style(AtlasTheme.PAPER, AtlasTheme.COPPER, 8)
	window_border.border_width_top = 30
	ui.set_stylebox("embedded_border", "Window", window_border)
	ui.set_color("title_color", "Window", AtlasTheme.INK)
	ui.set_font("title_font", "Window", BOLD)
	ui.set_font_size("title_font_size", "Window", 14)
	var separator := StyleBoxLine.new()
	separator.color = Color("9f8c69")
	separator.thickness = 1
	ui.set_stylebox("separator", "HSeparator", separator)
	var scroll := _style(Color("9f8c69"), Color.TRANSPARENT, 3)
	ui.set_stylebox("grabber", "VScrollBar", scroll)
	ui.set_stylebox("grabber_highlight", "VScrollBar", _style(Color("866a57"), Color.TRANSPARENT, 3))
	ui.set_stylebox("grabber_pressed", "VScrollBar", _style(ACCENT, Color.TRANSPARENT, 3))
	ui.set_stylebox("scroll", "VScrollBar", _style(Color("cab792"), Color.TRANSPARENT, 3))
	var slider := _style(Color("ae9973"), Color.TRANSPARENT, 3)
	slider.content_margin_top = 2
	slider.content_margin_bottom = 2
	ui.set_stylebox("slider", "HSlider", slider)
	ui.set_stylebox("grabber_area", "HSlider", _style(AtlasTheme.COPPER, Color.TRANSPARENT, 3))
	ui.set_icon("grabber", "HSlider", PixelArt.sprite_texture([".cccc.", "cccccc", "cccccc", "cccccc", ".cccc."], {"c": Color("a98a57")}))
	ui.set_icon("grabber_highlight", "HSlider", PixelArt.sprite_texture([".wwww.", "wwwwww", "wwwwww", "wwwwww", ".wwww."]))
	ui.set_constant("separation", "VBoxContainer", 8)
	ui.set_constant("separation", "HBoxContainer", 8)
	theme = ui

func _label(text_value: String, font_size: int = 14, color: Color = AtlasTheme.INK) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", maxi(16, font_size) if touch_ui else font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text_value: String, callback: Callable, minimum: Vector2 = Vector2(0, 42)) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = minimum.max(Vector2.ONE * _touch_target()) if touch_ui else minimum
	button.pressed.connect(callback)
	button.pressed.connect(func(): sound.click())
	button.focus_mode = Control.FOCUS_NONE
	return button

func _icon_rect(key: String, pixels: int = 24) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = PixelArt.icon(key)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(pixels, pixels)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _tool_button(key: String, caption: String, description: String, grid: bool = true) -> Button:
	var button := _button("", _select_tool.bind(key), Vector2(66, 60) if grid else Vector2(0, 42))
	button.toggle_mode = true
	button.tooltip_text = description
	button.set_meta("caption", caption)
	button.set_meta("description", description)
	var content: BoxContainer = VBoxContainer.new() if grid else HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 4)
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 4
	content.offset_right = -4
	content.offset_top = 5
	content.offset_bottom = -5
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(_icon_rect(key, 23))
	var label := _label(caption, 11 if grid else 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)
	button.set_meta("caption_label", label)
	tool_buttons[key] = button
	return button

func _build_ui() -> void:

	view = WorldView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.cell_selected.connect(_request_inspection)
	view.feedback.connect(show_message)
	add_child(view)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	world_menu = MenuButton.new()
	world_menu.text = "Мир  ▾"
	world_menu.icon = PixelArt.icon("atlas")
	world_menu.add_theme_constant_override("icon_max_width", 18)
	world_menu.flat = false
	world_menu.position = Vector2(16, 16)
	world_menu.custom_minimum_size = Vector2(90, 44)
	hud.add_child(world_menu)
	var popup := world_menu.get_popup()
	for item in [["Новый остров", 0], ["Сохранить", 1], ["Загрузить", 2], ["Настройки", 3], ["Координаты и поселения", 4], ["Климат мира", 5], ["Как играть", 6], ["Создать материк", 10]]:
		popup.add_item(item[0], item[1])
	if touch_ui:
		popup.add_item("Вся суша", 11)
		popup.add_item("Скрыть панели", 12)
	popup.about_to_popup.connect(func():
		if platform!=null and platform.available and popup.get_item_index(7)==-1:
			popup.add_separator()
			for item in [["Сохранить в облако",7],["Загрузить из облака",8],["Дождь за видео",9]]: popup.add_item(item[0],item[1]))
	popup.id_pressed.connect(_world_menu_selected)
	top_time = HBoxContainer.new()
	top_time.add_theme_constant_override("separation", 6)
	hud.add_child(top_time)
	var day_panel := PanelContainer.new()
	day_panel.add_theme_stylebox_override("panel", AtlasTheme.frame(AtlasTheme.PAPER, AtlasTheme.COPPER))
	top_time.add_child(day_panel)
	day_label = _label("Месяц 1", 12, ACCENT)
	day_panel.add_child(day_label)
	pause_button = _button("", _toggle_pause, Vector2(44, 44))
	pause_button.icon = PixelArt.icon("pause")
	pause_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_button.add_theme_constant_override("icon_max_width", 14)
	pause_button.tooltip_text = "Пауза / продолжить · Пробел"
	top_time.add_child(pause_button)
	speed_button = _button("×1", _cycle_speed, Vector2(44, 44))
	speed_button.tooltip_text = "Скорость: ×1 → ×2 → ×5 · Клавиши 1, 2, 3"
	top_time.add_child(speed_button)
	_build_tool_drawer()
	_build_info_drawer()
	tools_button = _button("Инструменты", _toggle_tools, Vector2(154, 44))
	tools_button.toggle_mode = true
	tools_button.icon = PixelArt.icon("inspect")
	tools_button.add_theme_constant_override("icon_max_width", 16)
	tools_button.tooltip_text = "Открыть / скрыть инструменты · T"
	hud.add_child(tools_button)
	bottom_controls = HBoxContainer.new()
	bottom_controls.add_theme_constant_override("separation", 6)
	hud.add_child(bottom_controls)
	info_button = _button("Сведения", _toggle_info, Vector2(92, 44))
	info_button.toggle_mode = true
	info_button.tooltip_text = "Сведения и хроника · I"
	bottom_controls.add_child(info_button)
	var zoom_out := _button("−", func(): view.zoom_by(1.0 / 1.3), Vector2(44, 44))
	zoom_out.name = "ZoomOut"
	zoom_out.tooltip_text = "Отдалить · −"
	bottom_controls.add_child(zoom_out)
	var fit := _button("", func(): view.fit_map(), Vector2(44, 44))
	fit.name = "Fit"
	fit.icon = PixelArt.icon("fit")
	fit.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fit.add_theme_constant_override("icon_max_width", 16)
	fit.tooltip_text = "Вся созданная суша · F"
	bottom_controls.add_child(fit)
	var zoom_in := _button("+", func(): view.zoom_by(1.3), Vector2(44, 44))
	zoom_in.name = "ZoomIn"
	zoom_in.tooltip_text = "Приблизить · +"
	bottom_controls.add_child(zoom_in)
	var clean := _button("◌", _toggle_hud, Vector2(44, 44))
	clean.name = "Clean"
	clean.tooltip_text = "Скрыть интерфейс · Tab"
	bottom_controls.add_child(clean)
	status_panel = PanelContainer.new()
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_theme_stylebox_override("panel", AtlasTheme.frame(AtlasTheme.PAPER, AtlasTheme.COPPER))
	hud.add_child(status_panel)
	status_label = _label("", 12, ACCENT)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_panel.add_child(status_label)
	status_panel.hide()
	reveal_button = _button("Панели", _toggle_hud, Vector2(90, 44))
	reveal_button.tooltip_text = "Вернуть интерфейс · Tab / Esc"
	add_child(reveal_button)
	reveal_button.hide()
	_build_dialogs()

func _drawer_heading(parent: VBoxContainer, title: String, close: Callable) -> void:
	var cover := PanelContainer.new()
	var frame := AtlasTheme.frame(AtlasTheme.INK, AtlasTheme.COPPER)
	frame.content_margin_left = 6; frame.content_margin_right = 6
	frame.content_margin_top = 3; frame.content_margin_bottom = 3
	cover.add_theme_stylebox_override("panel", frame)
	parent.add_child(cover)
	var row := HBoxContainer.new()
	cover.add_child(row)
	var heading := _label(title, 18, AtlasTheme.PAPER)
	heading.add_theme_font_override("font", BOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	row.add_child(_button("×", close, Vector2(36, 36)))

func _build_tool_drawer() -> void:
	tool_panel = PanelContainer.new()
	hud.add_child(tool_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tool_panel.add_child(scroll)
	toolbar = VBoxContainer.new()
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(toolbar)
	_drawer_heading(toolbar, "Кисти мира", _toggle_tools)
	var nav := HBoxContainer.new()
	toolbar.add_child(nav)
	for item in [["inspect", "Обзор", "Коснитесь земли, жителя или поселения"], ["pan", "Камера", "Перетащите карту; два пальца меняют масштаб"]]:
		var button := _tool_button(item[0], item[1], item[2])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(button)
	tool_group_picker = OptionButton.new()
	tool_group_picker.custom_minimum_size.y = 40
	for group_name in ["Земля", "Жизнь", "Стихии", "Биомы"]:
		tool_group_picker.add_item(group_name)
	tool_group_picker.item_selected.connect(_tool_group_changed)
	toolbar.add_child(tool_group_picker)
	land_group = GridContainer.new()
	land_group.columns = 3
	land_group.add_theme_constant_override("h_separation", 6)
	land_group.add_theme_constant_override("v_separation", 6)
	toolbar.add_child(land_group)
	for item in [["water", "Вода", "Удаляет сушу; пустой океан не занимает место"], ["sand", "Песок", "Песчаный берег без источников еды"], ["grass", "Равнина", "Рисуйте землю в любом месте. Для континентов увеличьте кисть"], ["forest", "Лес", "Источник еды и древесины"], ["mountain", "Горы", "Непроходимые горы"]]:
		land_group.add_child(_tool_button(item[0], item[1], item[2]))
	life_tool = _tool_button("person", "Поселить жителя", "Разместите минимум трёх жителей рядом", false)
	toolbar.add_child(life_tool)
	power_group = HBoxContainer.new()
	toolbar.add_child(power_group)
	for item in [["fire", "Молния", "Поджигает лес и равнину"], ["rain", "Дождь", "Тушит огонь и восстанавливает еду"]]:
		var button := _tool_button(item[0], item[1], item[2])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		power_group.add_child(button)
	biome_group=GridContainer.new(); biome_group.columns=2; toolbar.add_child(biome_group)
	for i in WorldClimate.NAMES.size():
		biome_group.add_child(_tool_button("biome_%d" % i,WorldClimate.NAMES[i],"Меняет климат суши, сохраняя землю и поселения"))
	biome_group.hide()
	tool_title = _label("Обзор", 14, ACCENT)
	toolbar.add_child(tool_title)
	tool_description = _label("", 12, MUTED)
	tool_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_description.custom_minimum_size.x = 200
	toolbar.add_child(tool_description)
	brush_row = VBoxContainer.new()
	toolbar.add_child(brush_row)
	brush_label = _label("Размер кисти · 2", 12, MUTED)
	brush_row.add_child(brush_label)
	brush_slider = HSlider.new()
	var slider := brush_slider
	slider.min_value = 1
	slider.max_value = 64
	slider.step = 1
	slider.value = 2
	slider.custom_minimum_size.y = 36
	slider.value_changed.connect(func(value: float):
		view.brush_radius = int(value)
		brush_label.text = "Размер кисти · %d" % int(value))
	brush_row.add_child(slider)
	tool_panel.hide()

func _build_info_drawer() -> void:
	sidebar = PanelContainer.new()
	hud.add_child(sidebar)
	var side := VBoxContainer.new()
	sidebar.add_child(side)
	var tabs := HBoxContainer.new()
	side.add_child(tabs)
	object_tab = _button("Выбрано", func(): _set_info_tab(false), Vector2(0, 36))
	world_tab = _button("События", func(): _set_info_tab(true), Vector2(0, 36))
	var tab_group := ButtonGroup.new()
	tab_group.allow_unpress = false
	for tab in [object_tab, world_tab]:
		tab.button_group = tab_group
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
	tabs.add_child(_button("×", _toggle_info, Vector2(38, 36)))
	object_tab.set_pressed_no_signal(true)
	history_scroll = ScrollContainer.new()
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(history_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_scroll.add_child(content)
	inspector = WorldInspector.new()
	content.add_child(inspector)
	inspector.setup(touch_ui, _touch_target())
	inspector.details_changed.connect(func(): inspector_dirty = true)
	inspector.selection_changed.connect(func():
		info_scroll_positions[0] = 0
		history_scroll.set_deferred("scroll_vertical", 0))
	world_info = VBoxContainer.new()
	world_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(world_info)
	stats_label = _label("", 14, AtlasTheme.INK)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world_info.add_child(stats_label)
	world_info.add_child(HSeparator.new())
	world_info.add_child(_label("Летопись", 18, ACCENT))
	history_box = VBoxContainer.new()
	history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_box.add_theme_constant_override("separation", 14)
	world_info.add_child(history_box)
	world_info.hide()
	sidebar.hide()

func _set_info_tab(show_world: bool) -> void:
	if info_world == show_world: return
	info_scroll_positions[int(info_world)] = history_scroll.scroll_vertical
	info_world = show_world
	inspector.visible = not show_world
	world_info.visible = show_world
	object_tab.set_pressed_no_signal(not show_world)
	world_tab.set_pressed_no_signal(show_world)
	history_scroll.set_deferred("scroll_vertical", info_scroll_positions[int(show_world)])
	inspector_dirty = true

func _build_dialogs() -> void:
	generation_dialog = ConfirmationDialog.new()
	generation_dialog.title = "Новый остров"
	generation_dialog.dialog_text = ""
	generation_dialog.exclusive = true
	generation_dialog.ok_button_text = "Создать остров"
	generation_dialog.cancel_button_text = "Отмена"
	var generation_content := VBoxContainer.new()
	generation_content.custom_minimum_size.x = 520
	generation_content.add_theme_constant_override("separation", 14)
	var replacement_hint := _label("Текущий мир будет заменён. Сохраните его через меню «Мир».", 13)
	replacement_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	replacement_hint.custom_minimum_size.x = 520
	generation_content.add_child(replacement_hint)
	var seed_hint := _label("Число генерации: одинаковое число создаёт одинаковый остров.", 12, MUTED)
	seed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	seed_hint.custom_minimum_size.x = 520
	generation_content.add_child(seed_hint)
	seed_input = LineEdit.new()
	seed_input.text = "42817"
	seed_input.max_length = 10
	seed_input.custom_minimum_size = Vector2(180, 42)
	generation_content.add_child(seed_input)
	generation_dialog.add_child(generation_content)
	generation_dialog.confirmed.connect(func(): _at_boundary(_generate))
	add_child(generation_dialog)
	settings_dialog = AcceptDialog.new()
	settings_dialog.title = "Настройки"
	settings_dialog.exclusive = true
	settings_dialog.ok_button_text = "Готово"
	var settings := VBoxContainer.new()
	settings_dialog.add_child(settings)
	settings.add_child(_label("Размер интерфейса",16,MUTED))
	ui_scale_picker = OptionButton.new()
	for caption in ["Компактный · 85%","Системный · 100%","Крупный · 115%","Очень крупный · 130%"]: ui_scale_picker.add_item(caption)
	var scale_options := [0.85,1.0,1.15,1.3]
	ui_scale_picker.select(scale_options.find(preferences.ui_scale) if scale_options.has(preferences.ui_scale) else 1)
	ui_scale_picker.item_selected.connect(_set_ui_scale)
	settings.add_child(ui_scale_picker)
	var motion := CheckButton.new()
	motion.text = "Уменьшить анимацию"
	motion.button_pressed=preferences.reduce_motion
	motion.toggled.connect(func(value: bool): view.reduce_motion=value; preferences.reduce_motion=value; preferences.save_preferences())
	settings.add_child(motion)
	var minimap := CheckButton.new()
	minimap.text = "Показывать мини-карту"
	minimap.button_pressed=preferences.minimap
	minimap.toggled.connect(func(value: bool): view.show_minimap=value; preferences.minimap=value; preferences.save_preferences())
	settings.add_child(minimap)
	var settings_hint := _label("Отключает декоративное движение воды, жителей и флагов.", 12, MUTED)
	settings_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_hint.custom_minimum_size.x = 340
	settings.add_child(settings_hint)
	var autosave:=CheckButton.new(); autosave.text="Автосохранение" if touch_ui else "Автосохранение раз в минуту"; autosave.button_pressed=preferences.autosave
	autosave.toggled.connect(func(value: bool): preferences.autosave=value; preferences.save_preferences())
	settings.add_child(autosave)
	for item in [["effects","Звуки действий"],["ambience","Шум океана"]]:
		var row:=HBoxContainer.new(); settings.add_child(row); row.add_child(_label(item[1],12,MUTED))
		var slider:=HSlider.new(); slider.min_value=0; slider.max_value=1; slider.step=.05; slider.value=preferences.get(item[0]); slider.custom_minimum_size=Vector2(150,36); row.add_child(slider)
		var key: String=item[0]
		slider.value_changed.connect(func(value: float): preferences.set(key,value); sound.update_volume(); preferences.save_preferences())
	add_child(settings_dialog)
	navigation_dialog = ConfirmationDialog.new()
	navigation_dialog.title = "Путешествие по миру"
	navigation_dialog.exclusive = true
	navigation_dialog.ok_button_text = "Перейти"
	navigation_dialog.cancel_button_text = "Отмена"
	var navigation := VBoxContainer.new()
	navigation.add_theme_constant_override("separation", 12)
	navigation.custom_minimum_size.x = 380
	navigation_dialog.add_child(navigation)
	var hint := _label("Выберите поселение или координаты. В океане можно нарисовать новый остров кистью земли.", 12, MUTED)
	hint.custom_minimum_size.x = 380
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	navigation.add_child(hint)
	destination_picker = OptionButton.new()
	destination_picker.custom_minimum_size.y = 40
	navigation.add_child(destination_picker)
	destination_picker.item_selected.connect(func(index: int):
		var cell: Vector2i = destination_picker.get_item_metadata(index)
		coordinate_x.value = cell.x
		coordinate_y.value = cell.y)
	var coordinates := HBoxContainer.new()
	navigation.add_child(coordinates)
	coordinates.add_child(_label("X", 13, ACCENT))
	coordinate_x = SpinBox.new()
	coordinate_y = SpinBox.new()
	for spin in [coordinate_x, coordinate_y]:
		spin.min_value = -WorldState.COORD_LIMIT
		spin.max_value = WorldState.COORD_LIMIT - 1
		spin.step = 1
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.custom_minimum_size = Vector2(165, 40)
	coordinates.add_child(coordinate_x)
	coordinates.add_child(_label("Y", 13, ACCENT))
	coordinates.add_child(coordinate_y)
	navigation_dialog.confirmed.connect(func():
		coordinate_x.apply()
		coordinate_y.apply()
		view.go_to_cell(Vector2i(coordinate_x.value, coordinate_y.value)))
	add_child(navigation_dialog)
	_build_climate_and_help()
	modal_scrim = ColorRect.new()
	modal_scrim.color = Color(0.015, 0.035, 0.04, 0.55)
	modal_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_scrim.hide()
	add_child(modal_scrim)
	for dialog in [generation_dialog, settings_dialog, navigation_dialog,climate_dialog,help_dialog,sculpt_dialog]:
		dialog.about_to_popup.connect(func(): modal_scrim.show())
		dialog.visibility_changed.connect(func(): modal_scrim.visible = _modal_open())

func _responsive() -> void:
	if sidebar == null: return
	if tool_tween != null: tool_tween.kill()
	if info_tween != null: info_tween.kill()
	safe_rect = _screen_rect()
	var top := safe_rect.position.y + (60.0 if touch_ui else 60.0)
	var bottom := safe_rect.end.y - (_touch_target() if touch_ui else 44.0)
	var available_height := maxf(80, bottom - top - 12)
	tool_panel.size = Vector2(minf(324 if touch_ui else 248, safe_rect.size.x), available_height)
	sidebar.size = Vector2(minf(360 if touch_ui else 344, safe_rect.size.x), available_height)
	tool_panel.position = Vector2(safe_rect.position.x if tools_open else -tool_panel.size.x - 16, top)
	sidebar.position = Vector2(safe_rect.end.x - sidebar.size.x if info_open else size.x + 16, top)
	tool_panel.visible = tools_open
	sidebar.visible = info_open
	if touch_ui:
		tools_button.text = "Кисть"
		tools_button.custom_minimum_size = Vector2(88,_touch_target())
		tools_button.size = tools_button.get_combined_minimum_size()
		info_button.text = "Мир"
		info_button.custom_minimum_size = Vector2(64,_touch_target())
		bottom_controls.get_node("Clean").hide()
		bottom_controls.get_node("Fit").visible = safe_rect.size.x >= 460
		day_label.visible = safe_rect.size.x >= 420
		day_label.get_parent().visible = day_label.visible
	call_deferred("_fit_tool_drawer")
	top_time.position = Vector2(safe_rect.end.x - top_time.get_combined_minimum_size().x, safe_rect.position.y)
	world_menu.position = safe_rect.position
	tools_button.position = Vector2(safe_rect.position.x, bottom)
	bottom_controls.position = Vector2(safe_rect.end.x - bottom_controls.get_combined_minimum_size().x, bottom)
	reveal_button.position = Vector2(safe_rect.position.x, bottom)
	status_panel.position = Vector2(maxf(safe_rect.position.x, (size.x - 420) * 0.5), bottom - 56)
	status_panel.size.x = minf(420, safe_rect.size.x)
	status_panel.custom_minimum_size.x = minf(420, safe_rect.size.x)
	if _compact_drawers() and tools_open and info_open: _set_drawer("info", false, false)

func _tool_group_changed(index: int) -> void:
	land_group.visible = index == 0
	life_tool.visible = index == 1
	power_group.visible = index == 2
	biome_group.visible = index == 3
	call_deferred("_fit_tool_drawer")

func _fit_tool_drawer() -> void:
	if tool_panel != null:
		tool_panel.size.y = minf(maxf(180, toolbar.get_combined_minimum_size().y + 28), maxf(80, safe_rect.end.y - tool_panel.position.y - 60))

func _compact_drawers() -> bool:
	return size.x < 900 or (touch_ui and minf(size.x,size.y) < 600)

func _toggle_tools() -> void:
	_set_drawer("tools", not tools_open)

func _toggle_info() -> void:
	if not info_open and selected_cell == WorldState.NO_CELL: _set_info_tab(true)
	_set_drawer("info", not info_open)

func _set_drawer(key: String, opened: bool, animated: bool = true) -> void:
	if key == "tools":
		tools_open = opened
		tools_button.button_pressed = opened
	else:
		info_open = opened
		info_button.button_pressed = opened
		if opened: inspector_dirty = true
	if opened and _compact_drawers():
		if key == "tools" and info_open: _set_drawer("info", false, animated)
		elif key == "info" and tools_open: _set_drawer("tools", false, animated)
	var panel := tool_panel if key == "tools" else sidebar
	var old_tween := tool_tween if key == "tools" else info_tween
	if old_tween != null: old_tween.kill()
	var target: float = (safe_rect.position.x if opened else -panel.size.x - 16.0) if key == "tools" else (safe_rect.end.x - panel.size.x if opened else size.x + 16.0)
	if not animated or view.reduce_motion:
		panel.position.x = target
		panel.visible = opened
		return
	panel.show()
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:x", target, 0.22)
	if not opened:
		tween.tween_callback(panel.hide)
	if key == "tools": tool_tween = tween
	else: info_tween = tween

func _toggle_hud() -> void:
	hud_hidden = not hud_hidden
	hud.visible = not hud_hidden
	reveal_button.visible = hud_hidden
	view.interface_visible = not hud_hidden
	view.cancel_input()
	if hud_hidden:
		hidden_tool = view.tool
		view.tool = "pan"
	else:
		view.tool = hidden_tool

func _world_menu_selected(id: int) -> void:
	match id:
		0:
			_ask_generation()
		1:
			_save()
		2:
			_load()
		3:
			_popup_dialog(settings_dialog, Vector2i(400, 310))

		10: _popup_dialog(sculpt_dialog, Vector2i(420,240))
		5:
			climate_mode.selected=["uniform","belts","manual"].find(world.climate.mode)
			climate_biome.selected=world.climate.biome
			climate_scale.value=world.climate.scale; climate_equator.value=world.climate.equator; climate_seasons.button_pressed=world.climate.seasons
			climate_weather.selected = int(world.weather.rate)
			_popup_dialog(climate_dialog, Vector2i(440,300))
		6: _popup_dialog(help_dialog, Vector2i(470,300))
		7: _at_boundary(func(): _save(true); platform.save_cloud(world))
		11: view.fit_map()
		12: _toggle_hud()
		8: platform.load_cloud()
		9: platform.rewarded()
		4:
			var center := view.local_to_cell(view.size * 0.5)
			coordinate_x.value = center.x
			coordinate_y.value = center.y
			destination_picker.clear()
			destination_picker.add_item("Текущая точка")
			destination_picker.set_item_metadata(0, center)
			destination_picker.add_item("Первый остров")
			destination_picker.set_item_metadata(1, Vector2i(64, 64))
			for town in world.towns:
				destination_picker.add_item(town.name)
				destination_picker.set_item_metadata(destination_picker.item_count - 1, Vector2i(town.x, town.y))
			_popup_dialog(navigation_dialog, Vector2i(420, 250))

func _set_world(value: WorldState) -> void:
	step_job = null
	if sculpt!=null:
		sculpt.cancelled=true; sculpt.advance(); sculpt=null; sculpt_stop.hide()
	if world != null and world.changed.is_connected(_refresh):
		world.changed.disconnect(_refresh)
	world = value
	weather_sequence = int(world.weather.sequence)
	world.changed.connect(_refresh)
	view.set_world(world)
	seed_input.text = str(world.world_seed)
	selected_cell = WorldState.NO_CELL
	pending_inspection = WorldState.NO_CELL; pending_inspection_cycles = 0
	inspected_person_id = -1
	inspector.reset()
	object_tab.text = "Выбрано"
	info_scroll_positions = [0, 0]
	history_scroll.scroll_vertical = 0
	accumulator = 0.0
	autosave_timer = 0.0
	history_signature = ""
	_refresh()

func _select_tool(value: String) -> void:
	view.tool = value
	view.last_painted = WorldState.NO_CELL
	if value not in ["inspect", "pan"]:
		tool_group_picker.selected = 3 if value.begins_with("biome_") else (1 if value == "person" else (2 if value in ["fire", "rain"] else 0))
		_tool_group_changed(tool_group_picker.selected)
	else:
		_tool_group_changed(tool_group_picker.selected)
	for key in tool_buttons:
		var active: bool = key == value
		tool_buttons[key].button_pressed = active
		var caption: Label = tool_buttons[key].get_meta("caption_label")
		caption.add_theme_color_override("font_color", Color("fff0cf") if active else AtlasTheme.INK)
	tool_title.text = tool_buttons[value].get_meta("caption")
	tool_description.text = tool_buttons[value].get_meta("description")
	tools_button.icon = PixelArt.icon(value)
	brush_slider.max_value = 8 if value in ["fire", "rain"] else 64
	brush_row.visible = value.begins_with("biome_") or value in ["water", "sand", "grass", "forest", "mountain", "fire", "rain"]
	call_deferred("_fit_tool_drawer")
	if size.x < 900 and tools_open:
		_set_drawer("tools", false)

func _toggle_pause() -> void:
	paused = not paused
	pause_button.icon = PixelArt.icon("play" if paused else "pause")
	pause_button.tooltip_text = "Продолжить · Пробел" if paused else "Пауза · Пробел"
	_refresh()

func _set_speed(value: int) -> void:
	speed = value
	speed_button.text = "×%d" % value

func _cycle_speed() -> void:
	_set_speed({1: 2, 2: 5, 5: 1}[speed])

func _process(delta: float) -> void:
	if world == null: return
	var work_deadline := Time.get_ticks_usec()+_work_budget()
	if not view.active_stroke(): WorldRegions.cleanup_retired(200)
	inspector_timer += delta
	if climate_update_job != null and Time.get_ticks_usec() < work_deadline:
		if climate_update_job.advance(mini(2000,maxi(1,work_deadline-Time.get_ticks_usec()))):
			climate_update_job = null; view.edits_locked = false
			show_message("Климат обновлён. Поселения приспосабливаются к новым условиям.")
		else:
			status_label.text = "Климат · %d%%" % (climate_update_job.cursor * 100 / maxi(1, climate_update_job.keys.size()))
			status_panel.show()
	if save_job != null and Time.get_ticks_usec() < work_deadline:
		var save_budget := maxi(1,work_deadline-Time.get_ticks_usec())
		if save_job.snapshot_ready: save_budget = mini(2500,save_budget)
		if save_job.advance(save_budget):
			var result := save_job.result
			save_job = null
			view.edits_locked = false
			if result != OK: show_message("Не удалось сохранить мир: %s." % error_string(result))
			elif not save_automatic: show_message("Мир сохранён на этом устройстве.")
		elif save_job.snapshot_ready:
			view.edits_locked = false
	if step_job != null and Time.get_ticks_usec() < work_deadline:
		if step_job.advance(maxi(1,work_deadline-Time.get_ticks_usec())): step_job = null
	if step_job == null and (save_job == null or save_job.snapshot_ready) and climate_update_job == null:
		if Time.get_ticks_usec() < work_deadline: view.flush_tools(maxi(1,work_deadline-Time.get_ticks_usec()))
		while not pending_actions.is_empty() and not view.has_pending_edits() and save_job == null and climate_update_job == null and Time.get_ticks_usec() < work_deadline:
			var action: Callable = pending_actions.pop_front()
			action.call()
		if pending_inspection != WorldState.NO_CELL and not view.has_pending_edits() and save_job == null and climate_update_job == null and Time.get_ticks_usec() < work_deadline:
			var cell := pending_inspection
			var cycles := pending_inspection_cycles
			pending_inspection = WorldState.NO_CELL; pending_inspection_cycles = 0
			_inspect(cell, true, false, cycles)
		if inspector_dirty and info_open and not hud_hidden and not view.has_pending_edits() and save_job == null and inspector_timer >= 0.25 and Time.get_ticks_usec() < work_deadline:
			_refresh_inspector()
	if sculpt != null and step_job == null and save_job == null and climate_update_job == null and Time.get_ticks_usec() < work_deadline:
		sculpt.advance(mini(4000,maxi(1,work_deadline-Time.get_ticks_usec())))
		status_label.text="Создание материка · %d%%" % (sculpt.cursor*100/maxi(1,sculpt.total))
		status_panel.show()
		if sculpt.finished:
			sculpt_stop.hide(); sculpt=null; show_message("Создание суши завершено. Можно поселить жителей.")
	var running := not paused and not suspended and not _modal_open() and sculpt == null and climate_update_job == null
	platform.gameplay(running)
	if running and (save_job == null or save_job.snapshot_ready):
		accumulator = minf(0.4, accumulator + minf(delta, 0.25) * speed)
		if step_job == null and not view.has_pending_edits() and not view.active_stroke() and accumulator >= 0.2:
			accumulator -= 0.2
			step_job = WorldStepJob.new(world)
	autosave_timer += delta
	if preferences.autosave and autosave_timer >= 60.0 and not suspended and sculpt == null and save_job == null and climate_update_job == null:
		autosave_timer = 0.0
		_save(true)
	if message_time > 0:
		message_time -= delta
		if message_time <= 0: status_panel.hide()

func _work_budget() -> int:
	return clampi(8000-view.process_usec-view.draw_usec,2000,6000)

func _exit_tree() -> void:
	WorldRegions.deferred_cleanup = false
	WorldRegions.cleanup_retired(0)

func _refresh() -> void:
	if int(world.weather.sequence) > weather_sequence:
		weather_sequence = int(world.weather.sequence)
		if not hud_hidden:
			for event in world.weather.active:
				if int(event.id) == weather_sequence: show_message(WorldWeather.TITLES[event.kind]); break
	stats_label.text = "%d жителей · %d поселений\n%s" % [world.people.size(), world.towns.size(),
		"%d очагов огня" % world.fires.size() if not world.fires.is_empty() else ("Засуха" if world.ticks < world.drought_until else "Остров спокоен")]
	day_label.text = "Год %d · месяц %d" % [world.year(), (world.month() - 1) % WorldEconomy.DAYS_PER_YEAR + 1]
	inspector_dirty = true
	if inspected_person_id != -1:
		var person := WorldLife.person(world, inspected_person_id)
		if not person.is_empty():
			selected_cell = Vector2i(person.x, person.y)
			view.selected = selected_cell

func _refresh_inspector() -> void:
	inspector_dirty = false
	inspector_timer = 0.0
	inspector_updates += 1
	if selected_cell != WorldState.NO_CELL and not info_world: _inspect(selected_cell, false)
	if not info_world: return
	var signature := str(world.history_revision)
	if signature != history_signature:
		history_signature = signature
		for child in history_box.get_children():
			history_box.remove_child(child)
			child.queue_free()
		for event in world.history.slice(0, 20):
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", inspector.surface(Color("f0e3c7"), Color("baa27b")))
			history_box.add_child(card)
			var entry := VBoxContainer.new()
			entry.add_theme_constant_override("separation", 6)
			card.add_child(entry)
			entry.add_child(_label("ГОД %d · МЕСЯЦ %d" % [int(event.tick) / WorldLife.YEAR + 1, (int(event.tick) / WorldEconomy.DAY_TICKS) % WorldEconomy.DAYS_PER_YEAR + 1], 10, ACCENT))
			var title := _label(event.title, 15)
			title.add_theme_font_override("font", BOLD)
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			entry.add_child(title)
			var description := _label(event.message, 12, MUTED)
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			entry.add_child(description)

func _request_inspection(cell: Vector2i) -> void:
	_set_info_tab(false)
	if not hud_hidden: _set_drawer("info", true)
	pending_inspection_cycles = pending_inspection_cycles + 1 if pending_inspection == cell else 1
	pending_inspection = cell

func _inspect(cell: Vector2i, reveal: bool = true, open_panel: bool = true, cycles: int = 1) -> void:
	var person: Dictionary = {}
	var structure := world.building_at(cell)
	if reveal:
		var repeated_cell := selected_cell == cell
		var previous_person_id := inspected_person_id if selected_cell == cell else -1
		inspected_person_id = -1
		if structure.is_empty() or structure.kind != "camp" or repeated_cell or cycles > 1:
			var occupants: Array[Dictionary] = []
			occupants = world.population.nearby(world, cell, 0)
			if not occupants.is_empty():
				var camp: bool = not structure.is_empty() and structure.kind == "camp"
				var slots := occupants.size() + (1 if camp else 0)
				var next := posmod(cycles - (2 if camp and not repeated_cell else 1), slots)
				for i in occupants.size():
					if occupants[i].id == previous_person_id: next = (i + cycles) % slots
				if next < occupants.size():
					person = occupants[next]
					inspected_person_id = person.id
	elif inspected_person_id != -1:
		person = WorldLife.person(world, inspected_person_id)
		if not person.is_empty():
			cell = Vector2i(person.x, person.y)
			view.selected = cell
		if person.is_empty(): inspected_person_id = -1
	selected_cell = cell
	if not world.inside(cell): return
	if not open_panel and (not info_open or hud_hidden):
		inspector_dirty = true
		return
	world.workforce.begin(world, false)
	var nearest: Dictionary = {}
	if person.is_empty():
		if not structure.is_empty(): nearest = WorldEconomy.town(world, structure.town)
		if nearest.is_empty():
			var distance := 7.0
			for home in world.towns:
				var gap := cell.distance_to(Vector2i(home.x, home.y))
				if gap < distance:
					nearest = home
					distance = gap
	if reveal: _set_info_tab(false)
	inspector.present(world, cell, person, nearest, structure)
	object_tab.text = {"town": "Поселение", "person": "Житель", "terrain": "Клетка", "site":"Руины"}[inspector.selection_kind]
	world.workforce.end()
	world.population.active = false
	inspector_dirty = false
	inspector_timer = 0.0
	if reveal and open_panel and not hud_hidden: _set_drawer("info", true)

func show_message(message: String) -> void:
	status_label.text = message
	message_time = 4.0
	status_panel.show()
	if toast_tween != null: toast_tween.kill()
	status_panel.modulate.a = 0.3
	toast_tween = create_tween()
	toast_tween.tween_property(status_panel, "modulate:a", 1.0, 0.16)

func _ask_generation() -> void:
	_popup_dialog(generation_dialog, Vector2i(560, 230))

func _generate() -> void:
	if not seed_input.text.is_valid_int():
		show_message("Число генерации должно быть целым.")
		return
	var fresh := WorldState.new()
	fresh.generate(seed_input.text.to_int())
	fresh.weather.rate = int(world.weather.rate)
	WorldClimate.configure(fresh,world.climate.mode,world.climate.biome,world.climate.equator,world.climate.scale,world.climate.seasons)
	_set_world(fresh)
	show_message("Новый остров готов. Разместите минимум трёх жителей рядом, чтобы появилось поселение.")

func _save(automatic: bool = false) -> void:
	_at_boundary(func():
		save_automatic = automatic
		save_job = WorldSaveJob.new(world)
		view.edits_locked = true)

func _load() -> void:
	_at_boundary(_load_now)

func _load_now() -> void:
	var loaded := SaveStore.load_world()
	if loaded == null:
		show_message("Сохранение отсутствует или повреждено. Текущий мир сохранён в памяти.")
		return
	_set_world(loaded)
	show_message("Мир загружен.")

func _input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and _input_popup_open():
		get_viewport().set_input_as_handled()
		return

	if not event is InputEventKey or not event.pressed or event.echo: return
	if generation_dialog == null or _modal_open(): return
	if world_menu.get_popup().visible or get_viewport().gui_get_focus_owner() is LineEdit: return
	if event.keycode == KEY_TAB:
		_toggle_hud()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and (hud_hidden or tools_open or info_open):
		if hud_hidden: _toggle_hud()
		else:
			_set_drawer("tools", false)
			_set_drawer("info", false)
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if _modal_open(): return
	if get_viewport().gui_get_focus_owner() is LineEdit: return
	match event.keycode:
		KEY_F11:
			if not OS.has_feature("web"): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_SPACE:
			_toggle_pause()
		KEY_1:
			_set_speed(1)
		KEY_2:
			_set_speed(2)
		KEY_3:
			_set_speed(5)
		KEY_F:
			view.fit_map()
		KEY_G:
			_world_menu_selected(4)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			view.zoom_by(1.3)
		KEY_MINUS, KEY_KP_SUBTRACT:
			view.zoom_by(1.0 / 1.3)
		KEY_T:
			_toggle_tools()
		KEY_I:
			_toggle_info()
		KEY_S:
			if event.ctrl_pressed: _save()
		KEY_L:
			if event.ctrl_pressed: _load()

func _notification(what: int) -> void:
	if world == null:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_finish_work()
		SaveStore.save_world(world)
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_cancel_ui_input(self)
		app_suspended=true; _update_suspension(); platform.gameplay(false)
		_finish_work()
		SaveStore.save_world(world)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		view.cancel_input()
		app_suspended=false; _update_suspension()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		view.cancel_input()

func _cancel_ui_input(node: Node) -> void:
	if node == self: view.cancel_input()
	if node is PopupMenu: node.hide()
	for child in node.get_children(true): _cancel_ui_input(child)

func _update_suspension() -> void:
	suspended=platform_suspended or app_suspended
	sound.set_muted(suspended)

func _modal_open() -> bool:
	return generation_dialog.visible or settings_dialog.visible or navigation_dialog.visible or climate_dialog.visible or help_dialog.visible or sculpt_dialog.visible

func _build_climate_and_help() -> void:
	climate_dialog=AcceptDialog.new(); climate_dialog.title="Климат мира"; climate_dialog.exclusive=true; climate_dialog.ok_button_text="Применить"
	var content:=VBoxContainer.new(); climate_dialog.add_child(content)
	var hint:=_label("Пояса привязаны к координатам. Биомы кистью имеют приоритет. Новый остров наследует эти настройки.",12,MUTED); hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; hint.custom_minimum_size.x=400; content.add_child(hint)
	var row:=HBoxContainer.new(); content.add_child(row)
	climate_mode=OptionButton.new(); row.add_child(climate_mode)
	for caption in ["Единый климат","Климатические пояса","Ручные биомы"]: climate_mode.add_item(caption)
	climate_biome=OptionButton.new(); row.add_child(climate_biome)
	for caption in WorldClimate.NAMES: climate_biome.add_item(caption)
	var latitude:=HBoxContainer.new(); content.add_child(latitude); latitude.add_child(_label("Экватор Y",12))
	climate_equator=SpinBox.new(); climate_equator.min_value=-999999; climate_equator.max_value=999999; latitude.add_child(climate_equator)
	latitude.add_child(_label("Ширина пояса",12)); climate_scale=SpinBox.new(); climate_scale.min_value=32; climate_scale.max_value=1000000; latitude.add_child(climate_scale)
	climate_seasons=CheckButton.new(); climate_seasons.text="Смена сезонов"; content.add_child(climate_seasons)
	var weather_row := HBoxContainer.new(); content.add_child(weather_row)
	weather_row.add_child(_label("Природные события", 12))
	climate_weather = OptionButton.new(); weather_row.add_child(climate_weather)
	for caption in ["Выключены", "Редкие", "Обычные", "Частые"]: climate_weather.add_item(caption)
	climate_dialog.confirmed.connect(func(): _at_boundary(_apply_climate))
	add_child(climate_dialog)
	help_dialog=AcceptDialog.new(); help_dialog.title="Как играть"; help_dialog.exclusive=true; help_dialog.ok_button_text="В мир"
	var help:=_label("1. Земля. Откройте инструменты и рисуйте сушу, лес и горы. Кисть до 64 клеток; за новым материком переходите к координатам (G).\n\n2. Жизнь. Разместите от трёх жителей рядом. Поселение само собирает еду, строит, растит детей и передаёт навыки. Нужны лес и доступные горы для ремёсел.\n\n3. История. Выберите жителя или лагерь: сведения покажут снабжение, семьи, открытия и причины задержек. Отдельные острова встретятся после освоения судов. Климат меняется в меню мира или кистью биомов.\n\n4. Управление. Колесо / два пальца — масштаб, правая кнопка / режим камеры — движение. Пробел — пауза, Tab — скрыть панели. Мир → Сохранить; в браузере хранение привязано к сайту и устройству.",12,MUTED)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; help.custom_minimum_size.x=430
	var help_scroll:=ScrollContainer.new(); help_scroll.custom_minimum_size=Vector2(430,260); help_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	help.size_flags_horizontal=Control.SIZE_EXPAND_FILL; help_scroll.add_child(help); help_dialog.add_child(help_scroll)
	help_dialog.confirmed.connect(func(): preferences.tutorial_done=true; preferences.save_preferences())
	add_child(help_dialog)
	sculpt_dialog=ConfirmationDialog.new(); sculpt_dialog.title="Создать материк"; sculpt_dialog.exclusive=true; sculpt_dialog.ok_button_text="Создать"; sculpt_dialog.cancel_button_text="Отмена"
	var sculpt_content:=VBoxContainer.new(); sculpt_dialog.add_child(sculpt_content)
	var sculpt_hint:=_label("Новый материк появится в центре камеры. Существующая земля сохраняется. Можно остановить создание в любой момент.",12,MUTED); sculpt_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; sculpt_hint.custom_minimum_size.x=380; sculpt_content.add_child(sculpt_hint)
	var dimensions_row:=HBoxContainer.new(); sculpt_content.add_child(dimensions_row)
	dimensions_row.add_child(_label("Ширина",12)); sculpt_width=SpinBox.new(); dimensions_row.add_child(sculpt_width)
	dimensions_row.add_child(_label("Высота",12)); sculpt_height=SpinBox.new(); dimensions_row.add_child(sculpt_height)
	for spin in [sculpt_width,sculpt_height]: spin.min_value=32; spin.max_value=2048; spin.step=32; spin.value=256
	sculpt_dialog.confirmed.connect(func(): _at_boundary(_begin_sculpt))
	add_child(sculpt_dialog)
	sculpt_stop=_button("Остановить создание",func(): if sculpt!=null: sculpt.cancelled=true,Vector2(190,48)); sculpt_stop.position=Vector2(16,76); add_child(sculpt_stop); sculpt_stop.hide()

func _begin_sculpt() -> void:
	sculpt_width.apply(); sculpt_height.apply()
	var job:=WorldSculpt.new()
	if job.begin(world,view.local_to_cell(view.size*0.5),Vector2i(sculpt_width.value,sculpt_height.value),WorldState.Terrain.GRASS): sculpt=job; sculpt_stop.show()
	else: show_message("Недостаточно свободных участков для этого размера материка. Уменьшите размеры или удалите лишнюю сушу.")

func _apply_climate() -> void:
	climate_scale.apply(); climate_equator.apply()
	WorldWeather.set_rate(world, climate_weather.selected)
	climate_update_job = WorldClimateConfigureJob.new(world,["uniform","belts","manual"][climate_mode.selected],climate_biome.selected,int(climate_equator.value),int(climate_scale.value),climate_seasons.button_pressed)
	view.edits_locked = true

func _finish_work() -> void:
	if climate_update_job != null: climate_update_job.advance(0); climate_update_job = null; view.edits_locked = false
	if step_job != null: step_job.advance(0); step_job = null
	if save_job != null: save_job.finish(); save_job = null; view.edits_locked = false
	view.flush_tools(0)
	var actions := pending_actions.duplicate()
	pending_actions.clear()
	for action in actions: action.call()
	if save_job != null: save_job.finish(); save_job = null; view.edits_locked = false

func _popup_dialog(dialog: AcceptDialog, requested: Vector2i) -> void:
	if touch_ui:
		dialog.get_ok_button().custom_minimum_size = Vector2(120,48)
		dialog.get_ok_button().add_theme_font_size_override("font_size",16)
		if dialog is ConfirmationDialog:
			dialog.get_cancel_button().custom_minimum_size = Vector2(96,48)
			dialog.get_cancel_button().add_theme_font_size_override("font_size",16)
		var usable := Vector2i(_screen_rect().size) - Vector2i(0, 32)
		if not dialog.has_meta("touch_wrapped"):
			var content: Control
			for child in dialog.get_children():
				if child is BoxContainer or child is ScrollContainer:
					content = child
					break
			if content != null:
				dialog.remove_child(content)
				var scroll := ScrollContainer.new()
				scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				scroll.scroll_deadzone = 12
				scroll.name = "TouchContent"
				dialog.add_child(scroll)
				scroll.add_child(content)
				content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_fit_dialog_content(content)
				_prepare_touch_ui(dialog)
				dialog.set_meta("touch_wrapped", true)
		var scroll := dialog.get_node_or_null("TouchContent")
		if scroll != null: scroll.custom_minimum_size = Vector2(mini(400, usable.x - 32), maxi(80, mini(requested.y - 80, usable.y - 96)))
		dialog.popup_centered(Vector2i(mini(requested.x, usable.x), mini(requested.y, usable.y)))
		var bounds := _screen_rect()
		dialog.position = Vector2i(bounds.position + Vector2((bounds.size.x - dialog.size.x) * .5, 32 + (bounds.size.y - 32 - dialog.size.y) * .5))
	else: dialog.popup_centered(requested)

func _fit_dialog_content(node: Node) -> void:
	if node is Control: node.custom_minimum_size.x = 0
	if node is HBoxContainer:
		var parent := node.get_parent()
		var index := node.get_index()
		var replacement := VBoxContainer.new()
		replacement.size_flags_horizontal = node.size_flags_horizontal
		for child in node.get_children():
			node.remove_child(child); replacement.add_child(child)
		parent.remove_child(node)
		parent.add_child(replacement); parent.move_child(replacement, index)
		node.free()
		node = replacement
	for child in node.get_children(): _fit_dialog_content(child)
