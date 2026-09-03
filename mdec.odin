package high_iq

import "core:os"
import rl "raylib"

MDEC_MAX_WIDTH :: 640
MDEC_MAX_HEIGHT :: 240
MDEC_FRAME_BYTES :: 9 * 2016
MDEC_RLE_HALFWORDS :: 0x4b000 / 2

mdec_quant_y: [64]u8
mdec_quant_uv: [64]u8
mdec_scale: [64]i16
mdec_dc2: [256]u32
mdec_dc3: [256]u32
mdec_primary: [8192][2]u32
mdec_secondary: [512]u32
mdec_rle: [MDEC_RLE_HALFWORDS]u16
mdec_decoded_halfwords: int
mdec_frame: [MDEC_FRAME_BYTES]u8
mdec_rgba: [MDEC_MAX_WIDTH * MDEC_MAX_HEIGHT * 4]u8
mdec_ready: bool

mdec_u16 :: proc(data: []u8, offset: int) -> u16 {
	if offset < 0 || offset + 2 > len(data) { return 0 }
	return u16(data[offset]) | u16(data[offset + 1]) << 8
}

mdec_u32 :: proc(data: []u8, offset: int) -> u32 {
	if offset < 0 || offset + 4 > len(data) { return 0 }
	return u32(data[offset]) | u32(data[offset + 1]) << 8 |
		u32(data[offset + 2]) << 16 | u32(data[offset + 3]) << 24
}

mdec_load_tables :: proc(root: string) -> bool {
	exe, err := os.read_entire_file(asset_path(root, "SCUS_941.81"), context.allocator)
	if err != nil { return false }
	defer delete(exe)
	offset :: proc(address: u32) -> int { return 0x800 + int(address - 0x80010000) }
	quant_offset := offset(0x8005a484)
	scale_offset := offset(0x8005a508)
	dc2_offset := offset(0x8005a5cc)
	dc3_offset := offset(0x8005a9cc)
	primary_offset := offset(0x8005adcc)
	secondary_offset := offset(0x8006adcc)
	if secondary_offset + len(mdec_secondary) * 4 > len(exe) { return false }
	for index in 0..<64 {
		mdec_quant_y[index] = exe[quant_offset + index]
		mdec_quant_uv[index] = exe[quant_offset + 64 + index]
		transposed := ((index & 7) << 3) | (index >> 3)
		mdec_scale[transposed] = i16(mdec_u16(exe, scale_offset + index * 2))
	}
	for index in 0..<256 {
		mdec_dc2[index] = mdec_u32(exe, dc2_offset + index * 4)
		mdec_dc3[index] = mdec_u32(exe, dc3_offset + index * 4)
	}
	for index in 0..<8192 {
		mdec_primary[index][0] = mdec_u32(exe, primary_offset + index * 8)
		mdec_primary[index][1] = mdec_u32(exe, primary_offset + index * 8 + 4)
	}
	for index in 0..<512 {
		mdec_secondary[index] = mdec_u32(exe, secondary_offset + index * 4)
	}
	mdec_ready = true
	return true
}

mdec_rotate_halfwords :: proc(value: u32) -> u32 {
	return (value << 16) | (value >> 16)
}

Mdec_Bit_Reader :: struct {
	data: []u8,
	position: int,
}

mdec_peek_bits :: proc(reader: ^Mdec_Bit_Reader) -> u32 {
	word := reader.position >> 5
	bit_offset := reader.position & 31
	current := mdec_rotate_halfwords(mdec_u32(reader.data, 8 + word * 4))
	if bit_offset == 0 { return current }
	next := mdec_rotate_halfwords(mdec_u32(reader.data, 8 + (word + 1) * 4))
	return (current << u32(bit_offset)) | (next >> u32(32 - bit_offset))
}

mdec_consume_bits :: proc(bits: ^u32, reader: ^Mdec_Bit_Reader, count: int) {
	reader.position += count
	bits^ = mdec_peek_bits(reader)
}

