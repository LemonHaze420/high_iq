package high_iq

import "core:fmt"
import "core:os"
import rl "raylib"

asset_path :: proc(root, relative: string) -> string {
	return fmt.aprintf("%s/%s", root, relative)
}

iq_asset_root :: proc() -> string {
	return "game"
}

iq_font: rl.Font

load_iq_font :: proc(root: string) -> rl.Font {
	font: rl.Font
	font.texture = load_4b_texture(
		asset_path(root, "IQ/CG/ETC/KANA25.4B"),
		asset_path(root, "IQ/CG/ETC/KANA25.COL"),
		256, 256, 0,
	)
	if font.texture.id == 0 { return {} }
	font.baseSize = 16
	font.glyphCount = 95
	font.glyphPadding = 0
	font.recs = ([^]rl.Rectangle)(rl.MemAlloc(u32(font.glyphCount * size_of(rl.Rectangle))))
	font.glyphs = ([^]rl.GlyphInfo)(rl.MemAlloc(u32(font.glyphCount * size_of(rl.GlyphInfo))))
	for index: i32 = 0; index < font.glyphCount; index += 1 {
		atlas_index := index + 80 + (index / 16) * 16
		font.recs[index] = rl.Rectangle{
			f32((atlas_index / 16) * 16 - 8), f32((atlas_index % 16) * 16), 16, 16,
		}
		font.glyphs[index] = rl.GlyphInfo{
			value = rune(index + 32),
			advanceX = 12,
		}
	}
	return font
}

psx_color :: proc(value: u16, transparent: bool = false) -> rl.Color {
	r := u8((value & 0x1f) * 255 / 31)
	g := u8(((value >> 5) & 0x1f) * 255 / 31)
	b := u8(((value >> 10) & 0x1f) * 255 / 31)
	a := u8(255)
	if transparent && value & 0x7fff == 0 {
		a = 0
	}
	return rl.Color{r, g, b, a}
}

load_bgr555_texture :: proc(path: string, width, height: i32) -> rl.Texture2D {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil || len(data) < int(width * height * 2) {
		return {}
	}
	defer delete(data)
	image := rl.GenImageColor(width, height, rl.BLACK)
	for y: i32 = 0; y < height; y += 1 {
		for x: i32 = 0; x < width; x += 1 {
			offset := int((y * width + x) * 2)
			value := u16(data[offset]) | u16(data[offset + 1]) << 8
			rl.ImageDrawPixel(&image, x, y, psx_color(value))
		}
	}
	texture := rl.LoadTextureFromImage(image)
	rl.UnloadImage(image)
	return texture
}

load_4b_texture :: proc(texture_path, palette_path: string, width, height: i32, palette_index: i32 = 0) -> rl.Texture2D {
	pixels, pixel_err := os.read_entire_file(texture_path, context.allocator)
	palette, palette_err := os.read_entire_file(palette_path, context.allocator)
	if pixel_err != nil || palette_err != nil || len(pixels) < int(width * height / 2) || len(palette) < int((palette_index + 1) * 32) {
		if pixel_err == nil { delete(pixels) }
		if palette_err == nil { delete(palette) }
		return {}
	}
	defer delete(pixels)
	defer delete(palette)
	colors: [16]rl.Color
	palette_start := int(palette_index * 32)
	for index in 0..<16 {
		offset := palette_start + index * 2
		value := u16(palette[offset]) | u16(palette[offset + 1]) << 8
		colors[index] = psx_color(value, true)
	}
	image := rl.GenImageColor(width, height, rl.BLANK)
	for y: i32 = 0; y < height; y += 1 {
		for x: i32 = 0; x < width; x += 1 {
			packed := pixels[int((y * width + x) / 2)]
			index := packed & 0x0f
			if x & 1 != 0 { index = packed >> 4 }
			rl.ImageDrawPixel(&image, x, y, colors[index])
		}
	}
	texture := rl.LoadTextureFromImage(image)
	rl.UnloadImage(image)
	return texture
}
load_4b_region :: proc(texture_path, palette_path: string, source_x, source_y, width, height: i32) -> rl.Texture2D {
	pixels, pixel_err := os.read_entire_file(texture_path, context.allocator)
	palette, palette_err := os.read_entire_file(palette_path, context.allocator)
	if pixel_err != nil || palette_err != nil || len(pixels) < 256 * 256 / 2 || len(palette) < 32 {
		if pixel_err == nil { delete(pixels) }
		if palette_err == nil { delete(palette) }
		return {}
	}
	defer delete(pixels)
	defer delete(palette)
	colors: [16]rl.Color
	for index in 0..<16 {
		value := u16(palette[index * 2]) | u16(palette[index * 2 + 1]) << 8
		colors[index] = psx_color(value, index == 0)
	}
	image := rl.GenImageColor(width, height, rl.BLANK)
	for y: i32 = 0; y < height; y += 1 {
		for x: i32 = 0; x < width; x += 1 {
			atlas_x := source_x + x
			atlas_y := source_y + y
			packed := pixels[int((atlas_y * 256 + atlas_x) / 2)]
			color_index := packed & 0x0f
			if atlas_x & 1 != 0 { color_index = packed >> 4 }
			rl.ImageDrawPixel(&image, x, y, colors[color_index])
		}
	}
	texture := rl.LoadTextureFromImage(image)
	rl.SetTextureFilter(texture, .POINT)
	rl.UnloadImage(image)
	return texture
}

