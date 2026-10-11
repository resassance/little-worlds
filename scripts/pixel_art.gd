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
		"dock": ["................",".bb........bb...",".bbbbbbbbbbbb...",".btbtbtbtbtbb...",".bbbbbbbbbbbb...",".btbtbtbtbtbb...",".bbbbbbbbbbbb...",".bb........bb...",".bb........bb...","................"]
	}
	if patterns.has(kind): return sprite_texture(patterns[kind])
	if kind=="boat" or kind=="sailboat": return vessel_texture(kind=="sailboat")
	if kind=="port": return sprite_texture(patterns.dock,{"t":Color("e5d3a3"),"b":Color("89755a")})
	if kind=="school": return sprite_texture(ARCHIVE,{"c":Color("d9c294"),"w":Color("b0d0c6")})
	return sprite_texture(WORKSHOP,{"t":Color("bda4c8"),"r":Color("876e9b"),"s":Color("e0d1b5")})

static func icon(key: String) -> ImageTexture:
	if key.begins_with("biome_"): return sprite_texture(TREE,{"l":WorldClimate.COLORS[int(key.trim_prefix("biome_"))],"g":WorldClimate.COLORS[int(key.trim_prefix("biome_"))].darkened(.12)})
	var patterns := {
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
	return sprite_texture(patterns.get(key, patterns.leaf))
