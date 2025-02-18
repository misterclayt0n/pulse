package engine

import rl "vendor:raylib"

// 
// Globals
// 

background_color :: rl.Color{28, 28, 28, 255}
text_color :: rl.Color{235, 219, 178, 255}

// Main state of the editor,
Pulse :: struct {
	buffer:         Buffer, // NOTE: This is probably being removed for a window system.
	font:           Font,
	mode:           Vim_Mode,
	command_buffer: Command_Buffer
}

pulse_init :: proc(font_path: string, allocator := context.allocator) -> Pulse {
	buffer := buffer_init(allocator)
	font := load_font_with_codepoints(font_path, 100, text_color, allocator) // Default font
	command_buffer := command_buffer_init(allocator)
	
	return Pulse {
		buffer = buffer,
		font = font,
		mode = .NORMAL,
		command_buffer = command_buffer,
	}
}

pulse_update :: proc(p: ^Pulse) {
	#partial switch p.mode {
	case .NORMAL:
		if rl.IsKeyPressed(.I) do change_mode(&p.buffer, &p.mode, .INSERT)
		if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressedRepeat(.LEFT) || rl.IsKeyPressed(.H) || rl.IsKeyPressedRepeat(.H) do buffer_move_cursor(&p.buffer, .LEFT)
		if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) || rl.IsKeyPressed(.L) || rl.IsKeyPressedRepeat(.L) do buffer_move_cursor(&p.buffer, .RIGHT)
		if rl.IsKeyPressed(.UP) || rl.IsKeyPressedRepeat(.UP) || rl.IsKeyPressed(.K) || rl.IsKeyPressedRepeat(.K) do buffer_move_cursor(&p.buffer, .UP)
		if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressedRepeat(.DOWN) || rl.IsKeyPressed(.J) || rl.IsKeyPressedRepeat(.J) do buffer_move_cursor(&p.buffer, .DOWN)
	case .INSERT:
		if rl.IsKeyPressed(.ESCAPE) do change_mode(&p.buffer, &p.mode, .NORMAL) 
		if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressedRepeat(.ENTER) do buffer_insert_char(&p.buffer, '\n')
		if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) do buffer_delete_char(&p.buffer)

		key := rl.GetCharPressed()
		for key != 0 {
			buffer_insert_char(&p.buffer, rune(key))
			key = rl.GetCharPressed()
		} 
	}
}

pulse_draw :: proc(p: ^Pulse) {
	rl.ClearBackground(background_color)
	buffer_draw(&p.buffer, {10, 10}, p.font)
}

