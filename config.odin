package high_iq

STAGES := [STAGE_COUNT]Stage_Config{
	{4, 15, {Wave_Config{6, 2}, {6, 2}, {9, 3}, {12, 4}}},
	{4, 28, {Wave_Config{15, 5}, {15, 5}, {18, 6}, {18, 6}}},
	{5, 27, {Wave_Config{12, 4}, {15, 5}, {18, 6}, {18, 6}}},
	{5, 32, {Wave_Config{14, 7}, {14, 7}, {16, 8}, {16, 8}}},
	{6, 33, {Wave_Config{18, 6}, {18, 6}, {21, 7}, {21, 7}}},
	{6, 35, {Wave_Config{16, 8}, {16, 8}, {18, 9}, {18, 9}}},
	{7, 35, {Wave_Config{21, 7}, {21, 7}, {24, 8}, {24, 8}}},
	{7, 36, {Wave_Config{16, 8}, {18, 9}, {18, 9}, {18, 9}}},
	{7, 25, {Wave_Config{9, 9}, {9, 9}, {9, 9}, {9, 9}}},
}

INTERNAL_WIDTH :: 640
INTERNAL_HEIGHT :: 480
TILE_SIZE :: 1.0
FIXED_DT :: 1.0 / 60.0
SAVE_MAGIC :: u32(0x48474951) // save-file signature: "high iq"
SAVE_VERSION :: u32(6)


IQ_DEFAULT_RANKINGS :: [10]Ranking_Entry{
	{name = {'D', 'I', 'L', 'L', 'O', 'N', 0, 0, 0, 0}, score = 559400, iq = 241},
	{name = {'S', 'U', 'S', 'A', 'N', ' ', 'M', '.', 0, 0}, score = 472100, iq = 215},
	{name = {'N', 'O', 'U', 'R', 'A', 'I', 0, 0, 0, 0}, score = 447600, iq = 214},
	{name = {'C', 'H', 'R', 'I', 'S', 0, 0, 0, 0, 0}, score = 430700, iq = 185},
	{name = {'T', 'A', 'K', 'U', ' ', 'I', '.', 0, 0, 0}, score = 416100, iq = 180},
	{name = {'J', 'O', 'H', 'N', ' ', 'R', '.', 0, 0, 0}, score = 400600, iq = 179},
	{name = {'J', 'U', 'A', 'N', ' ', 'M', '.', 0, 0, 0}, score = 394900, iq = 170},
	{name = {'J', 'A', 'S', 'O', 'N', ' ', 'F', '.', 0, 0}, score = 387200, iq = 159},
	{name = {'Y', 'A', 'M', 'A', 'M', 'O', 'T', 'O', 0, 0}, score = 383600, iq = 158},
	{name = {'K', 'E', 'N', 'J', 'I', 0, 0, 0, 0, 0}, score = 372800, iq = 156},
}

DEFAULT_RANKINGS :: [5][10]Ranking_Entry{
	IQ_DEFAULT_RANKINGS, {}, {}, {}, {},
}
