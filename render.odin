package high_iq

import "core:fmt"
import "core:math"
import rl "raylib"

iq_text_bytes :: proc(text: cstring) -> [^]u8 {
	return transmute([^]u8)text
}

iq_glyph_source :: proc(value: u8) -> rl.Rectangle {
	code := clamp(i32(value), 32, 126)
	index := code - 32
	atlas_index := index + 80 + (index / 16) * 16
	return rl.Rectangle{
		f32((atlas_index / 16) * 16 - 8), f32((atlas_index % 16) * 16), 16, 16,
	}
}

iq_measure_text :: proc(text: cstring, size: i32) -> i32 {
	if iq_font.texture.id == 0 { return rl.MeasureText(text, size) }
	bytes := iq_text_bytes(text)
	count: i32
	for bytes[count] != 0 { count += 1 }
	return i32(f32(count * size) * 0.75)
}

iq_draw_text :: proc(text: cstring, x, y, size: i32, color: rl.Color) {
	if iq_font.texture.id == 0 {
		rl.DrawText(text, x, y, size, color)
		return
	}
	bytes := iq_text_bytes(text)
	advance := f32(size) * 0.75
	for index: i32 = 0; bytes[index] != 0; index += 1 {
		source := iq_glyph_source(bytes[index])
		destination := rl.Rectangle{f32(x) + f32(index) * advance, f32(y), f32(size), f32(size)}
		rl.DrawTexturePro(iq_font.texture, source, destination, {}, 0, color)
	}
}

center_text :: proc(text: cstring, y, size: i32, color: rl.Color) {
	width := iq_measure_text(text, size)
	iq_draw_text(text, (INTERNAL_WIDTH - width) / 2, y, size, color)
}

draw_full_texture :: proc(texture: rl.Texture2D, tint: rl.Color = rl.WHITE) {
	if texture.id == 0 { return }
	source := rl.Rectangle{0, 0, f32(texture.width), f32(texture.height)}
	destination := rl.Rectangle{0, 0, INTERNAL_WIDTH, INTERNAL_HEIGHT}
	rl.DrawTexturePro(texture, source, destination, {}, 0, tint)
}

draw_trademark :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	if game.state_time < 2 {
		draw_full_texture(game.assets.warning_1)
	} else if game.state_time < 4 {
		draw_full_texture(game.assets.warning_2)
	} else {
		draw_full_texture(game.assets.trademark)
	}
}
draw_movie :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	if game.movie_frames <= 0 { return }
	target := clamp(i32(game.state_time * 15) + 1, 1, game.movie_frames)
	_ = movie_decode_frame(game, target)
	if game.movie_texture.id != 0 {
		source := rl.Rectangle{0, 0, f32(game.movie_texture.width), f32(game.movie_texture.height)}
		destination := rl.Rectangle{0, 0, INTERNAL_WIDTH, INTERNAL_HEIGHT}
		rl.DrawTexturePro(game.movie_texture, source, destination, {}, 0, rl.WHITE)
	}
}

draw_opening :: proc(game: ^Game) {
	draw_movie(game)
}


draw_title :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	draw_full_texture(game.assets.title)
	if game.assets.player_select.id == 0 { return }
	positions := [4]rl.Vector2{{40, 80}, {335, 80}, {40, 240}, {335, 240}}
	for choice: i32 = 0; choice < 4; choice += 1 {
		selected := game.menu_index == choice
		x := i32(positions[choice].x)
		y := i32(positions[choice].y)
		if selected {
			rl.DrawRectangle(x - 3, y - 12, 268, 140, rl.Color{240, 128, 128, 255})
		} else {
			rl.DrawRectangle(x - 1, y - 4, 260, 132, rl.Color{192, 192, 192, 255})
		}
		source := rl.Rectangle{0, f32(choice * 16 * 64), 256, 64}
		destination := rl.Rectangle{f32(x), f32(y), 256, 128}
		rl.DrawTexturePro(game.assets.player_select, source, destination, {}, 0, rl.Color{255, 255, 255, 128})
	}
}

