package high_iq

set_player_animation_behavior :: proc(player: ^Player, behavior: i32) {
	if player.animation_behavior == behavior && player.animation_timer >= 0 { return }
	sequence := player_animation_sequence(player.character, behavior)
	if len(sequence) == 0 { return }
	player.animation_behavior = behavior
	player.animation_sequence_index = 0
	player.animation_timer = i32(sequence[0].duration)
	player.animation_frame = i32(sequence[0].frame)
	player.animation_held = false
	if behavior == 5 { player.fall_step = 0 }
}

update_player_animation :: proc(player: ^Player) {
	if player.animation_held {
		switch player.animation_behavior {
		case 0, 1, 4, 10:
			set_player_animation_behavior(player, 2)
		case:
		}
	}
	sequence := player_animation_sequence(player.character, player.animation_behavior)
	if len(sequence) == 0 { return }
	if player.animation_timer == 0 {
		player.animation_sequence_index += 1
		if player.animation_sequence_index >= i32(len(sequence)) {
			player.animation_sequence_index = i32(len(sequence) - 1)
		}
		player.animation_timer = i32(sequence[player.animation_sequence_index].duration)
	} else {
		player.animation_timer -= 1
	}
	entry := sequence[player.animation_sequence_index]
	if entry.frame == 0xff {
		player.animation_sequence_index = 0
		player.animation_timer = i32(sequence[0].duration)
	} else if entry.frame == 0xfe {
		player.animation_held = true
		player.animation_timer = 0xff
		player.animation_sequence_index = max(0, player.animation_sequence_index - 1)
	}
	player.animation_frame = i32(sequence[player.animation_sequence_index].frame)
}
