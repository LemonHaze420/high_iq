package high_iq

import "core:math"
import rl "raylib"

board_world_position :: proc(board: ^Board, column, row: i32, y: f32 = 0) -> rl.Vector3 {
	x := (f32(column) - f32(board.width - 1) * 0.5) * TILE_SIZE
	z := f32(row) * TILE_SIZE
	return rl.Vector3{x, y, z}
}

iq_rand :: proc(game: ^Game) -> i32 {
	state := u32(game.rng)
	state = state * 1103515245 + 12345
	game.rng = u64(state)
	return i32((state >> 16) & 0x7fff)
}

stage_layout_bank :: proc(width, depth: i32) -> i32 {
	if width == 4 && depth >= 2 && depth <= 6 { return depth - 2 }
	if width == 5 && depth >= 4 && depth <= 8 { return depth + 1 }
	if width == 6 && depth >= 6 && depth <= 9 { return depth + 4 }
	if width == 7 && depth >= 7 && depth <= 9 { return depth + 7 }
	return -1
}

clear_board :: proc(board: ^Board) {
	for index in 0..<MAX_CUBES { board.cubes[index] = {} }
	for row in 0..<MAX_DEPTH {
		for column in 0..<MAX_WIDTH { board.markers[row][column] = {} }
	}
	board.placed_marker_active = false
	board.cube_count = 0
	board.wave_started = false
	board.wave_complete = false
	board.rolling = false
	board.roll_timer = 0
}

start_stage :: proc(
	game: ^Game, stage: i32, wave: i32 = 0, rows_override: i32 = -1,
	demo_spawn: bool = false, announce: bool = true,
) {
	game.stage = clamp(stage, 0, STAGE_COUNT - 1)
	stop_stage_music()
	if announce { play_stage_announcement(game.stage, game.save.sound_volume) }
	config := STAGES[game.stage]
	game.wave = clamp(wave, 0, i32(len(config.waves)) - 1)
	game.board = {}
	game.board.width = config.width
	game.board.depth = config.starting_rows
	game.board.remaining_rows = config.starting_rows
	if rows_override > 0 {
		game.board.depth = rows_override
		game.board.remaining_rows = rows_override
	}
	game.board.remaining_columns = config.width - 1
	game.board.stage = game.stage
	game.board.wave = game.wave
	game.board.wave_rows_remaining = config.waves[game.wave].advancements
	// original quarter-turns advance by 0x400 / 45 per frame; integer
	// truncation produces 47 rotation frames on a 72-frame cadence.
	game.board.roll_interval = 25.0 / 60.0
	game.board.roll_duration = 47.0 / 60.0
	character := game.player.character
	game.player = {}
	game.player.character = character
	spawn_offset := f32(60.0 / 600.0)
	if demo_spawn { spawn_offset = f32(2.0 / 600.0) }
	game.player.column = config.width / 2
	game.player.row = game.board.remaining_rows - config.waves[game.wave].advancements - 2
	game.player.position = rl.Vector3{
		spawn_offset,
		0.46,
		f32(game.player.row) + spawn_offset,
	}
	game.player.target = game.player.position
	game.camera_target = rl.Vector3{game.player.position.x, game.player.position.y + 1, game.player.position.z}
	game.camera_position = rl.Vector3{game.player.position.x + 3, game.player.position.y + 5, game.player.position.z - 6}
	game.player.alive = true
	set_player_animation_behavior(&game.player, 2)
	game.paused = false
	game.capture_timer = 0
	game.capture_multiplier = 0
	game.platform_loss_timer = 0
	game.platform_loss_forbidden = false

	game.stage_score = 0
	spawn_wave(game)
}