draw_panel :: proc(x, y, width, height: i32) {
	rl.DrawRectangle(x, y, width, height, rl.Fade(rl.BLACK, 0.76))
	rl.DrawRectangleLines(x, y, width, height, rl.Color{78, 155, 224, 255})
}

draw_menu_item :: proc(text: string, x, y: i32, selected: bool) {
	color := rl.LIGHTGRAY
	if selected {
		rl.DrawRectangle(x - 18, y - 4, 284, 30, rl.Fade(rl.BLUE, 0.42))
		color = rl.WHITE
		iq_draw_text(IQ_EN_CURSOR, x - 13, y, 21, rl.YELLOW)
	}
	iq_draw_text(fmt.ctprintf(IQ_EN_FMT_STRING, text), x, y, 21, color)
}


draw_mode_select :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	iq_draw_text(IQ_EN_GAME, 40, 40, 24, rl.WHITE)
	iq_draw_text(IQ_EN_MODE, 40, 64, 24, rl.WHITE)
	system := IQ_EN_NORMAL
	if game.mode == .Original { system = IQ_EN_ORIGINAL }
	draw_menu_item(IQ_EN_SYSTEM, 80, 160, game.menu_index == 0)
	iq_draw_text(fmt.ctprintf(IQ_EN_FMT_STRING, system), 320, 160, 21, rl.WHITE)
	draw_menu_item(IQ_EN_LEVEL, 80, 220, game.menu_index == 1)
	for level: i32 = 0; level < 5; level += 1 {
		color := rl.GRAY
		if game.speed_level == level { color = rl.WHITE }
		iq_draw_text(fmt.ctprintf(IQ_EN_FMT_LEVEL, level), 320 + level * 50, 220, 21, color)
	}
	draw_menu_item(IQ_EN_EXIT, 40, 360, game.menu_index == 2)
}
draw_two_player_select :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	if game.assets.player_select.id != 0 {
		source := rl.Rectangle{0, 16 * 64, 256, 64}
		destination := rl.Rectangle{192, 64, 256, 128}
		rl.DrawTexturePro(game.assets.player_select, source, destination, {}, 0, rl.Color{255, 255, 255, 128})
	}
	draw_menu_item(IQ_EN_LEVEL, 80, 240, game.menu_index == 0)
	for level: i32 = 0; level < 5; level += 1 {
		color := rl.GRAY
		if game.speed_level == level { color = rl.WHITE }
		iq_draw_text(fmt.ctprintf(IQ_EN_FMT_LEVEL, level), 320 + level * 50, 240, 21, color)
	}
	draw_menu_item(IQ_EN_EXIT, 80, 360, game.menu_index == 1)
}
draw_two_player_round_end :: proc(game: ^Game) {
	draw_gameplay(game)
	rl.DrawRectangle(96, 150, 448, 180, rl.Color{0, 0, 0, 232})
	result := IQ_EN_FAILED
	if game.two_player_round_clear { result = IQ_EN_POINT }
	center_text(fmt.ctprintf(IQ_EN_FMT_PLAYER_RESULT, game.active_player + 1, result), 182, 30, rl.WHITE)
	center_text(fmt.ctprintf(IQ_EN_FMT_TWO_PLAYER_SCORE, game.player_wins[0], game.player_wins[1]), 244, 25, rl.YELLOW)
}

draw_two_player_match_end :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	if game.player_wins[0] == game.player_wins[1] {
		center_text(IQ_EN_DRAW, 150, 52, rl.WHITE)
	} else {
		winner := 1
		if game.player_wins[1] > game.player_wins[0] { winner = 2 }
		center_text(fmt.ctprintf(IQ_EN_FMT_PLAYER_WINS, winner), 150, 52, rl.YELLOW)
	}
	center_text(fmt.ctprintf(IQ_EN_FMT_MATCH_SCORE, game.player_wins[0], game.player_wins[1]), 242, 38, rl.WHITE)
	center_text(IQ_EN_PRESS_START, 360, 18, rl.GRAY)
}


draw_rules :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	labels := IQ_EN_RULE_LABELS
	for index: i32 = 0; index < 7; index += 1 {
		y := 66 + index * 40
		if index == 6 { y = 346 }
		draw_menu_item(labels[index], 345, y, game.menu_index == index)
	}
}

