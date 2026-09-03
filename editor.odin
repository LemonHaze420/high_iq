package high_iq

import "core:os"
import rl "raylib"

EDITOR_WIDTHS := [17]i32{4,4,4,4,4,5,5,5,5,5,6,6,6,6,7,7,7}
EDITOR_DEPTHS := [17]i32{2,3,4,5,6,4,5,6,7,8,6,7,8,9,7,8,9}

editor_archive_offset :: proc(game: ^Game, column, row: i32) -> int {
	return int(game.editor_dimension * 14000 + game.editor_puzzle * 70 + row * 7 + column)
}

init_editor :: proc(game: ^Game) {
	game.editor_dimension = clamp(game.editor_dimension, 0, 16)
	game.editor_puzzle = clamp(game.editor_puzzle, 0, 199)
	game.editor_cursor_x = 0
	game.editor_cursor_y = 0
	game.editor_fill_type = 0
	game.paused = false
	game.state = .Editor
}

editor_cycle_cell :: proc(game: ^Game, column, row: i32) {
	if column < 0 || column >= EDITOR_WIDTHS[game.editor_dimension] ||
			row < 0 || row >= EDITOR_DEPTHS[game.editor_dimension] { return }
	offset := editor_archive_offset(game, column, row)
	if offset < 0 || offset >= len(game.group_data) { return }
	game.group_data[offset] = (game.group_data[offset] + 1) % 3
	play_effect(.Menu_Move, game.save.sound_volume)
}

editor_fill :: proc(game: ^Game) {
	width := EDITOR_WIDTHS[game.editor_dimension]
	depth := EDITOR_DEPTHS[game.editor_dimension]
	for row: i32 = 0; row < 10; row += 1 {
		for column: i32 = 0; column < 7; column += 1 {
			offset := editor_archive_offset(game, column, row)
			if offset < len(game.group_data) {
				game.group_data[offset] = game.editor_fill_type
			}
		}
	}
	game.editor_fill_type = (game.editor_fill_type + 1) % 3
	_ = width
	_ = depth
}

editor_copy :: proc(game: ^Game) {
	base := editor_archive_offset(game, 0, 0)
	if base + 70 <= len(game.group_data) {
		copy(game.editor_clipboard[:], game.group_data[base:base + 70])
	}
}

editor_paste :: proc(game: ^Game) {
	base := editor_archive_offset(game, 0, 0)
	if base + 70 <= len(game.group_data) {
		copy(game.group_data[base:base + 70], game.editor_clipboard[:])
	}
}

save_editor_archive :: proc(game: ^Game) {
	if os.write_entire_file("IQ_STAGE_BLOCKS.NEW", game.group_data) == nil {
		set_message(game, IQ_EN_DATA_SAVED, 1.5)
	}
}

load_editor_archive :: proc(game: ^Game) {
	if data, err := os.read_entire_file("IQ_STAGE_BLOCKS.NEW", context.allocator);
			err == nil && len(data) == 238000 {
		delete(game.group_data)
		game.group_data = data
		set_message(game, IQ_EN_DATA_LOADED, 1.5)
	} else if err == nil {
		delete(data)
	}
}

play_editor_puzzle :: proc(game: ^Game) {
	width := EDITOR_WIDTHS[game.editor_dimension]
	depth := EDITOR_DEPTHS[game.editor_dimension]
	game.stage = clamp(width - 4, 0, STAGE_COUNT - 1)
	start_stage(game, game.stage)
	board := &game.board
	board.width = width
	board.remaining_rows = max(depth + 7, 12)
	board.remaining_columns = width - 1
	board.wave_rows_remaining = 0
	board.cube_count = 0
	start_row := board.remaining_rows - depth
	for row: i32 = 0; row < depth; row += 1 {
		for column: i32 = 0; column < width; column += 1 {
			value := game.group_data[editor_archive_offset(game, column, row)]
			index := board.cube_count
			cube_row := start_row + row
			board.cubes[index] = Cube{
				Cube_Type(clamp(value, 0, 2)), column, cube_row, cube_row,
				0, true, false, false, 0, 0, .Waiting, 0, 0, 0,
			}
			board.cube_count += 1
		}
	}
	board.wave_started = true
	board.roll_timer = 72.0 / 60.0
	game.player.column = width / 2
	game.player.row = 1
	game.player.position = board_world_position(board, game.player.column, game.player.row, 0.46)
	game.player.target = game.player.position
	game.editor_playtest = true
	game.state = .Playing
	game.state_time = 0
}

editor_action :: proc(game: ^Game, action: i32) {
	switch action {
	case 0: editor_fill(game)
	case 1: editor_copy(game)
	case 2: editor_paste(game)
	case 3: load_editor_archive(game)
	case 4: save_editor_archive(game)
	case 5: play_editor_puzzle(game)
	case 6: transition_to(game, .Title)
	}
}

update_editor :: proc(game: ^Game, input: Input_State, dt: f32) {
	_ = dt
	width := EDITOR_WIDTHS[game.editor_dimension]
	depth := EDITOR_DEPTHS[game.editor_dimension]
	if rl.IsKeyPressed(.LEFT) { game.editor_cursor_x = max(0, game.editor_cursor_x - 1) }
	if rl.IsKeyPressed(.RIGHT) { game.editor_cursor_x = min(width - 1, game.editor_cursor_x + 1) }
	if rl.IsKeyPressed(.UP) { game.editor_cursor_y = max(0, game.editor_cursor_y - 1) }
	if rl.IsKeyPressed(.DOWN) { game.editor_cursor_y = min(depth - 1, game.editor_cursor_y + 1) }
	if rl.IsKeyPressed(.PAGE_UP) { game.editor_puzzle = min(199, game.editor_puzzle + 1) }
	if rl.IsKeyPressed(.PAGE_DOWN) { game.editor_puzzle = max(0, game.editor_puzzle - 1) }
	if rl.IsKeyPressed(.TAB) {
		game.editor_dimension = (game.editor_dimension + 1) % 17
		game.editor_cursor_x = min(game.editor_cursor_x, EDITOR_WIDTHS[game.editor_dimension] - 1)
		game.editor_cursor_y = min(game.editor_cursor_y, EDITOR_DEPTHS[game.editor_dimension] - 1)
	}
	if input.marker { editor_cycle_cell(game, game.editor_cursor_x, game.editor_cursor_y) }
	if input.detonate {
		game.group_data[editor_archive_offset(game, game.editor_cursor_x, game.editor_cursor_y)] = 0
	}
	if input.advantage { editor_fill(game) }
	if rl.IsKeyPressed(.F2) { save_editor_archive(game) }
	if rl.IsKeyPressed(.F3) { load_editor_archive(game) }
	if input.confirm { play_editor_puzzle(game) }
	if input.pause { transition_to(game, .Title) }

	mouse := rl.GetMousePosition()
	if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
		column := i32((mouse.x - 54) / 40)
		row := i32((mouse.y - 108) / 24)
		if column >= 0 && column < width && row >= 0 && row < depth {
			game.editor_cursor_x = column
			game.editor_cursor_y = row
			if rl.IsMouseButtonPressed(.LEFT) { editor_cycle_cell(game, column, row) }
			else { game.group_data[editor_archive_offset(game, column, row)] = 0 }
		} else if mouse.x >= 400 && mouse.x < 580 && mouse.y >= 100 && mouse.y < 380 {
			editor_action(game, i32((mouse.y - 100) / 40))
		}
	}
}
