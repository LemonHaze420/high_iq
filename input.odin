package high_iq

import rl "raylib"

mapped_gamepad_button :: proc(value: u8) -> rl.GamepadButton {
	switch value {
	case 1: return .RIGHT_FACE_RIGHT
	case 2: return .RIGHT_FACE_LEFT
	case 3: return .RIGHT_FACE_UP
	case: return .RIGHT_FACE_DOWN
	}
}

read_input_for_player :: proc(player_index: i32, mapping: [4]u8 = {0, 1, 2, 3}) -> Input_State {
	input: Input_State
	if player_index == 0 || !rl.IsGamepadAvailable(player_index) {
		input.up = rl.IsKeyDown(.UP) || rl.IsKeyDown(.W)
		input.down = rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S)
		input.left = rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A)
		input.right = rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D)
		input.confirm = rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.Z) || rl.IsKeyPressed(.SPACE)
		input.cancel = rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressed(.X)
		input.marker = rl.IsKeyPressed(.Z) || rl.IsKeyPressed(.SPACE)
		input.detonate = rl.IsKeyPressed(.X)
		input.advantage = rl.IsKeyPressed(.C)
		input.accelerate = rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
		input.pause = rl.IsKeyPressed(.ESCAPE)
	}
	if rl.IsGamepadAvailable(player_index) {
		input.up = input.up || rl.IsGamepadButtonDown(player_index, .LEFT_FACE_UP)
		input.down = input.down || rl.IsGamepadButtonDown(player_index, .LEFT_FACE_DOWN)
		input.left = input.left || rl.IsGamepadButtonDown(player_index, .LEFT_FACE_LEFT)
		input.right = input.right || rl.IsGamepadButtonDown(player_index, .LEFT_FACE_RIGHT)
		input.confirm = input.confirm || rl.IsGamepadButtonPressed(player_index, .RIGHT_FACE_DOWN)
		input.cancel = input.cancel || rl.IsGamepadButtonPressed(player_index, .RIGHT_FACE_RIGHT)
		input.marker = input.marker || rl.IsGamepadButtonPressed(player_index, mapped_gamepad_button(mapping[0]))
		input.detonate = input.detonate || rl.IsGamepadButtonPressed(player_index, mapped_gamepad_button(mapping[1]))
		input.advantage = input.advantage || rl.IsGamepadButtonPressed(player_index, mapped_gamepad_button(mapping[2]))
		input.accelerate = input.accelerate || rl.IsGamepadButtonDown(player_index, mapped_gamepad_button(mapping[3]))
		input.pause = input.pause || rl.IsGamepadButtonPressed(player_index, .MIDDLE_RIGHT)
	}
	return input
}

read_input :: proc() -> Input_State {
	return read_input_for_player(0)
}

menu_step :: proc(input: Input_State) -> i32 {
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) || (rl.IsGamepadAvailable(0) && rl.IsGamepadButtonPressed(0, .LEFT_FACE_UP)) { return -1 }
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) || (rl.IsGamepadAvailable(0) && rl.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN)) { return 1 }
	return 0
}
