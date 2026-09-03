package high_iq

import "core:fmt"
import "core:os"
import rl "raylib"

transition_to :: proc(game: ^Game, state: Game_State) {
	if (game.state == .Opening || game.state == .Ending) &&
		state != .Opening && state != .Ending {
		stop_movie_audio()
	}
	game.previous_state = game.state
	game.state = state
	game.state_time = 0
	game.menu_index = 0
	game.fade = 1
	game.fade_target = 0
	switch state {
		case .Title:
			game.attract = false
			game.attract_time = 0
			game.menu_count = 4
		case .Game_Mode_Menu:
			game.menu_count = 3
		case .Two_Player_Select:
			game.menu_count = 2
			game.two_player = true
		case .Two_Player_Round_End, .Two_Player_Match_End:
			game.menu_count = 1
		case .Pause:
			game.menu_count = 4
			game.menu_index = 1
			game.confirmation_active = false
		case .Ranking, .Memory_Card:
			game.menu_count = 1
		case .Texture_Select:
			game.menu_count = 5
		case .Model_Viewer:
			game.menu_count = 1
		case .Controller:
			game.menu_count = 6
		case .Rules:
			game.menu_count = 7
		case .Options:
			game.menu_count = 10
		case .Continue:
			game.menu_count = 2
		case .Stage_Clear:
			set_message(game, IQ_EN_STAGE_COMPLETE, 2)
		case .Game_Over:
		case .Name_Entry:
			game.name_entry = {}
			game.name_length = 0
			game.name_grid_x = 0
			game.name_grid_y = 0
		case .Editor:
			init_editor(game)
		case .Opening, .Ending:
			play_movie_audio(game.save.music_volume)
		case .Trademark, .Loading, .Playing, .Capture_Success, .Next_Level,
				.Score_Display, .Debug:
	}
}

init_game :: proc(game: ^Game, skip_splash, debug_mode, editor_mode: bool) {
	game^ = {}
	load_save(&game.save)
	game.player.character = clamp(i32(game.save.selected_character), 0, 2)
	if game.player.character == 2 && game.save.unlock_flags & 2 == 0 {
		game.player.character = 0
	}
	game.camera_yaw = 0
	game.camera_pitch = 47
	game.camera_distance = 15
	game.mode = .Normal
	game.rng = 2
	game.state = .Trademark
	game.fade = 1
	game.fade_target = 0
	_ = load_assets(game)
	if debug_mode {
		start_stage(game, 0)
		game.state = .Playing
	} else if editor_mode {
		game.state = .Editor
		init_editor(game)
	} else if skip_splash {
		game.state = .Title
	}
}

update_menu_index :: proc(game: ^Game, input: Input_State) {
	step := menu_step(input)
	if step != 0 && game.menu_count > 0 {
		game.menu_index = (game.menu_index + step + game.menu_count) % game.menu_count
		play_effect(.Menu_Move, game.save.sound_volume)
	}
}
menu_horizontal_step :: proc() -> i32 {
	if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.A) ||
	   (rl.IsGamepadAvailable(0) && rl.IsGamepadButtonPressed(0, .LEFT_FACE_LEFT)) { return -1 }
	if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) ||
	   (rl.IsGamepadAvailable(0) && rl.IsGamepadButtonPressed(0, .LEFT_FACE_RIGHT)) { return 1 }
	return 0
}

update_title_menu :: proc(game: ^Game) {
	horizontal := menu_horizontal_step()
	vertical := menu_step({})
	if horizontal != 0 {
		if game.menu_index & 1 == 0 { game.menu_index += 1 }
		else { game.menu_index -= 1 }
		play_effect(.Menu_Move, game.save.sound_volume)
	}
	if vertical != 0 {
		if game.menu_index < 2 { game.menu_index += 2 }
		else { game.menu_index -= 2 }
		play_effect(.Menu_Move, game.save.sound_volume)
	}
}

confirm_pause_choice :: proc(game: ^Game) {
	switch game.menu_index {
	case 1:
		transition_to(game, .Playing)
	case 2, 3:
		game.confirmation_active = true
		game.confirmation_index = 1
	case 0:
	}
}