draw_controller :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	iq_draw_text(IQ_EN_CONTROLLER, 40, 40, 28, rl.WHITE)
	labels := IQ_EN_CONTROLLER_LABELS
	button_names := IQ_EN_BUTTON_NAMES
	for index: i32 = 0; index < 6; index += 1 {
		y := 98 + index * 48
		if index == 4 { y = 360 }
		if index == 5 { y = 408 }
		draw_menu_item(labels[index], 105, y, game.menu_index == index)
		if index < 4 {
			button := game.save.button_mapping[index]
			iq_draw_text(fmt.ctprintf(IQ_EN_FMT_STRING, button_names[button]), 385, y, 21, rl.WHITE)
		}
	}
}

draw_continue :: proc(game: ^Game) {
	draw_game_over(game)
	rl.DrawRectangle(128, 315, 384, 105, rl.Color{8, 11, 18, 235})
	center_text(IQ_EN_CONTINUE_PROMPT, 330, 22, rl.WHITE)
	draw_menu_item(IQ_EN_YES, 224, 374, game.menu_index == 0)
	draw_menu_item(IQ_EN_NO, 374, 374, game.menu_index == 1)
}

draw_pause :: proc(game: ^Game) {
	draw_gameplay(game)
	rl.DrawRectangle(0, 0, INTERNAL_WIDTH, INTERNAL_HEIGHT, rl.Fade(rl.BLACK, 0.54))
	draw_panel(138, 142, 364, 224)
	draw_menu_item(fmt.tprintf(IQ_EN_FMT_CAMERA, game.camera_mode + 1), 184, 174, game.menu_index == 0)
	draw_menu_item(IQ_EN_RESUME, 184, 220, game.menu_index == 1)
	draw_menu_item(IQ_EN_START_OVER, 184, 266, game.menu_index == 2)
	draw_menu_item(IQ_EN_QUIT, 184, 312, game.menu_index == 3)
	if game.confirmation_active {
		rl.DrawRectangle(130, 128, 380, 180, rl.Color{0, 0, 0, 242})
		label := IQ_EN_QUIT_PROMPT
		if game.menu_index == 2 { label = IQ_EN_START_OVER_PROMPT }
		center_text(fmt.ctprintf(IQ_EN_FMT_STRING, label), 168, 25, rl.WHITE)
		draw_menu_item(IQ_EN_YES, 202, 236, game.confirmation_index == 0)
		draw_menu_item(IQ_EN_NO, 366, 236, game.confirmation_index == 1)
	}
}

draw_score_display :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	center_text(IQ_EN_SCORE, 142, 64, rl.Color{224, 224, 224, 255})
	center_text(fmt.ctprintf(IQ_EN_FMT_SCORE, game.score), 214, 52, rl.WHITE)
	center_text(IQ_EN_IQ, 292, 64, rl.Color{224, 224, 224, 255})
	center_text(fmt.ctprintf(IQ_EN_FMT_IQ_VALUE, game.iq), 356, 72, rl.WHITE)
}


cube_color :: proc(kind: Cube_Type) -> rl.Color {
	switch kind {
	case .Normal: return rl.Color{56, 78, 105, 255}
	case .Advantage: return rl.Color{42, 188, 117, 255}
	case .Forbidden: return rl.Color{30, 28, 31, 255}
	}
	return rl.GRAY
}

cube_render_transform :: proc(board: ^Board, cube: ^Cube) -> (rl.Vector3, f32) {
	position := board_world_position(board, cube.column, cube.row, 0.55)
	angle := -90.0 * f32(cube.turns)
	if cube.behavior == .Begin_Flip || cube.behavior == .Flipping {
		theta := -f64(cube.roll_t) * math.PI * 0.5
		pivot_z := f32(cube.previous_row) - 0.5
		position.y = 0.05 + 0.5 * f32(math.cos(theta)) - 0.5 * f32(math.sin(theta))
		position.z = pivot_z + 0.5 * f32(math.sin(theta)) + 0.5 * f32(math.cos(theta))
		angle -= 90.0 * cube.roll_t
	}
	if cube.behavior == .Falling {
		position.y -= cube.fall_offset
		angle += cube.spin
	}
	return position, angle
}

