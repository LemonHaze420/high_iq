package high_iq

import "core:os"

SAVE_PATH :: "save.dat"

reset_save :: proc(save: ^Save_Data) {
	save^ = {}
	save.magic = SAVE_MAGIC
	save.version = SAVE_VERSION
	save.music_volume = 0.75
	save.sound_volume = 0.9
	save.button_mapping = {0, 1, 2, 3}
	save.unlock_flags = 1
	save.rankings = DEFAULT_RANKINGS
}

load_save :: proc(save: ^Save_Data) {
	reset_save(save)
	data, err := os.read_entire_file(SAVE_PATH, context.allocator)
	if err != nil { return }
	defer delete(data)
	if len(data) != size_of(Save_Data) { return }
	copy(([^]u8)(rawptr(save))[:size_of(Save_Data)], data)
	if save.magic != SAVE_MAGIC || save.version != SAVE_VERSION {
		reset_save(save)
	}
}

write_save :: proc(save: ^Save_Data) {
	data := ([^]u8)(rawptr(save))[:size_of(Save_Data)]
	_ = os.write_entire_file(SAVE_PATH, data)
}

ranking_qualifies :: proc(game: ^Game) -> bool {
	table := &game.save.rankings[clamp(game.speed_level, 0, 4)]
	last := table[len(table^) - 1]
	return game.iq > last.iq || (game.iq == last.iq && game.score > last.score)
}
unlock_flags_for_iq :: proc(flags: u8, iq: i32) -> u8 {
	if iq > 400 { return flags | 2 }
	return flags
}


submit_ranking :: proc(game: ^Game) {
	entry := Ranking_Entry{name = game.name_entry, score = game.score, iq = game.iq}
	table := &game.save.rankings[clamp(game.speed_level, 0, 4)]
	insert_at := -1
	for index in 0..<len(table^) {
		if game.iq > table[index].iq ||
		   (game.iq == table[index].iq && game.score > table[index].score) {
			insert_at = index
			break
		}
	}
	if insert_at >= 0 {
		for index := len(table^) - 1; index > insert_at; index -= 1 {
			table[index] = table[index - 1]
		}
		table[insert_at] = entry
	}
	game.save.unlock_flags = unlock_flags_for_iq(game.save.unlock_flags, game.iq)
	write_save(&game.save)
}