update_pause :: proc(game: ^Game, input: Input_State) {
	if game.confirmation_active {
		horizontal := menu_horizontal_step()
		if horizontal != 0 {
			game.confirmation_index = 1 - game.confirmation_index
			play_effect(.Menu_Move, game.save.sound_volume)
		}
		if input.cancel {
			game.confirmation_active = false
		} else if input.confirm {
			if game.confirmation_index == 1 {
				game.confirmation_active = false
			} else if game.menu_index == 2 {
				start_stage(game, game.stage)
				transition_to(game, .Playing)
			} else {
				transition_to(game, .Title)
			}
		}
		return
	}
	update_menu_index(game, input)
	horizontal := menu_horizontal_step()
	if game.menu_index == 0 && horizontal != 0 {
		game.camera_mode = clamp(game.camera_mode + horizontal, 0, 2)
		play_effect(.Menu_Move, game.save.sound_volume)
	}
	if input.pause || input.cancel {
		transition_to(game, .Playing)
	} else if input.confirm {
		confirm_pause_choice(game)
	}
}

begin_game :: proc(game: ^Game) {
	play_effect(.Game_Start, game.save.sound_volume)
	game.score = 0
	game.iq = 0
	game.editor_playtest = false
	if game.mode == .Original {
		transition_to(game, .Editor)
		return
	}
	start_stage(game, 0)
	transition_to(game, .Loading)
}

demo_recording_frames :: proc(mode: i32) -> i32 {
	switch mode {
	case 0: return 3987
	case 1: return 5074
	case 2: return 3429
	case 3: return 4590
	case 4: return 3499
	case 5: return 4866
	case: return 0
	}
}

attract_input :: proc(game: ^Game) -> Input_State {
	input: Input_State
	if len(game.demo_data) < 16 { return input }
	offset := int(game.demo_cursor) * 4
	if offset + 8 > len(game.demo_data) {
		game.demo_cursor = 2
		game.demo_frame = 0
		offset = 8
	}
	duration := i32(u32_at(game.demo_data, offset))
	buttons := u32_at(game.demo_data, offset + 4)
	pressed := buttons & ~game.demo_buttons
	input.up = buttons & 0x1000 != 0
	input.down = buttons & 0x4000 != 0
	input.left = buttons & 0x8000 != 0
	input.right = buttons & 0x2000 != 0
	if pressed & 0x20 != 0 {
		if game.board.placed_marker_active { input.detonate = true }
		else { input.marker = true }
	}
	input.advantage = pressed & 0x10 != 0
	game.demo_buttons = buttons
	if duration == game.demo_frame {
		game.demo_cursor += 2
		game.demo_frame = 0
	} else {
		game.demo_frame += 1
	}
	game.demo_elapsed += 1
	return input
}

Timeline_Step :: struct { frame, hold, event: i32 }

DEMO_TIMELINE_0 := [26]Timeline_Step{
	{10,0,19}, {250,0,21}, {251,320,1}, {380,0,22}, {381,300,1},
	{410,0,23}, {411,300,1}, {480,0,24}, {481,400,1}, {500,0,25},
	{501,200,1}, {502,0,26}, {503,200,1}, {580,0,27}, {581,200,1},
	{660,0,28}, {661,300,1}, {700,0,29}, {1300,0,30}, {1530,0,31},
	{1531,460,2}, {1580,0,32}, {2000,0,33}, {2750,0,34}, {3700,0,35},
	{3900,360,1},
}
DEMO_TIMELINE_1 := [8]Timeline_Step{
	{10,0,37}, {320,0,38}, {835,0,39}, {837,380,3},
	{970,0,40}, {1230,0,41}, {1700,0,42}, {2200,0,43},
}
DEMO_TIMELINE_2 := [12]Timeline_Step{
	{10,0,44}, {300,0,45}, {800,0,46}, {802,250,4}, {900,0,47},
	{1200,0,48}, {1320,400,5}, {1350,0,49}, {1620,0,50},
	{1820,0,51}, {2400,0,52}, {2740,0,53},
}

demo_timeline_step :: proc(mode, index: i32) -> (Timeline_Step, bool) {
	switch mode {
	case 0:
		if index < len(DEMO_TIMELINE_0) { return DEMO_TIMELINE_0[index], true }
	case 1:
		if index < len(DEMO_TIMELINE_1) { return DEMO_TIMELINE_1[index], true }
	case 2:
		if index < len(DEMO_TIMELINE_2) { return DEMO_TIMELINE_2[index], true }
	case:
	}
	return {}, false
}