spawn_wave :: proc(game: ^Game) {
	board := &game.board
	for index in 0..<MAX_CUBES { board.cubes[index] = {} }
	board.cube_count = 0
	board.wave_started = false
	board.wave_complete = false
	board.rolling = false
	board.wave_missed = 0
	board.wave_forbidden = 0
	board.stage = game.stage
	board.wave = game.wave
	config := STAGES[game.stage].waves[game.wave]
	puzzle_depth := min(config.depth, board.wave_rows_remaining)
	bank := stage_layout_bank(board.width, puzzle_depth)
	game.current_puzzle = iq_rand(game) % 200
	game.puzzle_flipped = iq_rand(game) % 100 < 30
	if bank < 0 || len(game.group_data) < int((bank + 1) * 14000) { return }
	start_row := board.remaining_rows - board.wave_rows_remaining
	board.wave_rows_remaining -= puzzle_depth
	layout_base := bank * 14000 + game.current_puzzle * 0x46
	for depth_index: i32 = 0; depth_index < puzzle_depth; depth_index += 1 {
		for column: i32 = 0; column < board.width; column += 1 {
			source_column := column
			if game.puzzle_flipped { source_column = board.width - 1 - column }
			value := game.group_data[int(layout_base + depth_index * 7 + source_column)]
			kind := Cube_Type(clamp(value, 0, 2))
			index := board.cube_count
			row := start_row + puzzle_depth - 1 - depth_index
			board.cubes[index] = Cube{kind, column, row, row, 0, true, false, false, 0, 0, .Waiting, 0, 0, 0}
			board.cube_count += 1
		}
	}
	board.wave_started = true
	board.roll_timer = 72.0 / 60.0
	set_message(game, IQ_EN_WAVE_START, 1.2)
}
start_two_player_round :: proc(game: ^Game) {
	widths := [5]i32{4, 5, 6, 7, 7}
	rows := [5]i32{18, 26, 27, 28, 28}
	base_depths := [5]i32{4, 6, 7, 7, 7}
	stage_for_level := [5]i32{0, 2, 4, 6, 6}
	level := clamp(game.speed_level, 0, 4)
	puzzle_depth := base_depths[level] + min(game.two_player_rounds_cleared, 2)
	board := &game.board
	board^ = {}
	board.width = widths[level]
	board.depth = rows[level]
	board.remaining_rows = rows[level]
	board.remaining_columns = board.width - 1
	board.wave_rows_remaining = 0
	board.stage = stage_for_level[level]
	game.stage = board.stage
	game.wave = 0
	game.current_puzzle = iq_rand(game) % 200
	game.puzzle_flipped = false
	bank := stage_layout_bank(board.width, puzzle_depth)
	layout_base := bank * 14000 + game.current_puzzle * 0x46
	start_row := board.remaining_rows - puzzle_depth
	if bank >= 0 && int(layout_base + 0x46) <= len(game.group_data) {
		for depth_index: i32 = 0; depth_index < puzzle_depth; depth_index += 1 {
			for column: i32 = 0; column < board.width; column += 1 {
				value := game.group_data[int(layout_base + depth_index * 7 + column)]
				cube_row := start_row + puzzle_depth - 1 - depth_index
				board.cubes[board.cube_count] = Cube{
					Cube_Type(clamp(value, 0, 2)), column, cube_row, cube_row,
					0, true, false, false, 0, 0, .Waiting, 0, 0, 0,
				}
				board.cube_count += 1
			}
		}
	}
	board.wave_started = true
	board.roll_timer = 72.0 / 60.0
	game.player = {}
	game.player.character = game.active_player
	game.player.column = board.width / 2
	game.player.row = start_row - 2
	game.player.position = board_world_position(board, game.player.column, game.player.row, 0.46)
	game.player.target = game.player.position
	game.player.alive = true
	set_player_animation_behavior(&game.player, 2)
	game.camera_target = rl.Vector3{game.player.position.x, game.player.position.y + 1, game.player.position.z}
	game.camera_position = rl.Vector3{game.player.position.x + 3, game.player.position.y + 5, game.player.position.z - 6}
	game.capture_timer = 0
	game.platform_loss_timer = 0
	game.two_player_round_clear = false
	set_message(game, IQ_EN_PLAYER_1 if game.active_player == 0 else IQ_EN_PLAYER_2, 1.2)
}

two_player_match_complete :: proc(game: ^Game) -> bool {
	first, second := game.player_wins[0], game.player_wins[1]
	if first == 10 && second == 10 { return true }
	leader := max(first, second)
	trailer := min(first, second)
	return leader >= 5 && leader - trailer >= 2
}

finish_two_player_round :: proc(game: ^Game, cleared: bool) {
	game.two_player_round_clear = cleared
	if cleared {
		game.player_wins[game.active_player] += 1
		game.two_player_rounds_cleared += 1
	}
	transition_to(game, .Two_Player_Round_End)
}

set_message :: proc(game: ^Game, text: string, duration: f32) {
	game.message = {}
	game.message_len = min(len(text), len(game.message) - 1)
	copy(game.message[:game.message_len], transmute([]u8)text)
	game.message_time = duration
}