load_palette_color :: proc(path: string, index: int, fallback: rl.Color) -> rl.Color {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil || len(data) < (index + 1) * 2 {
		if err == nil { delete(data) }
		return fallback
	}
	defer delete(data)
	value := u16(data[index * 2]) | u16(data[index * 2 + 1]) << 8
	return psx_color(value)
}


load_cube_textures :: proc(game: ^Game, style: i32) -> bool {
	style_index := clamp(style, 0, 4)
	pixels, pixels_err := os.read_entire_file(
		asset_path(game.assets.root, fmt.aprintf("IQ/CG/TILE/TILE_%02d.TEX", style_index)), context.allocator)
	palettes, palette_err := os.read_entire_file(
		asset_path(game.assets.root, fmt.aprintf("IQ/CG/TILE/TILE_%02d.COL", style_index)), context.allocator)
	if pixels_err != nil || palette_err != nil {
		if pixels_err == nil { delete(pixels) }
		if palette_err == nil { delete(palettes) }
		return false
	}
	defer delete(pixels)
	defer delete(palettes)
	// first three 32x32 images and CLUTs contain the normal, advantage, and
	// forbidden cube faces; the remaining images contain animation frames.
	for cube_type in 0..<3 {
		palette: [256]rl.Color
		for index in 0..<256 {
			offset := cube_type * 0x200 + index * 2
			value := u16(palettes[offset]) | u16(palettes[offset + 1]) << 8
			palette[index] = psx_color(value, index == 0)
		}
		image := rl.GenImageColor(32, 32, rl.BLANK)
		for y in 0..<32 {
			for x in 0..<32 {
				offset := cube_type * 0x400 + y * 32 + x
				rl.ImageDrawPixel(&image, i32(x), i32(y), palette[pixels[offset]])
			}
		}
		game.assets.cube_textures[cube_type] = rl.LoadTextureFromImage(image)
		rl.SetTextureFilter(game.assets.cube_textures[cube_type], .POINT)
		rl.UnloadImage(image)
	}
	return true
}

set_cube_style_assets :: proc(game: ^Game, style: i32) -> bool {
	for index in 0..<3 {
		if game.assets.cube_models[index].meshCount > 0 {
			rl.UnloadModel(game.assets.cube_models[index])
			game.assets.cube_models[index] = {}
		}
		if game.assets.cube_textures[index].id != 0 {
			rl.UnloadTexture(game.assets.cube_textures[index])
			game.assets.cube_textures[index] = {}
		}
	}
	if !load_cube_textures(game, style) { return false }
	for index in 0..<3 {
		game.assets.cube_models[index] = make_cube_model(game.assets.cube_textures[index])
	}
	return true
}

