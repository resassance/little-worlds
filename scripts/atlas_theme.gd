class_name AtlasTheme
extends RefCounted

const PAPER := Color("f0e8d6")
const INK := Color("303b49")
const COPPER := Color("9a603c")
const MUTED := Color("6e716e")
const NAVY := Color("293847")
const EDGE := Color("cbbda2")
const SOFT := Color("faf4e7")
const GOLD := Color("d2a460")
const BLUE := Color("52788e")
const GOOD := Color("52735d")

static func frame(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

static func button(fill: Color, border: Color, raised: bool = true) -> StyleBoxFlat:
	var box := frame(fill,border)
	box.border_width_bottom = 3 if raised else 1
	box.content_margin_left = 12
	box.content_margin_right = 12
	return box