draw_board_3d :: proc(game: ^Game) {
	board := &game.board
	shake_x := f32(0)
	if game.camera_shake > 0 { shake_x = f32(math.sin(f64(game.state_time * 85))) * game.camera_shake * 0.13 }
	camera_position := game.camera_position
	camera_position.x += shake_x
	camera := rl.Camera3D{
		position = camera_position,
		target = game.camera_target,
		up = rl.Vector3{0, 1, 0},
		fovy = 42,
		projection = .PERSPECTIVE,
	}
	rl.BeginMode3D(camera)
	visible_rows := board.remaining_rows
	base_color := game.assets.tile_colors[game.stage % 5]
	for row: i32 = 0; row < visible_rows; row += 1 {
		for column: i32 = 0; column < board.width; column += 1 {
			position := board_world_position(board, column, row, -0.11)
			if game.platform_loss_timer != 0 && row == board.remaining_rows - 1 {
				frame := f32(game.platform_loss_timer)
				position.y -= frame * (frame + 1) * 3 / 300
			}
			shade := f32(0.78 + f32((row + column) & 1) * 0.12)
			color := rl.Color{u8(f32(base_color.r) * shade), u8(f32(base_color.g) * shade), u8(f32(base_color.b) * shade), 255}
			floor_model := game.assets.cube_models[0]
			rl.DrawModelEx(floor_model, position, rl.Vector3{0, 1, 0}, 0,
				rl.Vector3{0.96, 0.2, 0.96}, color)
			marker := &board.markers[row][column]
			if marker.state != .Empty {
				frame := clamp(i32(marker.pulse), 0, 14)
				marker_model := game.assets.marker_models[frame]
				tint := rl.Color{128, 128, 128, 255}
				if marker.state == .Advantage || marker.state == .Detonating {
					tint = rl.Color{0, 255, 0, 255}
				}
				rl.DrawModel(marker_model, board_world_position(board, column, row, 0.015), 1, tint)
			}
		}
	}
	for index: i32 = 0; index < board.cube_count; index += 1 {
		cube := &board.cubes[index]
		if !cube.active { continue }
		position, angle := cube_render_transform(board, cube)
		scale := rl.Vector3{0.9, 0.9, 0.9}
		if cube.captured {
			// original clips cube vertices upward by 21 units per capture frame;
			// this bottom-anchored scale reaches zero after 15 frames.
			visible := clamp(1 - f32(game.capture_timer) / 15, 0, 1)
			scale.y *= visible
			position.y = 0.1 + 0.45 * visible
		}
		model := game.assets.cube_models[int(cube.kind)]
		if scale.y > 0 {
			rl.DrawModelEx(model, position, rl.Vector3{1, 0, 0}, angle, scale, rl.WHITE)
		}
	}
	if game.platform_loss_timer > 0 && game.platform_loss_timer < 30 {
		phase := f32(game.platform_loss_timer)
		height: f32
		if phase < 6 { height = phase * 1.8 / 6 }
		else { height = (30 - phase) * 1.8 / 24 }
		if height > 0 {
			rl.DrawCube(rl.Vector3{0, -height * 0.5, -0.5},
				f32(board.width), height, 0.04, rl.Color{96, 96, 96, 112})
		}
	}
	if game.player.alive {
		position := game.player.position
		model := &game.assets.player_models[clamp(game.player.character, 0, 2)]
		update_ymd_model(model, game.player.animation_frame)
		if model.valid {
			position.y -= 0.46
			rl.DrawModelEx(model.model, position, rl.Vector3{0, 1, 0}, -game.player.facing,
				rl.Vector3{1, 1, 1}, rl.WHITE)
		} else {
			rl.DrawCylinder(position, 0.16, 0.23, 0.58, 12, rl.RAYWHITE)
			rl.DrawSphere(rl.Vector3{position.x, position.y + 0.43, position.z}, 0.18, rl.RAYWHITE)
		}
	}
	rl.EndMode3D()
}