lose_platform_row :: proc(game: ^Game, forbidden: bool) {
	if game.platform_loss_timer != 0 { return }
	game.platform_loss_timer = 1
	game.platform_loss_forbidden = forbidden
	game.camera_shake = 0.55
	play_effect(.Platform_Loss, game.save.sound_volume)
	if forbidden { set_message(game, IQ_EN_FORBIDDEN, 1.5) }
	else { set_message(game, IQ_EN_MISSED, 1.2) }
}
register_missed_cube :: proc(game: ^Game) {
	board := &game.board
	board.wave_missed += 1
	if board.remaining_columns < 1 {
		lose_platform_row(game, false)
		board.remaining_columns = board.width
	}
	board.remaining_columns -= 1
}
award_perfect_puzzle :: proc(game: ^Game) {
	if game.attract || game.two_player || game.editor_playtest ||
			game.board.wave_missed != 0 || game.board.wave_forbidden != 0 {
		return
	}
	game.score += 5000
	game.stage_score += 5000
	set_message(game, IQ_EN_PERFECT, 2)
}



capture_at_markers :: proc(game: ^Game, advantage_blast: bool) {
	board := &game.board
	captured, safe_captured, points: i32
	for index: i32 = 0; index < board.cube_count; index += 1 {
		cube := &board.cubes[index]
		if !cube.active || cube.falling || cube.row < 0 || cube.row >= MAX_DEPTH { continue }
		marker := &board.markers[cube.row][cube.column]
		if marker.state != .Detonating { continue }
		cube.captured = true
		captured += 1
		switch cube.kind {
		case .Normal:
			board.captured_normal += 1
			points += 100
			safe_captured += 1
		case .Advantage:
			board.captured_advantage += 1
			points += 100
			marker.state = .Advantage
			safe_captured += 1
		case .Forbidden:
			board.captured_forbidden += 1
			board.wave_forbidden += 1
			lose_platform_row(game, true)
			board.remaining_columns = board.width - 1
		}
	}
	if captured > 0 {
		game.combo = safe_captured
		multiplier: i32 = 1
		if advantage_blast { multiplier = 2 }
		award := points * multiplier
		game.score += award
		game.stage_score += award
		play_effect(.Capture, game.save.sound_volume)
		game.capture_timer = 1
		if safe_captured > 3 { set_message(game, IQ_EN_MULTIPLE_HITS, 1.0) }
	} else if !advantage_blast {
		game.combo = 0
	}
	for row in 0..<MAX_DEPTH {
		for column in 0..<MAX_WIDTH {
			marker := &board.markers[row][column]
			if marker.state == .Detonating { marker.state = .Empty }
		}
	}
}

place_marker :: proc(game: ^Game) {
	board := &game.board
	if board.placed_marker_active { return }
	marker := &board.markers[game.player.row][game.player.column]
	if marker.state == .Empty {
		marker.state = .Armed
		board.placed_marker_active = true
		play_effect(.Marker_Set, game.save.sound_volume)
	}
}

detonate_markers :: proc(game: ^Game) {
	for row in 0..<MAX_DEPTH {
		for column in 0..<MAX_WIDTH {
			marker := &game.board.markers[row][column]
			if marker.state == .Armed { marker.state = .Detonating }
		}
	}
	game.board.placed_marker_active = false
	game.capture_multiplier = 1
}

detonate_advantage :: proc(game: ^Game) {
	board := &game.board
	found := false
	for row: i32 = 0; row < MAX_DEPTH; row += 1 {
		for column: i32 = 0; column < MAX_WIDTH; column += 1 {
			if board.markers[row][column].state != .Advantage { continue }
			found = true
			board.markers[row][column].state = .Empty
			for dz: i32 = -1; dz <= 1; dz += 1 {
				for dx: i32 = -1; dx <= 1; dx += 1 {
					r := row + dz
					c := column + dx
					if r >= 0 && r < MAX_DEPTH && c >= 0 && c < board.width && board.markers[r][c].state == .Empty {
						board.markers[r][c].state = .Detonating
					}
				}
			}
		}
	}
	if found {
		play_effect(.Advantage, game.save.sound_volume)
		game.capture_multiplier = 2
	}
}

player_overlaps_cube :: proc(game: ^Game, position: rl.Vector3, cube: ^Cube) -> bool {
	if !cube.active || cube.captured || cube.falling { return false }
	cube_position, _ := cube_render_transform(&game.board, cube)
	return abs(position.x - cube_position.x) < 0.46 &&
		abs(position.z - cube_position.z) < 0.46
}

