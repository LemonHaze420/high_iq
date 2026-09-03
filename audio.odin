package high_iq

import "core:math"
import "core:os"
import rl "raylib"

Sound_Spec :: struct { program, tone, note: int }

SOUND_SPECS := [54]Sound_Spec{
	{0,0,1}, {0,1,2}, {0,2,3}, {0,4,4}, {0,6,5}, {0,8,6}, {0,10,7}, {0,12,8}, {0,14,9},
	{1,0,10}, {1,2,11}, {1,4,12}, {1,6,13}, {1,8,14}, {1,10,15}, {1,12,16}, {1,14,17},
	{2,0,18}, {2,1,18}, {2,2,19}, {2,4,20}, {2,6,21}, {2,8,22}, {2,10,23}, {2,12,24},
	{3,0,25}, {3,2,26}, {3,4,27}, {3,6,28}, {3,8,29}, {3,10,30}, {3,12,31}, {3,14,32},
	{4,0,60}, {4,2,61}, {4,4,62}, {4,6,63}, {4,8,64}, {4,9,65}, {4,10,66}, {4,11,67},
	{4,12,68}, {4,13,69}, {4,14,70},
	{5,0,64}, {5,2,61}, {5,3,61}, {5,4,62}, {5,6,63}, {5,8,64}, {5,9,64}, {5,10,65},
	{5,12,66}, {5,14,67},
}
Sound_Effect :: enum i32 {
	Platform_Loss = 0x03,
	Marker_Set = 0x04,
	Capture = 0x0b,
	Advantage = 0x0f,
	Menu_Move = 0x18,
	Title_Confirm = 0x1b,
	Game_Start = 0x1d,
	Spike_Step_A = 0x27,
	Step_A = 0x28,
	Step_B = 0x29,
	Spike_Step_B = 0x2b,
}


VOICE_FILES := [5]string{
	"IQ/SOUND/KI_00.XA",
	"IQ/SOUND/KI_01.XA",
	"IQ/SOUND/FO_00.XA",
	"IQ/SOUND/AD_00.XA",
	"IQ/SOUND/AD_01.XA",
}

Voice_Spec :: struct { file, channel: int }

// original g_cdTrackTable entries 19..53; events 35 and 36 both map to
// KI_00 channel 1, matching the table encoded in SCUS_941.81.
VOICE_SPECS := [35]Voice_Spec{
	{0,0}, {0,1}, {0,2}, {0,3}, {0,4}, {0,5}, {0,6}, {0,7},
	{1,0}, {1,1}, {1,2}, {1,3}, {1,4}, {1,5}, {1,6}, {1,7},
	{0,1}, {0,1},
	{2,0}, {2,1}, {2,2}, {2,3}, {2,4}, {2,5}, {2,6},
	{3,0}, {3,1}, {3,2}, {3,3}, {3,4}, {3,5}, {3,6}, {3,7},
	{4,0}, {4,1},
}


Audio_Bank :: struct {
	sounds: [54]rl.Sound,
	loaded: [54]bool,
	music: [4]rl.Sound,
	music_loaded: [4]bool,
	announcements: [9]rl.Sound,
	announcement_loaded: [9]bool,
	voices: [35]rl.Sound,
	voice_loaded: [35]bool,
	current_music: i32,
	movie: rl.Sound,
	movie_loaded: bool,
}

audio_bank: Audio_Bank

read_audio_u16 :: proc(data: []u8, offset: int) -> u16 {
	return u16(data[offset]) | u16(data[offset + 1]) << 8
}