mdec_vlc :: proc(input: []u8) -> bool {
	if !mdec_ready || len(input) < 16 { return false }
	mdec_rle[0] = mdec_u16(input, 0)
	mdec_rle[1] = mdec_u16(input, 2)
	cursor := 2
	reader := Mdec_Bit_Reader{data = input}
	bits := mdec_peek_bits(&reader)
	qscale := mdec_u16(input, 4) << 10
	version_three := mdec_u16(input, 6) >= 3
	dc_predictors: [3]i32
	block := 5
	if !version_three {
		mdec_rle[cursor] = qscale | u16(bits >> 22)
		cursor += 1
		mdec_consume_bits(&bits, &reader, 10)
	}
	for cursor + 3 < len(mdec_rle) {
		entry := mdec_primary[int(bits >> 19)]
		first, second := entry[0], entry[1]
		if first == 0 {
			mdec_consume_bits(&bits, &reader, 8)
			first = mdec_secondary[int(bits >> 23)]
			second = 0
		}
		mdec_consume_bits(&bits, &reader, int(first & 0xff))
		code := u16(first >> 16)
		if code == 0x7c1f {
			mdec_rle[cursor] = u16(bits >> 16)
			cursor += 1
			mdec_consume_bits(&bits, &reader, 16)
			continue
		}
		mdec_rle[cursor] = code
		cursor += 1
		block_end := code == 0xfe00
		if !block_end && second != 0 {
			low := u16(second)
			if low == 0x7c1f {
				mdec_rle[cursor] = u16(bits >> 16)
				cursor += 1
				mdec_consume_bits(&bits, &reader, 16)
			} else {
				mdec_rle[cursor] = low
				cursor += 1
				block_end = low == 0xfe00
				if !block_end {
					high := u16(second >> 16)
					if high == 0x7c1f {
						mdec_rle[cursor] = u16(bits >> 16)
						cursor += 1
						mdec_consume_bits(&bits, &reader, 16)
					} else if high != 0 {
						mdec_rle[cursor] = high
						cursor += 1
						block_end = high == 0xfe00
					}
				}
			}
		}
		if !block_end { continue }
		if !version_three {
			if bits >> 22 == 0x1ff { break }
			mdec_rle[cursor] = qscale | u16(bits >> 22)
			cursor += 1
			mdec_consume_bits(&bits, &reader, 10)
		} else {
			if bits >> 22 == 0x3ff { break }
			table := &mdec_dc2
			if block >= 3 { table = &mdec_dc3 }
			dc_entry := table[int(bits >> 24)]
			length := int(dc_entry & 0xffff)
			value_bits := int(dc_entry >> 16)
			mdec_consume_bits(&bits, &reader, length)
			delta: i32
			if value_bits != 0 {
				raw := bits >> u32(32 - value_bits)
				if i32(bits) >= 0 { raw -= 0xffffffff >> u32(32 - value_bits) }
				delta = i32(raw)
				mdec_consume_bits(&bits, &reader, value_bits)
			}
			predictor := 2
			if block == 5 { predictor = 0 }
			else if block == 4 { predictor = 1 }
			dc_predictors[predictor] += delta
			mdec_rle[cursor] = qscale | u16((dc_predictors[predictor] & 0xff) << 2)
			cursor += 1
		}
		if block == 0 { block = 5 }
		else { block -= 1 }
	}
	if cursor + 64 >= len(mdec_rle) { return false }
	for _ in 0..<64 { mdec_rle[cursor] = 0xfe00; cursor += 1 }
	mdec_decoded_halfwords = cursor
	return true
}

mdec_sign10 :: proc(value: u16) -> i32 {
	masked := i32(value & 0x3ff)
	if masked & 0x200 != 0 { masked -= 0x400 }
	return masked
}