player_position_blocked :: proc(game: ^Game, position: rl.Vector3) -> bool {
	for index: i32 = 0; index < game.board.cube_count; index += 1 {
		cube := &game.board.cubes[index]
		if cube.behavior == .Waiting && player_overlaps_cube(game, position, cube) { return true }
	}
	return false
}
player_crushed_by_cube :: proc(game: ^Game, cube: ^Cube) -> bool {
	return cube.behavior == .Waiting &&
		player_overlaps_cube(game, game.player.position, cube)
}


move_player :: proc(game: ^Game, input: Input_State, dt: f32) {
	_ = dt
	player := &game.player
	if player.animation_behavior != 2 && player.animation_behavior != 3 { return }
	dx, dz: f32
	if game.attract {
		if input.left { dx = -1 }
		if input.right { dx = 1 }
	} else {
		if input.left { dx = 1 }
		if input.right { dx = -1 }
		if game.save.inverted_horizontal { dx = -dx }
	}
	if input.up { dz = 1 }
	if input.down { dz = -1 }
	if dx != 0 && dz != 0 {
		diagonal_scale := f32(0.7071067811865476)
		dx *= diagonal_scale
		dz *= diagonal_scale
	}
	if dx == 0 && dz == 0 {
		if player.animation_behavior == 3 { set_player_animation_behavior(player, 2) }
		return
	}
	// original movement advances 40 model units per frame across 600-unit cells.
	step := f32(40.0 / 600.0)
	candidate_x := player.position.x + dx * step
	candidate_z := player.position.z + dz * step
	left := -f32(game.board.width) * 0.5 + f32(1.0 / 600.0)
	right := f32(game.board.width) * 0.5 - f32(1.0 / 600.0)
	front := f32(-0.5 + 1.0 / 600.0)
	back := f32(game.board.remaining_rows) - f32(0.5 + 1.0 / 600.0)
	candidate_x = clamp(candidate_x, left, right)
	candidate_z = clamp(candidate_z, front, back)
	x_position := player.position
	x_position.x = candidate_x
	if !player_position_blocked(game, x_position) {
		player.position.x = candidate_x
	}
	z_position := player.position
	z_position.z = candidate_z
	if !player_position_blocked(game, z_position) {
		player.position.z = candidate_z
	}
	player.target = player.position
	player.column = clamp(i32(math.floor(f64(player.position.x + f32(game.board.width) * 0.5))), 0, game.board.width - 1)
	player.row = clamp(i32(math.floor(f64(player.position.z + 0.5))), 0, game.board.remaining_rows - 1)
	if dx < 0 { player.facing = -90 }
	else if dx > 0 { player.facing = 90 }
	else if dz < 0 { player.facing = 0 }
	else { player.facing = 180 }
	set_player_animation_behavior(player, 3)
}
iq_group_speed :: proc(speed_level: i32) -> i32 {
	remaining := max(0, 4 - speed_level)
	return ((remaining * 250 / 4) + 200) / 10
}

iq_group_wait :: proc(speed_level: i32) -> i32 {
	return max(0, 4 - speed_level) * 2 + 15
}

roll_wave :: proc(game: ^Game, dt: f32, accelerate: bool = false) {
	_ = dt
	board := &game.board
	board.roll_frame_counter += 1
	group_speed := iq_group_speed(game.speed_level)
	group_wait := iq_group_wait(game.speed_level)
	if accelerate {
		group_speed = max(8, group_speed / 2)
		group_wait = 0
	}
	trigger := board.roll_frame_counter % (group_speed + group_wait + 4) == 0
	board.rolling = false
	if trigger {
		capture_at_markers(game, game.capture_multiplier == 2)
		game.capture_multiplier = 0
	}
	for index: i32 = 0; index < board.cube_count; index += 1 {
		cube := &board.cubes[index]
		if !cube.active || cube.captured { continue }
		previous_behavior := cube.behavior
		switch cube.behavior {
		case .Waiting:
			if trigger { cube.behavior = .Begin_Flip }
		case .Begin_Flip:
			cube.behavior = .Flipping
			cube.previous_row = cube.row
			cube.roll_t = 0
		case .Flipping:
			rotation := i32(cube.roll_t * 1024.0 + 0.5)
			if rotation == 0x400 {
				cube.row -= 1
				cube.turns += 1
				cube.roll_t = 0
				if cube.row < 0 {
					cube.behavior = .Falling
					cube.falling = true
					cube.fall_t = 0
					cube.fall_offset = 0
					cube.spin = 0
				} else {
					cube.behavior = .Waiting
					if !game.attract && player_crushed_by_cube(game, cube) {
						set_player_animation_behavior(&game.player, 5)
						return
					}
				}
			} else {
				rotation = min(0x400, rotation + 0x400 / group_speed)
				cube.roll_t = f32(rotation) / 1024.0
			}
		case .Falling:
			cube.spin += 360.0 * 64.0 / 4096.0
			cube.fall_offset += f32(cube.behavior_frames + 4) * 12.0 / 300.0
			cube.fall_t = f32(cube.behavior_frames) / 25.0
			if cube.behavior_frames == 0x19 {
				cube.active = false
				if cube.kind != .Forbidden { register_missed_cube(game) }
			}
		}
		if previous_behavior == cube.behavior {
			cube.behavior_frames += 1
		} else {
			cube.behavior_frames = 0
		}
		if cube.behavior == .Begin_Flip || cube.behavior == .Flipping {
			board.rolling = true
		}
	}
}


