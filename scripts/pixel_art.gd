class_name PixelArt
extends RefCounted


const PALETTE := {
	"o": Color("263b39"), "d": Color("426f4b"), "g": Color("649357"),
	"l": Color("94ba69"), "h": Color("c3d88b"), "b": Color("765341"),
	"s": Color("efcf9b"), "w": Color("fff0c6"), "r": Color("bc654b"),
	"t": Color("e09a66"), "y": Color("f7c873"), "a": Color("83c4c0"),
	"c": Color("c0e7d5"), "m": Color("939d91"), "n": Color("c5c9b0"),
	"u": Color("39778a"), "v": Color("5ea2ac"), "f": Color("e7794b"),
	"k": Color("415553")
}
const TREE := [
	".....oo.....", "....olgo....", "...olllgo...", "..ollllgdo..",
	".olllllggdo.", "olllllgggddo", "ollllggggddo", ".oggggggddo.",
	"..oggggddo..", "...oddddo...", "....obbo....", "....obbo....",
	"....obbo....", "...kkkkkk..."
]
const PINE := [
	".....o......", "....olgo....", "...ollgdo...", "..olllggdo..",
	"...ollgdo...", "..olllggdo..", ".ollllgggdo.", "..oggggddo..",
	".olllggggdo.", "ogggggggdddo", "..oddddddo..", "....obbo....",
	"....obbo....", "...kkkkkk..."
]
const HOUSE := [
	"........oo......", "....oooooroo....", "...otttttrrro...", "..ottttttrrrro..",
	".otttttttrrrrro.", "ottttttttrrrrrro", "oooooooooooooooo", ".ossssssssssbo..",
	".oswwoossswwbo..", ".oswwoossswwbo..", ".ossssssssssbo..", ".ossssoooossbo..",
	".ossssobbossbo..", ".ossssobbossbo..", ".ossssobbossbo..", ".ooooooooooooo..",
	"...kkkkkkkkkk..."
]
const CAMP := [
	".......oo.......", "......ossso.....", ".....ossssso....", "....ossssssso...",
	"...ossssssssso..", "..ossssssssssto.", ".ossssssssssstto", "osssssssosssstto",
	"ooooooooooooooo.", "....bb....bb....", "....bb....bb....", "...kkkkkkkkkk..."
]
const STORE := [
	".......oo.......", "...ooooorooo....", "..otttttrrrro...", ".ottttttrrrrro..",
	"otttttttrrrrrro.", "ooooooooooooooo.", ".obsssssssssbo..", ".obsssssssssbo..",
	".obssboooossbo..", ".obssbbwwbssbo..", ".obssbbwwbssbo..", ".obssbbbbbssbo..",
	".obssbbbbbssbo..", ".ooooooooooooo..", "...kkkkkkkkkk..."
]

const PERSON := [
	"..oooo..", ".obbbbo.", ".osssso.", "..osso..", ".occcco.", ".occcco.",
	".occcco.", "..oaao..", "..oooo..", "..o..o..", ".oo..oo.", ".kkkkkk."
]
const JOB_COLORS := {"settler": ["b9d2be", "719a8e"], "forager": ["b8c58a", "827c54"], "logger": ["caa16f", "806049"], "builder": ["b4a5bd", "797186"], "farmer": ["a2bd86", "697f53"], "child": ["dcc4a3", "a88d72"], "teen": ["bac6a2", "829472"], "carer": ["d0afbb", "957d8b"], "teacher": ["d3bf8d", "95805a"], "researcher": ["a7b9c8", "718697"], "miner": ["a8b0a6", "697970"], "artisan": ["c8a08a", "92745c"], "fisher": ["8eb5b7", "5c848d"], "sailor": ["d4c9a2", "758c9e"], "merchant": ["c5adbd", "91788d"], "scout": ["b3bd8e", "778267"]}
const SKIN_TONES := [Color("efcf9b"), Color("d1a076"), Color("a77552"), Color("745039")]
const CLOTH_TONES := [Color.TRANSPARENT, Color("b78570"), Color("899fb4"), Color("cbb791"), Color("aa8397"), Color("929f98")]
const PEOPLE_PALETTES := 24

