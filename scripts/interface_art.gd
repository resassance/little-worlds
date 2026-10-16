class_name InterfaceArt
extends RefCounted

static var textures: Dictionary = {}
const PATTERNS := {
	"food":["......o.....",".....oyo....","...oyyyyo...","..oyoyyoyo..","...oyyyyo...",".....oyo....","....oyo.....","...oyoo.....","..oo.o......"],
	"wood":["..oooooo....",".obttttbo...","obtttttbbo..","obtttttbbo..",".obttttbo...","..oooooo....","....bb......","....bb......"],
	"stone":["............","....oooo....","..oonnnmo...",".onnnnnmmo..","onnnnnnmmmo.","onnnnnnmmmo.",".ooooooooo.."],
	"ore":["....oooo....","..oonnnmo...",".onnttnmmo..","onnnttnmmmo.","onntttnmmmo.",".ooooooooo.."],
	"wool":["...oooooo...","..owwwwwwo..",".owwwwwwwwo.","owwwwwwwwwwo","owwwwwwwwwwo",".owwwwwwwo..","..ooooooo..."],
	"cloth":[".oooooooooo.",".ovvvvvvvvo.",".ovvuvvvvvo.",".ovvvuvvvvo.",".ovvvvuvvvo.",".ovvvvvuvvo.",".oooooooooo."],
	"pottery":["...oooooo...","...otttto...","....otto....","...otttto...","..otttttto..","..otttttto..","...oooooo..."],
	"metal":["............","...ooooooo..","..onnnnnno..",".onnnnnnmo..","onnnnnnmmo..","oooooooooo.."],
	"tools":["..oo........",".onnno......","onnnnnno....",".onnnno.....","...obbo.....","....obbo....",".....obbo...","......oo...."],
	"work":["....oo......",".ooonnno....","onnnnnnno...",".ooonnno....","....obbo....","....obbo....","....obbo....",".....oo....."],
	"book":[".oooo.oooo..",".owwwoowwwo.",".owwwoowwwo.",".owwwoowwwo.",".owwwoowwwo.",".owwwoowwwo.",".oooo.oooo.."],
	"check":[".........oo.","........oyo.",".......oyo..",".oo...oyo...",".oyo.oyo....","..oyoyo.....","...oyo......","....o......."],
	"clock":["...oooooo...","..owwwwwwo..",".owwwowwwwo.",".owwwowwwwo.",".owwwoowwwo.",".owwwwwwwwo.","..owwwwwwo..","...oooooo..."],
	"help":["...ooooo....","..owwwwwo...","..oo..owo...",".....owo....","....owo.....","....oo......","............","....oo......"],
	"arrow":["......oo....",".......oo...",".ooooooooo..",".......oo...","......oo...."],
	"close":[".oo......oo.","..oo....oo..","...oo..oo...","....oooo....",".....oo.....","....oooo....","...oo..oo...","..oo....oo..",".oo......oo."],
	"history":["..oooooooo..","..owwwwwwo..","..owoooowo..","..owwwwwwo..","..owoooowo..","..owwwwwwo..","..owoooowo..","..owwwwwwo..","..oooooooo.."],
	"heart":["..ooo..ooo..",".orrrorrrro.",".orrrrrrrro.","..orrrrrro..","...orrrro...","....orro....",".....oo....."],
	"warning":[".....oo.....","....oyyo....","...oyoyyo...","..oyyoyyyo..",".oyyyyyyyyo.",".oyyyoyyyyo.",".oooooooooo."],
	"flag":["..oooooooo..","..obrrrrro..","..obrrrrro..","..oboooooo..","..ob........","..ob........","..ob........","..ob........"],
	"trade":["........oo..",".oooooooooo.","........oo..","............","..oo........",".oooooooooo.","..oo........"],
	"field":[".oooooooooo.",".obbbbbbbbo.",".obybybybbo.",".obbbbbbbbo.",".obybybybbo.",".obbbbbbbbo.",".oooooooooo."],
	"energy":[".....yyyy...","....yyyy....","...yyyy.....","..yyyyyyy...",".....yyy....","....yyy.....","...yyy......","..yy........"]
}

static func icon(key: String) -> Texture2D:
	if textures.has(key): return textures[key]
	var result: Texture2D
	if PATTERNS.has(key):
		result = PixelArt.sprite_texture(PATTERNS[key], {"o":Color("39495a"),"w":Color("f6ead2"),"y":Color("d5a354"),"b":Color("79563d"),"t":Color("bd8a59"),"v":Color("8ca9b9"),"u":Color("577b94"),"n":Color("c9c8ba"),"m":Color("929b9c"),"r":Color("b36b50")})
	elif key=="building:farm":
		result = icon("field")
	elif key.begins_with("building:"):
		var kind := key.trim_prefix("building:")
		var patterns := {"house":PixelArt.HOUSE,"camp":PixelArt.CAMP,"store":PixelArt.STORE,"archive":PixelArt.ARCHIVE,"workshop":PixelArt.WORKSHOP}
		result = PixelArt.sprite_texture(patterns[kind]) if patterns.has(kind) else PixelArt.building_texture(kind)
	else:
		result = PixelArt.icon(key)
	var image := result.get_image()
	var longest := maxi(image.get_width(),image.get_height())
	if longest>16:
		var ratio := 16.0/longest
		image.resize(maxi(1,roundi(image.get_width()*ratio)),maxi(1,roundi(image.get_height()*ratio)),Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(16,16,false,Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	canvas.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),(Vector2i(16,16)-image.get_size())/2)
	result = ImageTexture.create_from_image(canvas)
	textures[key] = result
	return result

static func rect(key: String, pixels: int = 20) -> TextureRect:
	var node := TextureRect.new()
	node.texture = icon(key)
	node.custom_minimum_size = Vector2(pixels,pixels)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func resource_name(key: String) -> String:
	return {"food":"Еда","wood":"Древесина"}.get(key,WorldCivilization.GOODS.get(key,key))
