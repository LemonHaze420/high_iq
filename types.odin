package high_iq

import rl "raylib"

MAX_WIDTH :: 7
MAX_DEPTH :: 40
MAX_CUBES :: MAX_WIDTH * MAX_DEPTH
MAX_MARKERS :: MAX_WIDTH * MAX_DEPTH
STAGE_COUNT :: 9
WAVES_PER_STAGE :: 4

Game_State :: enum {
	Trademark,
	Opening,
	Ending,
	Title,
	Game_Mode_Menu,
	Two_Player_Select,
	Two_Player_Round_End,
	Two_Player_Match_End,
	Loading,
	Playing,
	Pause,
	Controller,
	Capture_Success,
	Stage_Clear,
	Next_Level,
	Game_Over,
	Score_Display,
	Ranking,
	Options,
	Rules,
	Name_Entry,
	Memory_Card,
	Texture_Select,
	Model_Viewer,
	Continue,
	Editor,
	Debug,
}

Game_Mode :: enum {
	Normal,
	Original,
}

Cube_Type :: enum u8 {
	Normal,
	Advantage,
	Forbidden,
}

Marker_State :: enum u8 {
	Empty,
	Armed,
	Detonating,
	Advantage,
}

Cube_Behavior :: enum u8 {
	Waiting,
	Begin_Flip,
	Flipping,
	Falling,
}

Cube :: struct {
	kind: Cube_Type,
	column: i32,
	row: i32,
	previous_row: i32,
	roll_t: f32,
	active: bool,
	captured: bool,
	falling: bool,
	fall_t: f32,
	turns: i32,
	behavior: Cube_Behavior,
	behavior_frames: i32,
	fall_offset: f32,
	spin: f32,
}

Marker :: struct {
	state: Marker_State,
	visual_state: Marker_State,
	pulse: f32,
}

Player :: struct {
	column: i32,
	row: i32,
	position: rl.Vector3,
	target: rl.Vector3,
	facing: f32,
	move_cooldown: f32,
	alive: bool,
	character: i32,
	animation_behavior: i32,
	animation_sequence_index: i32,
	animation_timer: i32,
	animation_frame: i32,
	animation_held: bool,
	fall_step: i32,
}

Wave_Config :: struct {
	advancements: i32,
	depth: i32,
}

Stage_Config :: struct {
	width: i32,
	starting_rows: i32,
	waves: [WAVES_PER_STAGE]Wave_Config,
}

Board :: struct {
	width: i32,
	depth: i32,
	remaining_rows: i32,
	stage: i32,
	wave: i32,
	cubes: [MAX_CUBES]Cube,
	placed_marker_active: bool,
	remaining_columns: i32,
	wave_rows_remaining: i32,
	cube_count: i32,
	markers: [MAX_DEPTH][MAX_WIDTH]Marker,
	roll_timer: f32,
	roll_frame_counter: i32,
	roll_interval: f32,
	roll_duration: f32,
	rolling: bool,
	wave_started: bool,
	wave_complete: bool,
	mistakes: i32,
	captured_normal: i32,
	captured_advantage: i32,
	captured_forbidden: i32,
	wave_missed: i32,
	wave_forbidden: i32,
}

Input_State :: struct {
	up, down, left, right: bool,
	confirm, cancel, marker, detonate, advantage, accelerate: bool,
	pause: bool,
}
Ranking_Entry :: struct {
	name: [10]u8,
	score: i32,
	iq: i32,
}

Save_Data :: struct {
	magic: u32,
	version: u32,
	music_volume: f32,
	sound_volume: f32,
	button_mapping: [4]u8,
	inverted_horizontal: bool,
	unlock_flags: u8,
	selected_character: u8,
	rankings: [5][10]Ranking_Entry,
}

Ymd_Model :: struct {
	model: rl.Model,
	data: []u8,
	frame_count: i32,
	animation_start: i32,
	animation_length: i32,
	triangle_count: i32,
	quad_count: i32,
	current_frame: i32,
	valid: bool,
}

Assets :: struct {
	root: string,
	trademark: rl.Texture2D,
	title: rl.Texture2D,
	warning_1: rl.Texture2D,
	warning_2: rl.Texture2D,
	player_select: rl.Texture2D,
	tile_colors: [5]rl.Color,
	player_models: [3]Ymd_Model,
	cube_models: [3]rl.Model,
	cube_textures: [3]rl.Texture2D,
	marker_models: [15]rl.Model,
	marker_textures: [15]rl.Texture2D,
	loaded: bool,
}
Game :: struct {
	state: Game_State,
	previous_state: Game_State,
	mode: Game_Mode,
	state_time: f32,
	frame: u64,
	menu_index: i32,
	speed_level: i32,
	menu_count: i32,
	two_player: bool,
	active_player: i32,
	player_wins: [2]i32,
	two_player_rounds_cleared: i32,
	two_player_round_clear: bool,
	confirmation_active: bool,
	confirmation_index: i32,
	camera_mode: i32,
	texture_style: i32,
	stage: i32,
	wave: i32,
	current_puzzle: i32,
	puzzle_flipped: bool,
	score: i32,
	stage_score: i32,
	iq: i32,
	combo: i32,
	capture_timer: i32,
	capture_multiplier: i32,
	platform_loss_timer: i32,
	platform_loss_forbidden: bool,
	message: [128]u8,
	message_len: int,
	message_time: f32,
	paused: bool,
	attract: bool,
	attract_time: f32,
	attract_cycle: i32,
	camera_yaw: f32,
	camera_pitch: f32,
	camera_distance: f32,
	camera_shake: f32,
	camera_position: rl.Vector3,
	camera_target: rl.Vector3,
	fade: f32,
	fade_target: f32,
	board: Board,
	player: Player,
	assets: Assets,
	save: Save_Data,
	group_data: []u8,
	demo_data: []u8,
	demo_cursor: i32,
	demo_frame: i32,
	demo_buttons: u32,
	demo_elapsed: i32,
	demo_mode: i32,
	demo_timeline_clock: i32,
	demo_timeline_index: i32,
	demo_hold_remaining: i32,
	demo_return_rules: bool,
	movie_data: []u8,
	movie_texture: rl.Texture2D,
	editor_dimension: i32,
	editor_puzzle: i32,
	editor_cursor_x: i32,
	editor_cursor_y: i32,
	editor_playtest: bool,
	editor_fill_type: u8,
	editor_clipboard: [MAX_WIDTH * 10]u8,
	name_entry: [10]u8,
	name_length: i32,
	name_grid_x: i32,
	name_grid_y: i32,
	movie_frame: i32,
	movie_frames: i32,
	movie_width: i32,
	movie_height: i32,
	rng: u64,
}