all_cubes_resolved :: proc(board: ^Board) -> bool {
	for index: i32 = 0; index < board.cube_count; index += 1 {
		if board.cubes[index].active { return false }
	}
	return true
}

update_iq_camera :: proc(game: ^Game) {
	player := &game.player
	left := -f32(game.board.width) * 0.5
	right := f32(game.board.width) * 0.5
	front := f32(-0.5)
	if game.capture_timer != 0 {
		game.camera_target = rl.Vector3{player.position.x, player.position.y + 1, player.position.z}
		game.camera_position.x += (right + 1 - game.camera_position.x) / 18
		game.camera_position.y += (player.position.y + 6 - game.camera_position.y) / 18
		game.camera_position.z += (front - 8 - game.camera_position.z) / 18
		return
	}
	if game.platform_loss_timer != 0 {
		game.camera_target.x += (left + 3 - game.camera_target.x) / 30
		game.camera_target.y += (0 - game.camera_target.y) / 30
		game.camera_target.z += (front - game.camera_target.z) / 30
		game.camera_position.x += (right + 2 - game.camera_position.x) / 18
		game.camera_position.y += (5 - game.camera_position.y) / 18
		game.camera_position.z += (front - 8 - game.camera_position.z) / 18
		return
	}
	if player.animation_behavior == 5 || game.state == .Game_Over {
		game.camera_target = player.position
		game.camera_position.x += (player.position.x + 1 - game.camera_position.x) / 38
		game.camera_position.y += (player.position.y - 7 - game.camera_position.y) / 38
		game.camera_position.z += (player.position.z - 2 - game.camera_position.z) / 38
		return
	}
	first_row, last_row := i32(99), i32(-1)
	for index: i32 = 0; index < game.board.cube_count; index += 1 {
		cube := &game.board.cubes[index]
		if !cube.active { continue }
		first_row = min(first_row, cube.row)
		last_row = max(last_row, cube.row)
	}
	active_span: i32 = 0
	if last_row >= first_row { active_span = last_row - first_row + 1 }
	game.camera_target = rl.Vector3{player.position.x, player.position.y + 1, player.position.z}
	switch game.camera_mode {
	case 1:
		game.camera_position.x += (player.position.x * 2 - game.camera_position.x) / 14
		game.camera_position.y += (player.position.y + 4 - game.camera_position.y) / 14
		game.camera_position.z += (player.position.z - 4.5 - game.camera_position.z) / 14
	case 2:
		game.camera_position.x += (player.position.x * 3.5 - game.camera_position.x) / 22
		game.camera_position.y +=
			(player.position.y + f32(active_span + 6) - game.camera_position.y) / 24
		game.camera_position.z += (player.position.z - 8 - game.camera_position.z) / 22
	case:
		game.camera_position.x += (player.position.x * 3 - game.camera_position.x) / 18
		game.camera_position.y +=
			(player.position.y + f32(active_span + 4) * 0.8 - game.camera_position.y) / 20
		game.camera_position.z = player.position.z - 6
	}
}

