class_name AtlasTheme
extends RefCounted

const PAPER := Color("e7d8b6")
const INK := Color("3d3329")
const COPPER := Color("945f3c")
const MUTED := Color("776750")

static func frame(fill: Color, border: Color) -> StyleBoxTexture:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(1, 1, 22, 22), border.darkened(0.28))
	image.fill_rect(Rect2i(2, 2, 20, 20), border)
	image.fill_rect(Rect2i(3, 3, 18, 18), fill)
	image.fill_rect(Rect2i(4, 3, 16, 1), fill.lightened(0.12))
	image.fill_rect(Rect2i(3, 20, 18, 1), fill.darkened(0.1))
	for point in [Vector2i(2, 2), Vector2i(20, 2), Vector2i(2, 20), Vector2i(20, 20)]:
		image.fill_rect(Rect2i(point, Vector2i(2, 2)), Color("b69b68"))
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(image)
	box.texture_margin_left = 5; box.texture_margin_right = 5
	box.texture_margin_top = 5; box.texture_margin_bottom = 5
	box.content_margin_left = 12; box.content_margin_right = 12
	box.content_margin_top = 8; box.content_margin_bottom = 8
	return box