static func person_palette(seed_value: int, id: int) -> int:
	return posmod(hash(Vector3i(seed_value, id, 9187)), PEOPLE_PALETTES)

static func person_image(job: String, master: bool = false, cold: bool = false, palette: int = 0) -> Image:
	var colors: Array = JOB_COLORS.get(job, JOB_COLORS.settler)
	var cloth: Color = CLOTH_TONES[palette % CLOTH_TONES.size()]
	if cloth.a > 0: colors = [cloth.to_html(false), cloth.darkened(0.28).to_html(false)]
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.blit_rect(sprite_image(PERSON, {"c": Color(colors[0]), "a": Color(colors[1]), "s": SKIN_TONES[palette / CLOTH_TONES.size()]}), Rect2i(0, 0, 8, 12), Vector2i(4, 3))
	var ink := PALETTE.o
	var wood := Color("94734f")
	var edge := Color("bac1af")
	if cold:
		image.fill_rect(Rect2i(5, 7, 6, 4), Color(colors[1]))
		image.fill_rect(Rect2i(5, 7, 6, 1), Color("d2c7aa"))
		image.fill_rect(Rect2i(6, 3, 4, 1), Color(colors[1]))
	if job in ["farmer", "forager", "fisher"]:
		image.fill_rect(Rect2i(5, 3, 6, 2), wood)
		image.fill_rect(Rect2i(4, 5, 8, 1), Color("cbb782"))
	elif job in ["builder", "miner", "artisan"]:
		image.fill_rect(Rect2i(6, 3, 4, 2), Color(colors[1]))
		image.fill_rect(Rect2i(7, 8, 3, 4), Color("8c7158"))
	elif job == "sailor":
		image.fill_rect(Rect2i(5, 3, 6, 2), Color("e6debd"))
		image.fill_rect(Rect2i(5, 8, 6, 1), Color("617e92"))
	elif job in ["teacher", "researcher"]:
		image.fill_rect(Rect2i(5, 9, 6, 3), Color(colors[0]))
	elif job == "scout":
		image.fill_rect(Rect2i(4, 6, 2, 6), Color(colors[1]))
	if job == "logger":
		image.fill_rect(Rect2i(12, 5, 1, 8), wood)
		image.fill_rect(Rect2i(11, 5, 4, 3), ink)
		image.fill_rect(Rect2i(13, 5, 2, 2), edge)
	elif job in ["builder", "artisan"]:
		image.fill_rect(Rect2i(12, 7, 1, 6), wood)
		image.fill_rect(Rect2i(11, 6, 4, 2), ink)
		image.fill_rect(Rect2i(11, 6, 3, 1), edge)
	elif job == "miner":
		image.fill_rect(Rect2i(12, 5, 1, 8), wood)
		image.fill_rect(Rect2i(10, 5, 5, 1), edge)
		image.fill_rect(Rect2i(14, 6, 1, 2), edge)
	elif job == "farmer":
		image.fill_rect(Rect2i(12, 5, 1, 9), wood)
		image.fill_rect(Rect2i(10, 13, 3, 1), edge)
	elif job == "fisher":
		image.fill_rect(Rect2i(12, 3, 1, 11), wood)
		image.fill_rect(Rect2i(13, 3, 2, 1), Color("d8d5ae"))
		image.fill_rect(Rect2i(14, 4, 1, 7), Color("d8d5ae"))
	elif job in ["forager", "merchant"]:
		image.fill_rect(Rect2i(11, 8, 4, 5), ink)
		image.fill_rect(Rect2i(12, 9, 3, 3), Color("b79563"))
		image.fill_rect(Rect2i(12, 7, 2, 1), wood)
	elif job == "sailor":
		image.fill_rect(Rect2i(12, 5, 1, 8), wood)
		image.fill_rect(Rect2i(11, 11, 3, 3), Color("c0a67c"))
	elif job in ["teacher", "researcher"]:
		image.fill_rect(Rect2i(11, 8, 4, 4), ink)
		image.fill_rect(Rect2i(12, 9, 2, 2), Color("e7d9ae"))
	elif job == "scout":
		image.fill_rect(Rect2i(12, 4, 1, 10), wood)
	if master and job not in ["child", "teen", "settler"]:
		image.fill_rect(Rect2i(5, 10, 6, 1), Color("574e40"))
		image.fill_rect(Rect2i(8, 10, 1, 1), Color("d9bb76"))
		image.fill_rect(Rect2i(5, 7, 1, 2), Color("e0d2a5"))
	return image