calculate_stage_iq :: proc(game: ^Game) {
	weighted := game.stage_score
	switch game.speed_level {
	case 1: weighted += weighted / 4
	case 2: weighted += weighted * 3 / 10
	case 3: weighted += weighted * 9 / 20
	case 4: weighted += weighted / 2
	case:
	}
	increment: i32
	switch game.stage {
	case 0:
		increment = i32((u64((weighted / 100) * 600) * u64(0xd1b71759)) >> 45)          // hackers delight-esque div by 5 optimisation
	case 1:
		increment = i32((u64((weighted / 100) * 550) * u64(0xd1b71759)) >> 45)
	case 2: increment = weighted / 2000
	case 3:
		increment = i32((u64((weighted / 100) * 450) * u64(0xd1b71759)) >> 45)
	case 4: increment = weighted / 2500
	case 5:
		increment = i32((u64((weighted / 100) * 350) * u64(0xd1b71759)) >> 45)
	case 6:
		increment = i32((u64((weighted / 100) * 300) * u64(0xd1b71759)) >> 45)
	case 7: increment = weighted / 4000
	case 8: increment = weighted / 5000
	}
	game.stage_score = 0
	game.iq = min(999, game.iq + increment)
}

update_marker_animation :: proc(board: ^Board) {
	for row in 0..<MAX_DEPTH {
		for column in 0..<MAX_WIDTH {
			marker := &board.markers[row][column]
			if marker.state != marker.visual_state {
				marker.visual_state = marker.state
				marker.pulse = 0
			} else if marker.state != .Empty {
				marker.pulse = min(14, marker.pulse + 1)
			}
		}
	}
}

update_playing :: proc(game: ^Game, input: Input_State, dt: f32) {
	if input.pause { game.paused = !game.paused }
	if game.paused {
		if input.cancel { transition_to(game, .Title) }
		return
	}
	update_marker_animation(&game.board)
	play_stage_music(game.stage, game.save.music_volume)
	if game.capture_timer != 0 {
		game.capture_timer += 1
		update_player_animation(&game.player)
		update_iq_camera(game)
		if game.capture_timer > 0x38 {
			for index: i32 = 0; index < game.board.cube_count; index += 1 {
				cube := &game.board.cubes[index]
				if cube.captured {
					cube.captured = false
					cube.active = false
				}
			}
			game.capture_timer = 0
			if game.player.animation_behavior == 4 {
				set_player_animation_behavior(&game.player, 2)
			}
		}
		return
	}
	if game.platform_loss_timer != 0 {
		game.platform_loss_timer += 1
		update_iq_camera(game)
		if game.platform_loss_timer > 0x38 {
			game.board.remaining_rows -= 1
			game.board.mistakes += 1
			game.platform_loss_timer = 0
			if game.board.remaining_rows <= 4 {
				set_player_animation_behavior(&game.player, 5)
			}
		}
		return
	}
	if game.player.animation_behavior != 5 {
		move_player(game, input, dt)
		if input.marker { place_marker(game) }
		if input.detonate { detonate_markers(game) }
		if input.advantage { detonate_advantage(game) }
	}
	if input.up || input.down || input.left || input.right {
		if game.frame % 20 == 0 {
			effect := Sound_Effect.Step_A
			if game.player.character == 2 { effect = .Spike_Step_A }
			play_effect(effect, game.save.sound_volume)
		} else if game.frame % 20 == 10 {
			effect := Sound_Effect.Step_B
			if game.player.character == 2 { effect = .Spike_Step_B }
			play_effect(effect, game.save.sound_volume)
		}
	}
	roll_wave(game, dt, input.accelerate)
	if input.up || input.down || input.left || input.right || game.player.animation_behavior != 2 {
		if game.player.animation_behavior == 5 && !game.player.animation_held {
			game.player.fall_step += 1
			game.player.position.y -= f32(game.player.fall_step) / 300
		}
		update_player_animation(&game.player)
		if game.player.animation_behavior == 5 && game.player.animation_held {
			game.player.alive = false
			if game.editor_playtest { transition_to(game, .Editor) }
			else if game.two_player { finish_two_player_round(game, false) }
			else { transition_to(game, .Game_Over) }
			return
		}
	}
	update_iq_camera(game)
	if all_cubes_resolved(&game.board) && game.state == .Playing {
		game.board.wave_complete = true
		award_perfect_puzzle(game)
		if game.editor_playtest {
			transition_to(game, .Editor)
			return
		}
		if game.two_player {
			finish_two_player_round(game, true)
			return
		}
		if game.board.wave_rows_remaining > 0 {
			spawn_wave(game)
		} else if game.wave + 1 < WAVES_PER_STAGE {
			game.wave += 1
			game.board.wave_rows_remaining = STAGES[game.stage].waves[game.wave].advancements
			spawn_wave(game)
		} else {
			stage_bonus := game.board.remaining_rows * 1000
			game.score += stage_bonus
			game.stage_score += stage_bonus
			calculate_stage_iq(game)
			transition_to(game, .Stage_Clear)
		}
	}
}
