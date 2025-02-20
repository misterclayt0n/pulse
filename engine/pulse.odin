package engine

import rl "vendor:raylib"

// 
// Globals
// 

background_color :: rl.Color{28, 28, 28, 255}
text_color :: rl.Color{235, 219, 178, 255}
scroll_smoothness :: 0.2

// Main state of the editor,
Pulse :: struct {
	buffer:         Buffer, // NOTE: This is probably being removed for a window system.
	font:           Font,
	mode:           Vim_Mode,
	command_buffer: Command_Buffer,
	camera:         rl.Camera2D,
	target_x:       f32,
	target_y:       f32,
}

pulse_init :: proc(font_path: string, allocator := context.allocator) -> Pulse {
	buffer := buffer_init(allocator)
	font := load_font_with_codepoints(font_path, 35, text_color, allocator) // Default font
	command_buffer := command_buffer_init(allocator)
	
	return Pulse {
		buffer = buffer,
		font = font,
		mode = .NORMAL,
		command_buffer = command_buffer,
		camera = rl.Camera2D {
			offset = {0, 0},
			target = {0, 0},
			rotation = 0,
			zoom = 1
		},
		target_x = 0,
		target_y = 0,
	}
}

pulse_update :: proc(p: ^Pulse) {
	// TODO: Move this into a keybind module.
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

	pulse_scroll(p)
}

// TODO: Mouse interaction.
pulse_scroll :: proc(p: ^Pulse) {
    // Vertical scrolling logic
    line_height     := f32(p.font.size) + p.font.spacing
    cursor_world_y  := 10 + f32(p.buffer.cursor.line) * line_height  // World Y of cursor
    window_height   := f32(rl.GetScreenHeight())
    margin_y        :: 100.0
    document_height := 10 + f32(p.buffer.line_count) * line_height
    max_target_y    := max(0, document_height - window_height)

    // Calculate cursor position relative to current viewport
    cursor_screen_y := cursor_world_y - p.camera.target.y

    if cursor_screen_y < margin_y {
        p.target_y = cursor_world_y - margin_y
    } else if cursor_screen_y > (window_height - margin_y) {
        p.target_y = cursor_world_y - (window_height - margin_y)
    }
    // NOTE: Clamp to prevent showing empty space beyond the document.
    p.target_y = clamp(p.target_y, 0, max_target_y) 

    // Horizontal scrolling logic. 
	text_width: f32
	{
		temp := get_text_before_cursor(&p.buffer)
		defer delete(temp)
		text_width = rl.MeasureTextEx(p.font.ray_font, cstring(raw_data(temp)), f32(p.font.size), p.font.spacing).x
	}

    cursor_x       := f32(10) + text_width
    window_width   := f32(rl.GetScreenWidth())
    viewport_left  := p.camera.target.x
    viewport_right := viewport_left + window_width
	margin_x       :: 50.0

    if cursor_x < viewport_left + margin_x {
        p.target_x = cursor_x - margin_x 
    }
    if cursor_x > viewport_right - margin_x {
        p.target_x = cursor_x - (window_width - margin_x) 
    }

    // Lerp the camera's current position (p.camera.target) torwards the new 
	// target (p.target) for a smooth scrolling effect.
    p.camera.target.y = rl.Lerp(p.camera.target.y, p.target_y, scroll_smoothness)
    p.camera.target.x = rl.Lerp(p.camera.target.x, p.target_x, scroll_smoothness)
}

pulse_draw :: proc(p: ^Pulse) {
	rl.ClearBackground(background_color)
	rl.BeginMode2D(p.camera)
	buffer_draw(&p.buffer, {10, 10}, p.font)
	rl.EndMode2D()
}