decode_vab_sound :: proc(header, body: []u8, program, tone, note: int) -> (rl.Sound, bool) {
	tone_offset := 32 + 128 * 16 + (program * 16 + tone) * 32
	if tone_offset + 32 > len(header) { return {}, false }
	vag := int(read_audio_u16(header, tone_offset + 22))
	vag_count := int(read_audio_u16(header, 22))
	offset_table := 32 + 128 * 16 + int(read_audio_u16(header, 18)) * 16 * 32
	if vag <= 0 || vag > vag_count || offset_table + (vag_count + 1) * 2 > len(header) {
		return {}, false
	}

	byte_offset := 0
	for index in 1..<vag {
		byte_offset += int(read_audio_u16(header, offset_table + index * 2)) * 8
	}
	byte_count := int(read_audio_u16(header, offset_table + vag * 2)) * 8
	if byte_offset + byte_count > len(body) { return {}, false }

	samples := make([]i16, byte_count / 16 * 28)
	sample_count := 0
	history_1, history_2: i32
	filter_1 := [5]i32{0, 60, 115, 98, 122}
	filter_2 := [5]i32{0, 0, -52, -55, -60}
	for block_offset := byte_offset; block_offset + 16 <= byte_offset + byte_count; block_offset += 16 {
		control := body[block_offset]
		shift := u32(control & 15)
		predictor := int(control >> 4)
		if predictor >= len(filter_1) { predictor = 0 }
		for sample_index in 0..<28 {
			packed := body[block_offset + 2 + sample_index / 2]
			nibble := i32((packed >> u8((sample_index & 1) * 4)) & 15)
			if nibble >= 8 { nibble -= 16 }
			value := (nibble << 12) >> shift
			value += (history_1 * filter_1[predictor] + history_2 * filter_2[predictor] + 32) >> 6
			value = clamp(value, i32(-32768), i32(32767))
			samples[sample_count] = i16(value)
			sample_count += 1
			history_2 = history_1
			history_1 = value
		}
		if body[block_offset + 1] & 1 != 0 { break }
	}
	if sample_count == 0 { delete(samples); return {}, false }

	center := int(header[tone_offset + 4])
	fine := int(header[tone_offset + 5])
	semitones := f64(note - center) + f64(fine) / 128.0
	sample_rate := u32(clamp(44100.0 * math.pow(2.0, semitones / 12.0), 4000.0, 192000.0))
	wave := rl.Wave{u32(sample_count), sample_rate, 16, 1, raw_data(samples)}
	sound := rl.LoadSoundFromWave(wave)
	delete(samples)
	return sound, true
}

is_str_video_sector :: proc(data: []u8, offset: int) -> bool {
	return offset + 4 <= len(data) && data[offset] == 0x60 &&
		data[offset + 1] == 0x01 && data[offset + 2] == 0x01 && data[offset + 3] == 0x80
}

decode_xa_sectors :: proc(data: []u8, channel: int, movie_stream: bool, sample_rate: u32) -> (rl.Sound, bool) {
	sector_count := len(data) / 2048
	selected_count := 0
	for sector in 0..<sector_count {
		offset := sector * 2048
		selected := !is_str_video_sector(data, offset)
		if !movie_stream { selected = sector % 8 == channel }
		if selected { selected_count += 1 }
	}
	if selected_count == 0 { return {}, false }
	samples := make([]i16, selected_count * 16 * 112 * 2)
	sample_count := 0
	history_1, history_2: [2]i32
	filter_1 := [5]i32{0, 60, 115, 98, 122}
	filter_2 := [5]i32{0, 0, -52, -55, -60}
	for sector in 0..<sector_count {
		sector_offset := sector * 2048
		selected := !is_str_video_sector(data, sector_offset)
		if !movie_stream { selected = sector % 8 == channel }
		if !selected { continue }
		for group in 0..<16 {
			group_offset := sector_offset + group * 128
			for pair in 0..<4 {
				for sample_index in 0..<28 {
					for output_channel in 0..<2 {
						unit := pair * 2 + output_channel
						control := data[group_offset + unit]
						shift := u32(control & 15)
						predictor := int(control >> 4)
						if predictor >= len(filter_1) { predictor = 0 }
						packed := data[group_offset + 16 + sample_index * 4 + unit / 2]
						nibble := i32((packed >> u8((unit & 1) * 4)) & 15)
						if nibble >= 8 { nibble -= 16 }
						value := (nibble << 12) >> shift
						value += (history_1[output_channel] * filter_1[predictor] +
							history_2[output_channel] * filter_2[predictor] + 32) >> 6
						value = clamp(value, i32(-32768), i32(32767))
						samples[sample_count] = i16(value)
						sample_count += 1
						history_2[output_channel] = history_1[output_channel]
						history_1[output_channel] = value
					}
				}
			}
		}
	}
	wave := rl.Wave{u32(sample_count / 2), sample_rate, 16, 2, raw_data(samples)}
	sound := rl.LoadSoundFromWave(wave)
	delete(samples)
	return sound, true
}