static func settlement_mark(domain: String) -> ImageTexture:
	var patterns := {"food": ["..y...", ".yyy..", "..y.y.", "..yyy.", "..y...", "..y..."], "maritime": ["..w...", "..ww..", "..www.", "..b...", "bbbbbb", ".vvvv."], "engineering": [".mmmmm", "...b..", "...b..", "...b..", "...b..", "......"], "materials": ["...y..", "..yy..", ".yfy..", ".fff..", ".mmm..", "mmmmmm"], "education": ["......", "wwooww", "wwooww", "wwooww", "wwooww", "......"], "trade": [".yyyy.", "yo..oy", "yoyyoy", "yo..oy", ".yyyy.", "......"], "mixed": ["..cc..", ".cccc.", "cccccc", "cc..cc", "cc..cc", "......"]}
	return sprite_texture(patterns.get(domain, patterns.mixed))

static func house_variant(domain: String, form: int = 0) -> ImageTexture:
	var color: Color = WorldAppearanceJob.COLORS.get(domain, WorldAppearanceJob.COLORS.mixed)
	var image := sprite_image(HOUSE)
	if form == 1: image = sprite_image([".......oo.......", "......ottro.....", ".....ottttro....", "....ottttttro...", "...otttttttrro..", "..ottttttttrrro.", "oooooooooooooooo"] + HOUSE.slice(7))
	elif form == 2: image = sprite_image(["................", "................", "..oooooooooooo..", "..ottttttttrro..", "..ottttttttrro..", "..oooooooooooo..", ".oooooooooooooo."] + HOUSE.slice(7))
	image.fill_rect(Rect2i(6, 2, 3, 1), color)
	image.fill_rect(Rect2i(2, 8, 1, 3), color.darkened(0.15))
	image.fill_rect(Rect2i(12, 8, 1, 3), color.darkened(0.15))
	return ImageTexture.create_from_image(image)

static func supplies_texture(domain: String) -> ImageTexture:
	var patterns := {"food": ["........", "..ssss..", ".osssso.", ".osssso.", ".obbbbo.", "..oooo.."], "materials": ["...oo...", ".oonnoo.", ".onnnmo.", ".onmmmo.", "..oooo..", ".kkkkkk."], "maritime": [".oooooo.", "obbbbboo", "obooobbo", "obbbbooo", ".oooooo.", ".kkkkkk."], "trade": [".oooooo.", ".obbbbo.", ".obobbo.", ".obbbbo.", ".oooooo.", ".kkkkkk."]}
	return sprite_texture(patterns.get(domain, patterns.trade))
const WORKSHOP := [
	".....oooooo.....", "....ottttrro....", "...otttttrrro...", "..ottttttrrrro..",
	".oooooooooooooo.", ".obssssssssssbo.", ".obwwssooosswbo.", ".obwwssbbosswbo.",
	".obssssbbosssbo.", ".obbbbbbbbbbbbo.", ".obssbbssssbbbo.", ".oooooooooooooo.",
	"...kkkkkkkkkk..."
]
const ARCHIVE := [
	"......oooo......", ".....occcco.....", "....occcccco....", "...occcccccco...",
	"..oooooooooooo..", "..osssssssssso..", "..oswwsswwssso..", "..oswwsswwssso..",
	"..osssssssssso..", "..ossoooosssso..", "..ossobbosssso..", "..ossobbosssso..",
	"..oooooooooooo..", "...kkkkkkkkkk..."
]
const PEAK := [
	".......oo.......", "......onno......", ".....onnnmo.....", "....onwnnmmo....",
	"...onnnnmmmmo...", "..onnnnmmmmkmo..", ".onnnnmmmmkkkmo.", "onnnnmmmmkkkkkmo",
	".ommmmmmkkkkkko.", "..okkkkkkkkkko.."
]

