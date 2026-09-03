package high_iq

import "core:os"
import "core:fmt"
import rl "raylib"

has_argument :: proc(argument: string) -> bool {
	for value in os.args[1:] {
		if value == argument { return true }
	}
	return false
}
main :: proc() {
	skip_splash := has_argument("--skip-splash")
	debug_mode := has_argument("--debug")
	editor_mode := has_argument("--editor")

	state_snapshots := has_argument("--state-snapshots")
	movie_snapshot := has_argument("--movie-snapshot")
	rl.InitWindow(INTERNAL_WIDTH, INTERNAL_HEIGHT, IQ_EN_WINDOW_TITLE)
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	init_audio()
	defer shutdown_audio()
	game: Game
	init_game(&game, skip_splash, debug_mode, editor_mode)
	fmt.printf("[high_iq] ready state=%v assets=%v\n", game.state, game.assets.loaded)
	defer unload_assets(&game)
	if state_snapshots {
		start_stage(&game, 0)
		game.fade = 0
		states := [27]Game_State{
			.Trademark, .Opening, .Ending, .Title, .Game_Mode_Menu,
			.Two_Player_Select, .Two_Player_Round_End, .Two_Player_Match_End,
			.Loading, .Playing, .Pause, .Controller, .Capture_Success,
			.Stage_Clear, .Next_Level, .Game_Over, .Score_Display, .Ranking,
			.Options, .Rules, .Name_Entry, .Memory_Card, .Texture_Select,
			.Model_Viewer, .Continue, .Editor, .Debug,
		}
		for state, index in states {
			game.state = state
			game.state_time = 1
			game.fade = 0
			game.capture_timer = 0
			game.platform_loss_timer = 0
			if state == .Ending {
				_ = load_movie(&game, "IQ/STR/END0A.STR")
				game.state_time = 20
			}
			if state == .Name_Entry {
				game.name_entry[0] = 'I'
				game.name_entry[1] = 'Q'
				game.name_length = 2
			}
			if state == .Capture_Success && game.board.cube_count > 0 {
				game.board.cubes[0].captured = true
				game.capture_timer = 8
			}
			if state == .Editor { init_editor(&game) }
			render_game(&game)
			rl.TakeScreenshot(fmt.ctprintf("state_%02d.png", index))
		}
		game.state = .Playing
		game.fade = 0
		game.platform_loss_timer = 12
		render_game(&game)
		rl.TakeScreenshot("state_collapse.png")
		fmt.println("[high_iq] state_snapshots count=27")
		return
	}

	if movie_snapshot {
		game.state = .Opening
		game.state_time = 299.0 / 15.0
		rl.BeginDrawing()
		draw_movie(&game)
		fmt.printf("[high_iq] movie_frame requested=300 decoded=%d total=%d size=%dx%d\n",
			game.movie_frame, game.movie_frames, game.movie_width, game.movie_height)
		movie_rgb_max: u8
		movie_rgb_min := u8(255)
		movie_alpha := 0
		for index in 0..<int(game.movie_width * game.movie_height * 4) {
			if index & 3 == 3 {
				if mdec_rgba[index] != 0 { movie_alpha += 1 }
			} else {
				movie_rgb_max = max(movie_rgb_max, mdec_rgba[index])
				movie_rgb_min = min(movie_rgb_min, mdec_rgba[index])
			}
		}
		fmt.printf("[high_iq] movie_pixels rgb=%d..%d alpha=%d\n", movie_rgb_min, movie_rgb_max, movie_alpha)
		movie_image := rl.LoadImageFromTexture(game.movie_texture)
		_ = rl.ExportImage(movie_image, "movie_texture.png")
		rl.EndDrawing()
		rl.TakeScreenshot("movie_frame.png")
		rl.UnloadImage(movie_image)
		endings := [3]string{"IQ/STR/END0A.STR", "IQ/STR/END0G.STR", "IQ/STR/END0D.STR"}
		endings_ok := true
		for ending in endings {
			loaded := load_movie(&game, ending) && movie_decode_frame(&game, 300)
			rgb_min, rgb_max := u8(255), u8(0)
			for index in 0..<int(game.movie_width * game.movie_height * 4) {
				if index & 3 != 3 {
					rgb_min = min(rgb_min, mdec_rgba[index])
					rgb_max = max(rgb_max, mdec_rgba[index])
				}
			}
			endings_ok = endings_ok && loaded && rgb_min < rgb_max
		}
		fmt.printf("[high_iq] ending_movies decoded=%v\n", endings_ok)
		if !endings_ok { os.exit(1) }
		return
	}
	accumulator: f32
	for !rl.WindowShouldClose() {
		frame_time := min(rl.GetFrameTime(), f32(0.1))
		accumulator += frame_time
		input := read_input_for_player(
			game.active_player if game.two_player else 0, game.save.button_mapping)
		first_tick := true
		for accumulator >= FIXED_DT {
			tick_input := input
			if !first_tick {
				tick_input.confirm = false
				tick_input.cancel = false
				tick_input.marker = false
				tick_input.detonate = false
				tick_input.advantage = false
				tick_input.pause = false
			}
			update_game(&game, tick_input, FIXED_DT)
			accumulator -= FIXED_DT
			first_tick = false
		}
		render_game(&game)
	}
	write_save(&game.save)
}