mdec_idct :: proc(block: ^[64]i16) {
	temporary: [64]i16
	for row in 0..<8 {
		for x in 0..<8 {
			sum: i64
			for u in 0..<8 { sum += i64(block[row * 8 + u]) * i64(mdec_scale[x * 8 + u]) }
			temporary[row * 8 + x] = i16((sum + 0x4000) >> 15)
		}
	}
	for y in 0..<8 {
		for x in 0..<8 {
			sum: i64
			for v in 0..<8 { sum += i64(temporary[v * 8 + x]) * i64(mdec_scale[y * 8 + v]) }
			block[y * 8 + x] = i16(clamp(i32((sum + 0x10000) >> 17), -128, 127))
		}
	}
}

mdec_zigzag: [64]u8 = {
	0x00,0x01,0x08,0x10,0x09,0x02,0x03,0x0a,0x11,0x18,0x20,0x19,0x12,0x0b,0x04,0x05,
	0x0c,0x13,0x1a,0x21,0x28,0x30,0x29,0x22,0x1b,0x14,0x0d,0x06,0x07,0x0e,0x15,0x1c,
	0x23,0x2a,0x31,0x38,0x39,0x32,0x2b,0x24,0x1d,0x16,0x0f,0x17,0x1e,0x25,0x2c,0x33,
	0x3a,0x3b,0x34,0x2d,0x26,0x1f,0x27,0x2e,0x35,0x3c,0x3d,0x36,0x2f,0x37,0x3e,0x3f,
}

mdec_decode_block :: proc(position: ^int, quant: ^[64]u8, block: ^[64]i16) -> bool {
	block^ = {}
	for position^ < mdec_decoded_halfwords && mdec_rle[position^] == 0xfe00 { position^ += 1 }
	if position^ >= mdec_decoded_halfwords { return false }
	word := mdec_rle[position^]
	position^ += 1
	qscale := i32(word >> 10)
	coefficient := mdec_sign10(word)
	value := coefficient * i32(quant[0])
	if quant[0] == 0 { value = coefficient * 2 }
	block[0] = i16(clamp(value, -0x400, 0x3ff))
	k := 0
	for position^ < mdec_decoded_halfwords && k < 63 {
		word = mdec_rle[position^]
		position^ += 1
		if word == 0xfe00 { break }
		k += int(word >> 10) + 1
		if k >= 64 { break }
		coefficient = mdec_sign10(word)
		q := qscale * i32(quant[k])
		value = coefficient * 2
		if q != 0 { value = (coefficient * q + 4) >> 3 }
		destination := int(mdec_zigzag[k])
		if qscale == 0 { destination = k }
		block[destination] = i16(clamp(value, -0x400, 0x3ff))
	}
	mdec_idct(block)
	return true
}

mdec_channel :: proc(value: i32) -> u8 {
	return u8(clamp(value, -128, 127) + 128)
}

mdec_decode_rgba :: proc(width, height: int) -> bool {
	if width <= 0 || width > MDEC_MAX_WIDTH || height <= 0 || height > MDEC_MAX_HEIGHT { return false }
	position := 2
	rows := (height + 15) / 16
	columns := (width + 15) / 16
	for macroblock in 0..<rows * columns {
		cr, cb: [64]i16
		y_blocks: [4][64]i16
		if !mdec_decode_block(&position, &mdec_quant_uv, &cr) ||
		   !mdec_decode_block(&position, &mdec_quant_uv, &cb) ||
		   !mdec_decode_block(&position, &mdec_quant_y, &y_blocks[0]) ||
		   !mdec_decode_block(&position, &mdec_quant_y, &y_blocks[1]) ||
		   !mdec_decode_block(&position, &mdec_quant_y, &y_blocks[2]) ||
		   !mdec_decode_block(&position, &mdec_quant_y, &y_blocks[3]) { return macroblock != 0 }
		mbx := macroblock / rows
		mby := macroblock % rows
		for py in 0..<16 {
			if mby * 16 + py >= height { break }
			for px in 0..<16 {
				if mbx * 16 + px >= width { break }
				y_index := 0
				if py >= 8 { y_index += 2 }
				if px >= 8 { y_index += 1 }
				sample := i32(y_blocks[y_index][(py & 7) * 8 + (px & 7)])
				chroma := (py >> 1) * 8 + (px >> 1)
				red := sample + (359 * i32(cr[chroma]) + 0x80) >> 8
				green := sample + (((-88 * i32(cb[chroma])) & ~i32(0x1f)) +
					((-183 * i32(cr[chroma])) & ~i32(7)) + 0x80) >> 8
				blue := sample + (454 * i32(cb[chroma]) + 0x80) >> 8
				pixel := ((mby * 16 + py) * width + mbx * 16 + px) * 4
				mdec_rgba[pixel] = mdec_channel(red)
				mdec_rgba[pixel + 1] = mdec_channel(green)
				mdec_rgba[pixel + 2] = mdec_channel(blue)
				mdec_rgba[pixel + 3] = 255
			}
		}
	}
	return true
}