static func sprite_image(pattern: Array, overrides: Dictionary = {}) -> Image:
	var width := 1
	for row in pattern:
		width = maxi(width, row.length())
	var image := Image.create(width, pattern.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in pattern.size():
		for x in pattern[y].length():
			var key: String = pattern[y][x]
			if key != ".":
				image.set_pixel(x, y, overrides.get(key, PALETTE.get(key, Color.WHITE)))
	return image

static func sprite_texture(pattern: Array, overrides: Dictionary = {}) -> ImageTexture:
	return ImageTexture.create_from_image(sprite_image(pattern, overrides))

static func vessel_texture(sails: bool) -> ImageTexture:
	return sprite_texture([".......b........", ".......bw.......", ".......bww......", ".......bwww.....", ".......bwwww....", ".......bwwwww...", ".......bwwwwww..", ".......bwwwwwww.", ".......boooooooo", ".......b........", "..oooooooooooo..", "...obbbbbbbbo...", "....obbbbbbo....", ".....oooooo.....", "...vvvuuuvvvv..."] if sails else ["................", "................", "................", "......oo........", ".....osso.......", ".....occo.......", ".....occo.......", "......bb........", "..oooooooooooo..", "...obbbbbbbbo...", "....obbbbbbo....", ".....oooooo.....", "...vvvuuuvvvv..."])

static func building_texture(kind: String) -> ImageTexture:
	var patterns := {
		"kiln": [".....mmm........",".....mfm........",".....mfm........","....oooooo......","...onnnnnmo.....","..onnnnnnmmo....",".onnnooonmmmo...",".onnnofonmmmo...",".onnnfffnmmmo...",".oooooooooooo...","...kkkkkkkk....."],
		"forge": ["............oo..","............mo..","..oooooooo..mo..",".ottttttrroo mo..".replace(" ",""),"oooooooooooooo..",".obsssoooossbo..",".obsssffyossbo..",".obsssssssmmbo..",".obbbsssmmmmbo..",".ooooooooooooo..","...kkkkkkkkkk..."],
		"market": ["................",".oooooooooooooo.",".orrrssrrrssrro.",".orrrssrrrssrro.",".oooooooooooooo.","..b.........b...","..b..yyy.ss.b...","..bbbbbbbbbbb...","..b.........b...","..b.........b...","..kkkkkkkkkkk..."],
		"council": ["......oooo......",".....onnnmo.....","....onnnnmmo....","...oooooooooo...","...ns..ns..mm...","...ns..ns..mm...","...ns..ns..mm...","...ns..ns..mm...","..onnnnnnnnnmo..",".onnnnnnnnnnmmo.","..kkkkkkkkkkkk.."],
		"dock": ["................",".bb........bb...",".bbbbbbbbbbbb...",".btbtbtbtbtbb...",".bbbbbbbbbbbb...",".btbtbtbtbtbb...",".bbbbbbbbbbbb...",".bb........bb...",".bb........bb...","................"],
		"loom": [".....oooooo.....","....ottttrro....","...otttttrrro...","..oooooooooooo..","..obssssssssbo..","..obbbbbbbbbbo..","..ob.cccc..bbo..","..ob.cccc..bbo..","..ob.aaaa..bbo..","..ob.cccc..bbo..","..obbbbbbbbbbo..","..ob..sss...bo..","..oooooooooooo..","...kkkkkkkkkk..."],
		"school": ["......oooo......",".....ottttro....","....otttttrro...","...oooooooooo...","...ossswwssbo...","...ossswwssbo...","...osssssssbo...","..oooooooooooo..","..bb..wwww..bb..","..bbbbbbbbbbbb..","..bb........bb..","...kkkkkkkkkk..."],
		"port": ["............b...",".......bbbbbb...",".......b....b...","...oooooo...n...","..ottttrro..n...",".oooooooooo.....",".obssswwwbo.....",".obssswwwbo.....",".obsssooobo.....",".obsssbbbbo.....",".oooooooooo.....","bbbbbbbbbbbbbbbb","btbtbtbtbtbtbtbb","bbbbbbbbbbbbbbbb",".bb..bb..bb..bb."]
	}
	if kind in ["townhouse","apartment","tower","factory","power","mill","bridge","irrigation","roadworks","plaza","embankment"]: return city_texture(kind)
	if patterns.has(kind): return sprite_texture(patterns[kind])
	if kind=="boat" or kind=="sailboat": return vessel_texture(kind=="sailboat")
	return sprite_texture(WORKSHOP,{"t":Color("bda4c8"),"r":Color("876e9b"),"s":Color("e0d1b5")})

static func idle_furnace(kind: String) -> ImageTexture:
	var image := building_texture(kind).get_image()
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color == PALETTE.f or color == PALETTE.y: image.set_pixel(x, y, Color("554e42"))
	return ImageTexture.create_from_image(image)

static func icon(key: String) -> ImageTexture:
	if key.begins_with("biome_"): return sprite_texture(TREE,{"l":WorldClimate.COLORS[int(key.trim_prefix("biome_"))],"g":WorldClimate.COLORS[int(key.trim_prefix("biome_"))].darkened(.12)})
	var patterns := {
		"atlas": ["..oooooooo..", ".osssssssso.", ".oswwwwssso.", ".oswbwwssso.", ".oswbbbwsso.", ".oswwbwwsso.", ".oswwwwssso.", ".osssssssso.", "..oooooooo.."],
		"inspect": [".ww......", ".wcw.....", ".wccw....", ".wcccw...", ".wccccw..", ".wccwwww.", ".wcww....", ".ww.wc...", ".....wc.."],
		"pan": ["...cc.cc...", "cc.cc.cc.cc", "cc.cc.cc.cc", "cc.cc.cc.cc", "cccccccccc", ".ccccccccc", "..ccccccc.", "..ccccccc.", "...ccccc.."],
		"water": [".....v.....", "....vvv....", "...vvvvv...", "..vvvuvvv..", ".vvvuuvvvv.", ".vuuuuuuuv.", "..uuuuuuu..", "...uuuuu..."],
		"sand": ["....sss....", "...sssss...", "..sssssss..", ".sssssssss.", "sssssssssss", "..t..s..t.."],
		"grass": ["..l.....l..", "..ll...ll..", "...ll.ll...", ".l..lll..l.", "..lllllll..", "...ggggg...", "....ggg...."],
		"forest": TREE,
		"mountain": PEAK,
		"person": PERSON,
		"fire": ["......y....", ".....yy....", "....yy.....", "...yyyyyy..", "..yyyyyy...", ".....yy....", "....yy.....", "...yy......", "..y........"],
		"rain": ["...cccc....", ".cccccccc..", "cccccccccc.", "cccccccccc.", "..a..a..a..", ".a..a..a...", "..a..a..a.."],
		"pause": ["ccc..ccc", "ccc..ccc", "ccc..ccc", "ccc..ccc", "ccc..ccc", "ccc..ccc", "ccc..ccc"],
		"play": ["cc......", "cccc....", "cccccc..", "cccccccc", "cccccc..", "cccc....", "cc......"],
		"save": ["cccccccccc", "coossssooc", "coossssooc", "cooooooooc", "cccccccccc", "ccwwwwwwcc", "ccwccccwcc", "ccwccccwcc", "cccccccccc"],
		"sun": ["....y....", ".y.....y.", "...yyy...", "..yyyyy..", "y.yyyyy.y", "..yyyyy..", "...yyy...", ".y.....y.", "....y...."],
		"town": HOUSE,
		"leaf": [".......ggggg", "....gggllllg", "..gglllllllg", ".gglllllllg.", "gglllhlllg..", "gllllllgg...", "gllllgg.....", ".gggg.......", "..b.........", ".b.........."],
		"fit": ["cccc..cccc", "c........c", "c........c", "c........c", "..........", "..........", "c........c", "c........c", "cccc..cccc"]
	}
	return sprite_texture(patterns.get(key, patterns.leaf), {"c": Color("c3a871"), "a": Color("8c7754")})

static func city_texture(kind: String, lit: bool = false) -> ImageTexture:
	var height := 64 if kind=="tower" else (36 if kind=="apartment" else 24)
	var image := Image.create(24,height,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var ink := Color("494d50")
	var stone := Color("d3c4a6")
	var shadow := Color("998d7d")
	var roof := Color("8a5a4c")
	var glass := Color("eec67e") if lit else Color("8aa7af")
	if kind in ["townhouse","apartment","tower"]:
		var top := 6 if kind=="tower" else 4
		image.fill_rect(Rect2i(2,top,20,height-top-2),ink)
		image.fill_rect(Rect2i(3,top+1,17,height-top-4),stone)
		image.fill_rect(Rect2i(19,top+1,2,height-top-3),shadow)
		image.fill_rect(Rect2i(1,top-2,22,3),roof if kind=="townhouse" else shadow)
		for y in range(top+3,height-7,6):
			for x in [5,10,15]:
				image.fill_rect(Rect2i(x,y,3,4),ink)
				image.fill_rect(Rect2i(x,y,2,3),glass)
			image.fill_rect(Rect2i(3,y+4,16,1),shadow)
		image.fill_rect(Rect2i(9,height-7,5,5),ink)
		image.fill_rect(Rect2i(10,height-6,2,4),Color("9d7650"))
		if kind=="tower":
			image.fill_rect(Rect2i(9,1,6,3),ink)
			image.fill_rect(Rect2i(12,0,1,3),Color("bd8865"))
	elif kind in ["factory","power","mill"]:
		image.fill_rect(Rect2i(2,11,20,11),ink)
		image.fill_rect(Rect2i(3,12,17,9),Color("b17f61") if kind=="factory" else stone)
		image.fill_rect(Rect2i(1,9,22,3),roof)
		for x in [4,10,16]: image.fill_rect(Rect2i(x,14,3,4),glass)
		if kind=="mill":
			image.fill_rect(Rect2i(10,3,3,17),Color("c9b58d"))
			image.fill_rect(Rect2i(3,7,17,2),Color("e0cd9f"))
			image.fill_rect(Rect2i(11,0,2,18),Color("e0cd9f"))
		else:
			for x in [4,16]:
				image.fill_rect(Rect2i(x,2,4,11),ink)
				image.fill_rect(Rect2i(x,3,3,8),shadow)
				image.fill_rect(Rect2i(x-1,1,6,2),roof)
			if kind=="power":
				image.fill_rect(Rect2i(10,3,1,14),Color("cdad69"))
				image.fill_rect(Rect2i(7,5,8,1),ink)
				image.fill_rect(Rect2i(9,17,5,3),glass)
	elif kind=="irrigation":
		image.fill_rect(Rect2i(1,13,22,8),shadow)
		for y in [14,18]: image.fill_rect(Rect2i(2,y,20,2),Color("65a1b2"))
		for x in [5,11,17]: image.fill_rect(Rect2i(x,14,1,6),Color("809b64"))
	elif kind=="plaza":
		image.fill_rect(Rect2i(0,5,24,19),shadow)
		for y in range(6,23,4):
			for x in range(1,23,4): image.fill_rect(Rect2i(x,y,3,3),stone)
		image.fill_rect(Rect2i(8,9,8,9),ink)
		image.fill_rect(Rect2i(9,10,6,6),Color("6a9daa"))
		image.fill_rect(Rect2i(11,6,2,8),stone)
	elif kind=="embankment":
		for y in range(9,23,4):
			image.fill_rect(Rect2i(1,y,22,3),shadow)
			for x in range(2+(y%2),22,5): image.fill_rect(Rect2i(x,y,4,2),stone)
		image.fill_rect(Rect2i(0,7,24,2),stone)
	elif kind=="bridge":
		image.fill_rect(Rect2i(2,16,20,4),shadow)
		for x in [3,8,13,18]: image.fill_rect(Rect2i(x,15,3,4),Color("c0a276"))
	else:
		image.fill_rect(Rect2i(3,18,18,4),shadow)
		for x in [4,9,14]: image.fill_rect(Rect2i(x,16,4,3),stone)
	return ImageTexture.create_from_image(image)