draw_hud :: proc(game: ^Game) {
	rl.DrawRectangle(10, 32, 40, 40, rl.Color{192, 192, 192, 72})
	iq_draw_text(fmt.ctprintf(IQ_EN_FMT_SCORE, game.score), 54, 48, 20, rl.WHITE)
	for wave: i32 = 0; wave < WAVES_PER_STAGE; wave += 1 {
		x := 54 + wave * 32
		rl.DrawRectangleLines(x, 32, 29, 16, rl.Color{192, 192, 192, 72})
		if wave <= game.wave {
			rl.DrawRectangle(x, 32, 29, 16, rl.Color{64, 96, 255, 96})
		}
	}
	start_x := 610 - (game.board.width - 1) * 30
	for index: i32 = 0; index < game.board.width - 1; index += 1 {
		color := rl.Color{240, 240, 240, 96}
		if index >= game.board.remaining_columns { color = rl.Color{176, 48, 48, 96} }
		rl.DrawRectangle(start_x + index * 30, 438, 25, 8, color)
	}
	if game.two_player {
		iq_draw_text(fmt.ctprintf(IQ_EN_FMT_PLAYER_1_SCORE, game.player_wins[0]), 18, 18, 20,
			rl.YELLOW if game.active_player == 0 else rl.GRAY)
		iq_draw_text(fmt.ctprintf(IQ_EN_FMT_PLAYER_2_SCORE, game.player_wins[1]), 548, 18, 20,
			rl.YELLOW if game.active_player == 1 else rl.GRAY)
	}
	if game.message_time > 0 {
		text := cstring(&game.message[0])
		center_text(text, 104, 28, rl.WHITE)
	}
	if game.paused {
		draw_panel(187, 181, 266, 111)
		center_text(IQ_EN_PAUSE, 200, 38, rl.WHITE)
	}
}

draw_gameplay :: proc(game: ^Game) {
	rl.ClearBackground(rl.Color{5, 7, 11, 255})
	draw_board_3d(game)
	draw_hud(game)
}

draw_loading :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	center_text(fmt.ctprintf(IQ_EN_FMT_STAGE, game.stage + 1), 174, 58, rl.WHITE)
	center_text(fmt.ctprintf(IQ_EN_FMT_WAVE_WIDTH, game.board.width), 249, 21, rl.SKYBLUE)
	center_text(IQ_EN_NOW_LOADING, 386, 17, rl.GRAY)
}

draw_stage_clear :: proc(game: ^Game) {
	draw_gameplay(game)
	rl.DrawRectangle(0, 0, INTERNAL_WIDTH, INTERNAL_HEIGHT, rl.Fade(rl.BLACK, 0.68))
	center_text(IQ_EN_STAGE_COMPLETE, 121, 45, rl.YELLOW)
	center_text(fmt.ctprintf(IQ_EN_FMT_STAGE_SCORE, game.stage_score), 216, 25, rl.WHITE)
	center_text(fmt.ctprintf(IQ_EN_FMT_IQ, game.iq), 262, 25, rl.SKYBLUE)
	center_text(IQ_EN_PRESS_START, 360, 18, rl.LIGHTGRAY)
}

draw_game_over :: proc(game: ^Game) {
	draw_gameplay(game)
	rl.DrawRectangle(0, 0, INTERNAL_WIDTH, INTERNAL_HEIGHT, rl.Fade(rl.BLACK, 0.72))
	center_text(IQ_EN_GAME_OVER, 166, 58, rl.RED)
	center_text(fmt.ctprintf(IQ_EN_FMT_FINAL_SCORE, game.score), 257, 24, rl.WHITE)
	center_text(fmt.ctprintf(IQ_EN_FMT_IQ, game.iq), 299, 22, rl.SKYBLUE)
}