movie_frame_count :: proc(data: []u8) -> i32 {
	last: i32
	for sector := 0; sector + 2048 <= len(data); sector += 2048 {
		if mdec_u32(data, sector) == 0x80010160 {
			last = max(last, i32(mdec_u32(data, sector + 8)))
		}
	}
	return last
}

movie_decode_frame :: proc(game: ^Game, target: i32) -> bool {
	if !mdec_ready || target <= 0 || target == game.movie_frame { return target == game.movie_frame }
	for &value in mdec_frame { value = 0 }
	chunks := 0
	frame_size := 0
	width, height: i32
	seen: [16]bool
	for sector := 0; sector + 2048 <= len(game.movie_data); sector += 2048 {
		if mdec_u32(game.movie_data, sector) != 0x80010160 || i32(mdec_u32(game.movie_data, sector + 8)) != target { continue }
		chunk := int(mdec_u16(game.movie_data, sector + 4))
		chunks = int(mdec_u16(game.movie_data, sector + 6))
		frame_size = int(mdec_u32(game.movie_data, sector + 12))
		width = i32(mdec_u16(game.movie_data, sector + 16))
		height = i32(mdec_u16(game.movie_data, sector + 18))
		if chunk >= 0 && chunk < chunks && chunk < len(seen) {
			copy(mdec_frame[chunk * 2016:(chunk + 1) * 2016], game.movie_data[sector + 32:sector + 2048])
			seen[chunk] = true
		}
	}
	if chunks <= 0 || chunks > len(seen) || frame_size <= 0 || frame_size > len(mdec_frame) { return false }
	for chunk in 0..<chunks { if !seen[chunk] { return false } }
	if !mdec_vlc(mdec_frame[:frame_size]) || !mdec_decode_rgba(int(width), int(height)) { return false }
	if game.movie_texture.id == 0 || game.movie_texture.width != width || game.movie_texture.height != height {
		if game.movie_texture.id != 0 { rl.UnloadTexture(game.movie_texture) }
		image := rl.GenImageColor(width, height, rl.BLACK)
		game.movie_texture = rl.LoadTextureFromImage(image)
		rl.SetTextureFilter(game.movie_texture, .POINT)
		rl.UnloadImage(image)
	}
	rl.UpdateTexture(game.movie_texture, raw_data(mdec_rgba[:int(width * height * 4)]))
	game.movie_frame = target
	game.movie_width = width
	game.movie_height = height
	return true
}

load_movie :: proc(game: ^Game, relative_path: string) -> bool {
	if game.movie_data != nil { delete(game.movie_data); game.movie_data = nil }
	data, err := os.read_entire_file(asset_path(game.assets.root, relative_path), context.allocator)
	if err != nil { return false }
	game.movie_data = data
	game.movie_frame = 0
	game.movie_frames = movie_frame_count(data)
	_ = load_movie_audio(data, game.movie_frames)
	return game.movie_frames > 0 && movie_decode_frame(game, 1)
}