load_assets :: proc(game: ^Game) -> bool {
	game.assets.root = iq_asset_root()
	game.assets.trademark = load_bgr555_texture(asset_path(game.assets.root, "IQ/CG/TRADE.15B"), 640, 240)
	game.assets.title = load_bgr555_texture(asset_path(game.assets.root, "IQ/CG/ETC/TITLEIQ.15B"), 640, 240)
	game.assets.warning_1 = load_bgr555_texture(asset_path(game.assets.root, "IQ/CG/WARNING1.15B"), 640, 256)
	game.assets.warning_2 = load_bgr555_texture(asset_path(game.assets.root, "IQ/CG/WARNING2.15B"), 640, 256)
	game.assets.player_select = load_4b_texture(
		asset_path(game.assets.root, "IQ/CG/SELECT/SEL_A.TEX"),
		asset_path(game.assets.root, "IQ/CG/SELECT/SEL.COL"), 256, 4096, 0)
	iq_font = load_iq_font(game.assets.root)
	fallbacks := [5]rl.Color{
		rl.Color{56, 72, 91, 255}, rl.Color{72, 64, 94, 255}, rl.Color{49, 78, 73, 255},
		rl.Color{89, 66, 48, 255}, rl.Color{73, 73, 73, 255},
	}
	for index in 0..<5 {
		path := asset_path(game.assets.root, fmt.aprintf("IQ/CG/TILE/TILE_%02d.COL", index))
		game.assets.tile_colors[index] = load_palette_color(path, 23, fallbacks[index])
	}
	model_names := [3]string{"TEST00.YMD", "TEST02.YMD", "TEST01.YMD"}
	for index in 0..<3 {
		game.assets.player_models[index] = load_ymd_model(
			asset_path(game.assets.root, fmt.aprintf("IQ/MODEL/%s", model_names[index])))
	}
	for frame in 0..<15 {
		game.assets.marker_textures[frame] = load_4b_region(
			asset_path(game.assets.root, "IQ/CG/ETC/IQANM0.4B"),
			asset_path(game.assets.root, "IQ/CG/ETC/IQANM0.COL"),
			i32((frame & 7) * 32), i32((frame >> 3) * 32), 32, 32)
		game.assets.marker_models[frame] = make_marker_model(game.assets.marker_textures[frame])
	}
	if !set_cube_style_assets(game, game.texture_style) { return false }
	group_path := asset_path(game.assets.root, "IQ/ENEMY/GROUP.NEW")
	if group, err := os.read_entire_file(group_path, context.allocator); err == nil {
		game.group_data = group
	}
	demo_path := asset_path(game.assets.root, "IQ/PLAYER/DEMO_00.DAT")
	if demo, err := os.read_entire_file(demo_path, context.allocator); err == nil {
		game.demo_data = demo
	}
	if mdec_load_tables(game.assets.root) {
		_ = load_movie(game, "IQ/STR/OPENING.STR")
	}
	game.assets.loaded = game.assets.trademark.id != 0 && len(game.group_data) > 0
	return game.assets.loaded
}

unload_assets :: proc(game: ^Game) {
	if iq_font.texture.id != 0 {
		rl.UnloadFont(iq_font)
		iq_font = {}
	}
	textures := []rl.Texture2D{
		game.assets.trademark, game.assets.title, game.assets.warning_1,
		game.assets.warning_2, game.assets.player_select,
	}
	for texture in textures {
		if texture.id != 0 { rl.UnloadTexture(texture) }
	}
	for index in 0..<3 { unload_ymd_model(&game.assets.player_models[index]) }
	for index in 0..<3 {
		if game.assets.cube_models[index].meshCount > 0 {
			rl.UnloadModel(game.assets.cube_models[index])
		}
	}
	for texture in game.assets.cube_textures {
		if texture.id != 0 { rl.UnloadTexture(texture) }
	}
	for index in 0..<15 {
		if game.assets.marker_models[index].meshCount > 0 { rl.UnloadModel(game.assets.marker_models[index]) }
		if game.assets.marker_textures[index].id != 0 { rl.UnloadTexture(game.assets.marker_textures[index]) }
	}
	if game.movie_texture.id != 0 { rl.UnloadTexture(game.movie_texture) }
	if game.group_data != nil { delete(game.group_data) }
	if game.demo_data != nil { delete(game.demo_data) }
	if game.movie_data != nil { delete(game.movie_data) }
}