draw_rankings :: proc(game: ^Game) {
	rl.ClearBackground(rl.Color{7, 11, 18, 255})
	center_text(IQ_EN_IQ_RANKING, 25, 35, rl.WHITE)
	draw_panel(55, 78, 530, 344)
	for index: i32 = 0; index < 10; index += 1 {
		entry := &game.save.rankings[clamp(game.speed_level, 0, 4)][index]
		name := fmt.ctprintf(IQ_EN_FMT_NAME,
			entry.name[0], entry.name[1], entry.name[2], entry.name[3], entry.name[4],
			entry.name[5], entry.name[6], entry.name[7], entry.name[8], entry.name[9])
		color := rl.LIGHTGRAY
		if entry.score == game.score && entry.iq == game.iq { color = rl.YELLOW }
		iq_draw_text(fmt.ctprintf(IQ_EN_FMT_RANK, index + 1), 73, 98 + index * 30, 17, color)
		iq_draw_text(name, 112, 98 + index * 30, 17, color)
		iq_draw_text(fmt.ctprintf(IQ_EN_FMT_SCORE, entry.score), 310, 98 + index * 30, 17, color)
		iq_draw_text(fmt.ctprintf(IQ_EN_FMT_RANKING_IQ, entry.iq), 465, 98 + index * 30, 17, color)
	}
	center_text(IQ_EN_RANKING_RETURN, 446, 14, rl.GRAY)
}

draw_name_entry :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	center_text(IQ_EN_NAME_ENTRY, 28, 32, rl.WHITE)
	name := fmt.ctprintf(IQ_EN_FMT_NAME,
		game.name_entry[0], game.name_entry[1], game.name_entry[2], game.name_entry[3],
		game.name_entry[4], game.name_entry[5], game.name_entry[6], game.name_entry[7],
		game.name_entry[8], game.name_entry[9])
	characters := IQ_EN_NAME_CHARACTERS
	rl.DrawRectangle(150, 84, 340, 52, rl.Color{20, 25, 34, 255})
	center_text(name, 94, 30, rl.YELLOW)
	for row: i32 = 0; row < 3; row += 1 {
		for column: i32 = 0; column < 11; column += 1 {
			index := row * 11 + column
			label: string
			if index < 30 { label = string(characters[index:index + 1]) }
			else if index == 30 { label = IQ_EN_SPACE }
			else if index == 31 { label = IQ_EN_BACKSPACE }
			else { label = IQ_EN_END }
			x := 52 + column * 50
			y := 190 + row * 70
			if game.name_grid_x == column && game.name_grid_y == row {
				rl.DrawRectangle(x - 8, y - 8, 46, 44, rl.Color{40, 82, 150, 255})
			}
			iq_draw_text(fmt.ctprintf(IQ_EN_FMT_STRING, label), x, y, 20, rl.WHITE)
		}
	}
}

draw_options :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	labels := IQ_EN_OPTIONS_LABELS
	for index: i32 = 0; index < len(labels); index += 1 {
		y := 28 + index * 40
		draw_menu_item(labels[index], 80, y, game.menu_index == index)
		if index == 6 {
			iq_draw_text(fmt.ctprintf(IQ_EN_FMT_PERCENT, i32(game.save.music_volume * 100)), 390, y, 21, rl.WHITE)
		} else if index == 7 {
			iq_draw_text(fmt.ctprintf(IQ_EN_FMT_PERCENT, i32(game.save.sound_volume * 100)), 390, y, 21, rl.WHITE)
		} else if index == 8 {
			value := IQ_EN_OFF
			if game.save.inverted_horizontal { value = IQ_EN_ON }
			iq_draw_text(fmt.ctprintf(IQ_EN_FMT_STRING, value), 390, y, 21, rl.WHITE)
		}
	}
}

draw_memory_card :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	center_text(IQ_EN_MEMORY_CARD, 120, 42, rl.WHITE)
	center_text(IQ_EN_SAVE_DATA, 210, 28, rl.LIGHTGRAY)
	center_text(IQ_EN_PRESS_SAVE, 282, 20, rl.WHITE)
}

draw_texture_select :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)
	for index: i32 = 0; index < 5; index += 1 {
		draw_menu_item(fmt.tprintf(IQ_EN_FMT_TEXTURE, index), 160, 120 + index * 60,
			game.menu_index == index)
		rl.DrawRectangle(430, 116 + index * 60, 82, 32, game.assets.tile_colors[index])
		rl.DrawRectangleLines(430, 116 + index * 60, 82, 32, rl.GRAY)
	}
}