update_demo_timeline :: proc(game: ^Game) -> bool {
	if game.demo_hold_remaining > 0 {
		game.demo_hold_remaining -= 1
		return true
	}
	step, exists := demo_timeline_step(game.demo_mode, game.demo_timeline_index)
	if !exists { return false }
	game.demo_timeline_clock += 1
	if game.demo_timeline_clock != step.frame { return false }
	game.demo_timeline_index += 1
	if step.hold > 0 {
		game.demo_hold_remaining = step.hold
		return true
	}
	play_voice_event(int(step.event), game.save.sound_volume)
	return false
}

start_demo :: proc(game: ^Game, mode: i32, return_to_rules: bool) {
	path := asset_path(game.assets.root, fmt.aprintf("IQ/PLAYER/DEMO_%02d.DAT", mode))
	recording, err := os.read_entire_file(path, context.allocator)
	if err == nil {
		if game.demo_data != nil { delete(game.demo_data) }
		game.demo_data = recording
	}
	game.score = 0
	game.demo_cursor = 2
	game.demo_frame = 0
	game.demo_buttons = 0
	game.demo_elapsed = 0
	game.demo_mode = mode
	game.demo_timeline_clock = 0
	game.demo_timeline_index = 0
	game.demo_hold_remaining = 0
	game.demo_return_rules = return_to_rules
	// rng seed 2 selects the recorded demo's first puzzle layout.
	game.rng = 2
	if mode == 0 || mode == 1 {
		start_stage(game, 0, 0, -1, true, false)
	} else if mode == 2 {
		start_stage(game, 0, 2, -1, true, false)
	} else if mode == 3 {
		start_stage(game, 4, 3, 35, true, true)
	} else if mode == 4 || mode == 5 {
		start_stage(game, 8, 0, 25, true, true)
	} else {
		start_stage(game, 0, 0, -1, true, false)
	}
	game.attract = true
	transition_to(game, .Loading)
}


update_name_entry :: proc(game: ^Game, input: Input_State) {
	characters := IQ_EN_NAME_CHARACTERS
	horizontal := menu_horizontal_step()
	vertical := menu_step(input)
	if horizontal != 0 {
		game.name_grid_x = (game.name_grid_x + horizontal + 11) % 11
	}
	if vertical != 0 {
		game.name_grid_y = (game.name_grid_y + vertical + 3) % 3
	}
	if input.cancel {
		if game.name_length > 0 {
			game.name_length -= 1
			game.name_entry[game.name_length] = 0
		}
		return
	}
	if !input.confirm { return }
	index := game.name_grid_y * 11 + game.name_grid_x
	if index < 30 {
		if game.name_length < len(game.name_entry) {
			game.name_entry[game.name_length] = characters[index]
			game.name_length += 1
		}
	} else if index == 30 {
		if game.name_length < len(game.name_entry) {
			game.name_entry[game.name_length] = ' '
			game.name_length += 1
		}
	} else if index == 31 {
		if game.name_length > 0 {
			game.name_length -= 1
			game.name_entry[game.name_length] = 0
		}
	} else {
		if game.name_length == 0 {
			game.name_entry[0] = 'Y'
			game.name_entry[1] = 'O'
			game.name_entry[2] = 'U'
			game.name_length = 3
		}
		submit_ranking(game)
		transition_to(game, .Continue)
	}
}
start_ending :: proc(game: ^Game) {
	endings := [3]string{"IQ/STR/END0A.STR", "IQ/STR/END0G.STR", "IQ/STR/END0D.STR"}
	_ = load_movie(game, endings[clamp(game.player.character, 0, 2)])
	transition_to(game, .Ending)
}

cycle_controller_mapping :: proc(game: ^Game, action: i32) {
	if action < 0 || action >= len(game.save.button_mapping) { return }
	old_button := game.save.button_mapping[action]
	new_button := (old_button + 1) % 4
	for other in 0..<len(game.save.button_mapping) {
		if i32(other) != action && game.save.button_mapping[other] == new_button {
			game.save.button_mapping[other] = old_button
			break
		}
	}
	game.save.button_mapping[action] = new_button
	play_effect(.Menu_Move, game.save.sound_volume)
}