decode_xa_channel :: proc(data: []u8, channel: int) -> (rl.Sound, bool) {
	return decode_xa_sectors(data, channel, false, 37800)
}

load_movie_audio :: proc(data: []u8, frame_count: i32) -> bool {
	if audio_bank.movie_loaded {
		rl.StopSound(audio_bank.movie)
		rl.UnloadSound(audio_bank.movie)
		audio_bank.movie_loaded = false
	}
	audio_sectors := 0
	for sector in 0..<len(data) / 2048 {
		if !is_str_video_sector(data, sector * 2048) { audio_sectors += 1 }
	}
	if audio_sectors == 0 || frame_count <= 0 { return false }
	sample_frames := audio_sectors * 16 * 112
	sample_rate := u32((sample_frames * 15 + int(frame_count) / 2) / int(frame_count))
	audio_bank.movie, audio_bank.movie_loaded =
		decode_xa_sectors(data, 0, true, sample_rate)
	return audio_bank.movie_loaded
}

play_movie_audio :: proc(volume: f32) {
	if !audio_bank.movie_loaded { return }
	rl.SetSoundVolume(audio_bank.movie, volume)
	rl.PlaySound(audio_bank.movie)
}

stop_movie_audio :: proc() {
	if audio_bank.movie_loaded { rl.StopSound(audio_bank.movie) }
}

init_audio :: proc() {
	rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() { return }
	root := iq_asset_root()
	header, header_error := os.read_entire_file(asset_path(root, "IQ/SOUND/IQ.VH"), context.allocator)
	body, body_error := os.read_entire_file(asset_path(root, "IQ/SOUND/IQ.VB"), context.allocator)
	if header_error != nil || body_error != nil {
		if header_error == nil { delete(header) }
		if body_error == nil { delete(body) }
		return
	}
	defer delete(header)
	defer delete(body)

	for index in 0..<len(SOUND_SPECS) {
		spec := SOUND_SPECS[index]
		audio_bank.sounds[index], audio_bank.loaded[index] =
			decode_vab_sound(header, body, spec.program, spec.tone, spec.note)
	}
	iq00, iq00_error := os.read_entire_file(asset_path(root, "IQ/SOUND/IQ00.XA"), context.allocator)
	if iq00_error == nil {
		for channel in 0..<len(audio_bank.music) {
			audio_bank.music[channel], audio_bank.music_loaded[channel] = decode_xa_channel(iq00, channel)
		}
		delete(iq00)
	}
	iq01, iq01_error := os.read_entire_file(asset_path(root, "IQ/SOUND/IQ01.XA"), context.allocator)
	if iq01_error == nil {
		for stage in 0..<7 {
			audio_bank.announcements[stage], audio_bank.announcement_loaded[stage] =
				decode_xa_channel(iq01, stage + 1)
		}
		delete(iq01)
	}
	iq02, iq02_error := os.read_entire_file(asset_path(root, "IQ/SOUND/IQ02.XA"), context.allocator)
	if iq02_error == nil {
		for channel in 0..<2 {
			audio_bank.announcements[channel + 7], audio_bank.announcement_loaded[channel + 7] =
				decode_xa_channel(iq02, channel)
		}
		delete(iq02)
	}
	for file_index in 0..<len(VOICE_FILES) {
		xa, xa_error := os.read_entire_file(asset_path(root, VOICE_FILES[file_index]), context.allocator)
		if xa_error != nil { continue }
		for voice_index in 0..<len(VOICE_SPECS) {
			spec := VOICE_SPECS[voice_index]
			if spec.file != file_index { continue }
			audio_bank.voices[voice_index], audio_bank.voice_loaded[voice_index] =
				decode_xa_channel(xa, spec.channel)
		}
		delete(xa)
	}
	audio_bank.current_music = -1
}