draw_model_viewer :: proc(game: ^Game) {
	rl.ClearBackground(rl.Color{16, 16, 20, 255})
	center_text(IQ_EN_PLAYER, 26, 38, rl.WHITE)
	camera := rl.Camera3D{
		position = {0, 1.8, 5},
		target = {0, 1, 0},
		up = {0, 1, 0},
		fovy = 45,
		projection = .PERSPECTIVE,
	}
	rl.BeginMode3D(camera)
	model := &game.assets.player_models[clamp(game.player.character, 0, 2)]
	if model.valid {
		rl.DrawModelEx(model.model, {}, {0, 1, 0}, f32(game.frame % 360), {1, 1, 1}, rl.WHITE)
	}
	rl.EndMode3D()
	center_text(IQ_EN_PRESS_EXIT, 430, 16, rl.GRAY)
}

draw_editor :: proc(game: ^Game) {
	rl.ClearBackground(rl.Color{10, 12, 16, 255})
	width := EDITOR_WIDTHS[game.editor_dimension]
	depth := EDITOR_DEPTHS[game.editor_dimension]
	iq_draw_text(fmt.ctprintf(IQ_EN_FMT_GROUP, game.editor_puzzle), 54, 34, 24, rl.WHITE)
	iq_draw_text(fmt.ctprintf(IQ_EN_FMT_DIMENSIONS, width, depth), 54, 70, 20, rl.LIGHTGRAY)
	for row: i32 = 0; row < 10; row += 1 {
		for column: i32 = 0; column < 7; column += 1 {
			x := 54 + column * 40
			y := 108 + row * 24
			valid := column < width && row < depth
			color := rl.Color{24, 26, 30, 255}
			if valid {
				value := game.group_data[editor_archive_offset(game, column, row)]
				color = cube_color(Cube_Type(clamp(value, 0, 2)))
			}
			rl.DrawRectangle(x, y, 38, 22, color)
			border := rl.Color{70, 74, 82, 255}
			if column == game.editor_cursor_x && row == game.editor_cursor_y {
				border = rl.YELLOW
			}
			rl.DrawRectangleLines(x, y, 38, 22, border)
		}
	}
	actions := IQ_EN_EDITOR_ACTIONS
	for index: i32 = 0; index < 7; index += 1 {
		draw_menu_item(actions[index], 418, 106 + index * 40, false)
	}
	iq_draw_text(IQ_EN_EDITOR_SIZE_HELP, 54, 366, 15, rl.LIGHTGRAY)
	iq_draw_text(IQ_EN_EDITOR_CYCLE_HELP, 54, 390, 15, rl.LIGHTGRAY)
	if game.message_time > 0 {
		center_text(cstring(&game.message[0]), 435, 18, rl.YELLOW)
	}
}

render_game :: proc(game: ^Game) {
	rl.BeginDrawing()
	switch game.state {
	case .Trademark: draw_trademark(game)
	case .Opening, .Ending: draw_movie(game)
	case .Title: draw_title(game)
	case .Game_Mode_Menu: draw_mode_select(game)
	case .Two_Player_Select: draw_two_player_select(game)
	case .Two_Player_Round_End: draw_two_player_round_end(game)
	case .Two_Player_Match_End: draw_two_player_match_end(game)
	case .Loading, .Next_Level: draw_loading(game)
	case .Playing, .Debug, .Capture_Success: draw_gameplay(game)
	case .Pause: draw_pause(game)
	case .Controller: draw_controller(game)
	case .Stage_Clear: draw_stage_clear(game)
	case .Game_Over: draw_game_over(game)
	case .Score_Display: draw_score_display(game)
	case .Ranking: draw_rankings(game)
	case .Name_Entry: draw_name_entry(game)
	case .Options: draw_options(game)
	case .Rules: draw_rules(game)
	case .Memory_Card: draw_memory_card(game)
	case .Texture_Select: draw_texture_select(game)
	case .Model_Viewer: draw_model_viewer(game)
	case .Continue: draw_continue(game)
	case .Editor: draw_editor(game)
	}
	if game.fade > 0.01 { rl.DrawRectangle(0, 0, INTERNAL_WIDTH, INTERNAL_HEIGHT, rl.Fade(rl.BLACK, game.fade)) }
	rl.EndDrawing()
	free_all(context.temp_allocator)
}