update_game :: proc(game: ^Game, input: Input_State, dt: f32) {
	game.frame += 1
	game.state_time += dt
	game.message_time = max(0, game.message_time - dt)
	game.camera_shake = max(0, game.camera_shake - dt * 1.8)
	game.fade += (game.fade_target - game.fade) * min(1, dt * 6)

	switch game.state {
	case .Trademark:
		if input.confirm || input.cancel || game.state_time > 7 { transition_to(game, .Opening) }
	case .Title:
		if input.up || input.down || input.left || input.right ||
				input.confirm || input.cancel || input.pause {
			game.attract_time = 0
		} else {
			game.attract_time += dt
		}
		update_title_menu(game)
		if input.confirm {
			play_effect(.Title_Confirm, game.save.sound_volume)
			switch game.menu_index {
			case 0:
				game.two_player = false
				game.player.character = clamp(i32(game.save.selected_character), 0, 2)
				begin_game(game)
			case 1:
				game.two_player = true
				game.player.character = 1
				transition_to(game, .Two_Player_Select)
			case 2:
				transition_to(game, .Rules)
			case 3:
				transition_to(game, .Options)
			}
		} else if game.attract_time > 10 {
			mode := 3 + game.attract_cycle
			game.attract_cycle = (game.attract_cycle + 1) % 3
			start_demo(game, mode, false)
		}
	case .Opening:
		opening_duration := f32(game.movie_frames) / 15.0
		if input.confirm || input.cancel || game.state_time > opening_duration {
			transition_to(game, .Title)
		}
	case .Ending:
		ending_duration := f32(game.movie_frames) / 15.0
		if input.confirm || input.cancel || game.state_time > ending_duration {
			transition_to(game, .Score_Display)
		}
	case .Game_Mode_Menu:
		update_menu_index(game, input)
		horizontal := menu_horizontal_step()
		if horizontal != 0 {
			if game.menu_index == 0 {
				if horizontal < 0 { game.mode = .Normal }
				else { game.mode = .Original }
			} else if game.menu_index == 1 {
				game.speed_level = clamp(game.speed_level + horizontal, 0, 4)
			}
			play_effect(.Menu_Move, game.save.sound_volume)
		}
		if input.cancel || (input.confirm && game.menu_index == 2) {
			transition_to(game, .Options)
		}
	case .Two_Player_Select:
		update_menu_index(game, input)
		horizontal := menu_horizontal_step()
		if game.menu_index == 0 && horizontal != 0 {
			game.speed_level = clamp(game.speed_level + horizontal, 0, 4)
			play_effect(.Menu_Move, game.save.sound_volume)
		}
		if input.cancel || (input.confirm && game.menu_index == 1) {
			game.two_player = false
			transition_to(game, .Title)
		} else if input.confirm {
			game.score = 0
			game.iq = 0
			game.player_wins = {}
			game.two_player_rounds_cleared = 0
			game.active_player = 0
			start_two_player_round(game)
			transition_to(game, .Loading)
		}
	case .Two_Player_Round_End:
		if input.confirm || game.state_time > 2.5 {
			if two_player_match_complete(game) {
				transition_to(game, .Two_Player_Match_End)
			} else {
				game.active_player = 1 - game.active_player
				start_two_player_round(game)
				transition_to(game, .Loading)
			}
		}
	case .Two_Player_Match_End:
		if input.confirm || input.cancel || game.state_time > 6 {
			game.two_player = false
			transition_to(game, .Title)
		}
	case .Loading:
		if game.attract {
			// original consumes the recording during stage fly-in but suppresses
			// its input until wave_rows * 14 + 100 frames have elapsed.
			_ = attract_input(game)
			loading_frames := STAGES[game.stage].waves[game.wave].advancements * 14 + 100
			if game.state_time * 60 > f32(loading_frames) { transition_to(game, .Playing) }
		} else if game.state_time > 1.2 {
			transition_to(game, .Playing)
		}
	case .Playing:
		if input.pause && !game.attract {
			transition_to(game, .Pause)
			return
		}
		play_input := input
		if game.attract {
			if input.confirm || input.cancel || input.pause {
				if game.demo_return_rules { transition_to(game, .Rules) }
				else { transition_to(game, .Title) }
				return
			}
			if game.demo_elapsed >= demo_recording_frames(game.demo_mode) {
				if game.demo_return_rules { transition_to(game, .Rules) }
				else { transition_to(game, .Title) }
				return
			}
			if update_demo_timeline(game) { return }
			if game.capture_timer == 0 && game.platform_loss_timer == 0 {
				play_input = attract_input(game)
			} else {
				play_input = {}
			}
		}
		update_playing(game, play_input, dt)
	case .Pause:
		update_pause(game, input)
	case .Controller:
		update_menu_index(game, input)
		if input.cancel || (input.confirm && game.menu_index == 5) {
			transition_to(game, game.previous_state)
		} else if input.confirm && game.menu_index < 4 {
			cycle_controller_mapping(game, game.menu_index)
		} else if input.confirm && game.menu_index == 4 {
			game.save.button_mapping = {0, 1, 2, 3}
			play_effect(.Menu_Move, game.save.sound_volume)
		}
	case .Capture_Success:
		update_playing(game, {}, dt)
	case .Stage_Clear:
		if input.confirm || game.state_time > 4 {
			if game.editor_playtest {
				transition_to(game, .Editor)
			} else if game.stage + 1 < STAGE_COUNT {
				start_stage(game, game.stage + 1)
				transition_to(game, .Loading)
			} else {
				start_ending(game)
			}
		}
	case .Next_Level:
		start_stage(game, min(game.stage + 1, STAGE_COUNT - 1))
		transition_to(game, .Loading)
	case .Game_Over:
		if game.attract { transition_to(game, .Title) }
		else if input.confirm || game.state_time > 6 { transition_to(game, .Score_Display) }
	case .Score_Display:
		if input.confirm || input.cancel {
			game.save.unlock_flags = unlock_flags_for_iq(game.save.unlock_flags, game.iq)
			write_save(&game.save)
			if ranking_qualifies(game) { transition_to(game, .Name_Entry) }
			else { transition_to(game, .Continue) }
		}
	case .Name_Entry:
		update_name_entry(game, input)
	case .Ranking:
		if input.confirm || input.cancel { transition_to(game, .Options) }
	case .Options:
		update_menu_index(game, input)
		if input.cancel {
			transition_to(game, .Title)
		} else if input.confirm {
			switch game.menu_index {
			case 0: transition_to(game, .Controller)
			case 1: transition_to(game, .Game_Mode_Menu)
			case 2: transition_to(game, .Ranking)
			case 3: transition_to(game, .Memory_Card)
			case 4: transition_to(game, .Texture_Select)
			case 5: transition_to(game, .Model_Viewer)
			case 6:
				game.save.music_volume += 0.25
				if game.save.music_volume > 1 { game.save.music_volume = 0 }
			case 7:
				game.save.sound_volume += 0.25
				if game.save.sound_volume > 1 { game.save.sound_volume = 0 }
			case 8:
				game.save.inverted_horizontal = !game.save.inverted_horizontal
			case 9: transition_to(game, .Title)
			}
		}
	case .Rules:
		update_menu_index(game, input)
		if input.cancel || (input.confirm && game.menu_index == 6) {
			transition_to(game, .Title)
		} else if input.confirm {
			start_demo(game, game.menu_index, true)
		}
	case .Memory_Card:
		if input.confirm || input.cancel {
			write_save(&game.save)
			transition_to(game, .Options)
		}
	case .Texture_Select:
		update_menu_index(game, input)
		if input.cancel {
			transition_to(game, .Options)
		} else if input.confirm {
			game.texture_style = game.menu_index
			if game.assets.loaded { _ = set_cube_style_assets(game, game.texture_style) }
			transition_to(game, .Options)
		}
	case .Model_Viewer:
		horizontal := menu_horizontal_step()
		if horizontal != 0 {
			character_count := i32(2)
			if game.save.unlock_flags & 2 != 0 { character_count = 3 }
			game.player.character =
				(game.player.character + horizontal + character_count) % character_count
			game.save.selected_character = u8(game.player.character)
		}
		if input.confirm || input.cancel {
			write_save(&game.save)
			transition_to(game, .Options)
		}
	case .Continue:
		update_menu_index(game, input)
		if input.cancel || (input.confirm && game.menu_index == 1) {
			transition_to(game, .Title)
		} else if input.confirm {
			start_stage(game, game.stage)
			transition_to(game, .Loading)
		}
	case .Editor:
		update_editor(game, input, dt)
	case .Debug:
		if input.pause { transition_to(game, .Pause) }
		else { update_playing(game, input, dt) }
}
}

status_text :: proc(game: ^Game) -> string {
	return fmt.aprintf(IQ_EN_FMT_STATUS, game.stage + 1, game.wave + 1, game.score)
}