shutdown_audio :: proc() {
	for index in 0..<len(audio_bank.sounds) {
		if audio_bank.loaded[index] { rl.UnloadSound(audio_bank.sounds[index]) }
	}
	for index in 0..<len(audio_bank.music) {
		if audio_bank.music_loaded[index] { rl.UnloadSound(audio_bank.music[index]) }
	}
	for index in 0..<len(audio_bank.announcements) {
		if audio_bank.announcement_loaded[index] { rl.UnloadSound(audio_bank.announcements[index]) }
	}
	for index in 0..<len(audio_bank.voices) {
		if audio_bank.voice_loaded[index] { rl.UnloadSound(audio_bank.voices[index]) }
	}
	if audio_bank.movie_loaded { rl.UnloadSound(audio_bank.movie) }
	if rl.IsAudioDeviceReady() { rl.CloseAudioDevice() }
}

play_effect :: proc(effect: Sound_Effect, volume: f32) {
	id := int(effect)
	if id < 0 || id >= len(audio_bank.sounds) || !audio_bank.loaded[id] { return }
	rl.SetSoundVolume(audio_bank.sounds[id], volume)
	rl.PlaySound(audio_bank.sounds[id])
}

play_voice_event :: proc(event_id: int, volume: f32) {
	index := event_id - 19
	if index < 0 || index >= len(audio_bank.voices) || !audio_bank.voice_loaded[index] { return }
	rl.SetSoundVolume(audio_bank.voices[index], volume)
	rl.PlaySound(audio_bank.voices[index])
}

voice_event_count :: proc() -> int {
	count := 0
	for loaded in audio_bank.voice_loaded {
		if loaded { count += 1 }
	}
	return count
}

play_stage_announcement :: proc(stage: i32, volume: f32) {
	index := clamp(stage, 0, 8)
	for other in 0..<len(audio_bank.announcements) {
		if audio_bank.announcement_loaded[other] && rl.IsSoundPlaying(audio_bank.announcements[other]) {
			rl.StopSound(audio_bank.announcements[other])
		}
	}
	if !audio_bank.announcement_loaded[index] { return }
	rl.SetSoundVolume(audio_bank.announcements[index], volume)
	rl.PlaySound(audio_bank.announcements[index])
}

stop_stage_music :: proc() {
	if audio_bank.current_music >= 0 && audio_bank.current_music < len(audio_bank.music) &&
			audio_bank.music_loaded[audio_bank.current_music] {
		rl.StopSound(audio_bank.music[audio_bank.current_music])
	}
	audio_bank.current_music = -1
}

play_stage_music :: proc(stage: i32, volume: f32) {
	stage_tracks := [9]i32{0, 1, 2, 3, 0, 1, 2, 3, 1}
	index := stage_tracks[clamp(stage, 0, 8)]
	if audio_bank.current_music >= 0 && audio_bank.current_music != index &&
			audio_bank.music_loaded[audio_bank.current_music] {
		rl.StopSound(audio_bank.music[audio_bank.current_music])
	}
	audio_bank.current_music = index
	if !audio_bank.music_loaded[index] { return }
	rl.SetSoundVolume(audio_bank.music[index], volume)
	if !rl.IsSoundPlaying(audio_bank.music[index]) { rl.PlaySound(audio_bank.music[index]) }
}
