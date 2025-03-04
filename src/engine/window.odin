package engine

import rl "vendor:raylib"

Window :: struct {
	buffer:   ^Buffer,
	rect:     rl.Rectangle,
	scroll:   rl.Vector2,
	is_focus: bool,
	target_x: f32,
	target_y: f32,
}

window_init :: proc(buffer: ^Buffer, rect: rl.Rectangle, allocator := context.allocator) -> Window {
	return Window {
		buffer = buffer,
		rect = rect,
		scroll = {0, 0},
		is_focus = true,
		target_x = 0,
		target_y = 0,
	}
}

window_update :: proc(w: ^Window) {
	buffer_update_line_starts(w.buffer)
}

window_scroll :: proc(w: ^Window, font: Font) {
	// Vertical scrolling logic.
	line_height := f32(font.size) + font.spacing
	cursor_world_y := 10 + f32(w.buffer.cursor.line) * line_height // World Y of cursor.
	window_height := f32(rl.GetScreenHeight())
	margin_y :: 100.0
	line_count := f32(len(w.buffer.line_starts))
	document_height := 10 + line_count * line_height
	max_target_y := max(0, document_height - window_height)

	// Calculate cursor position relative to current viewport.
	cursor_screen_y := cursor_world_y - w.scroll.y

	if cursor_screen_y < margin_y {
		w.target_y = cursor_world_y - margin_y
	} else if cursor_screen_y > (window_height - margin_y) {
		w.target_y = cursor_world_y - (window_height - margin_y)
	}
	// NOTE: Clamp to prevent showing empty space beyond the document.
	w.target_y = clamp(w.target_y, 0, max_target_y)

	// Horizontal scrolling logic.
	line_start := w.buffer.line_starts[w.buffer.cursor.line]
	text_slice := w.buffer.data[line_start:w.buffer.cursor.pos]
	temp_len := len(text_slice)
	temp := make([]u8, temp_len + 1)

	defer delete(temp)
	if temp_len > 0 do copy(temp, text_slice)
	temp[temp_len] = 0

	text_width :=
		rl.MeasureTextEx(font.ray_font, cstring(raw_data(temp)), f32(font.size), font.spacing).x
	cursor_x := f32(10) + text_width
	window_width := f32(rl.GetScreenWidth())
	viewport_left := w.scroll.x
	viewport_right := viewport_left + window_width
	margin_x :: 50.0

	if cursor_x < viewport_left + margin_x {
		w.target_x = cursor_x - margin_x
	}
	if cursor_x > viewport_right - margin_x {
		w.target_x = cursor_x - (window_width - margin_x)
	}

	// Lerp the camera's current position (p.camera.target) torwards the new
	// target (p.target) for a smooth scrolling effect.
    w.scroll.y = rl.Lerp(w.scroll.y, w.target_y, scroll_smoothness)
    w.scroll.x = rl.Lerp(w.scroll.x, w.target_x, scroll_smoothness)
}

window_draw :: proc(w: ^Window, font: Font, allocator := context.allocator) {
    screen_width := i32(w.rect.width)
    screen_height := i32(w.rect.height)
    line_height := f32(font.size) + font.spacing

    // Calculate visible lines based on w scroll position.
    first_visible_line := int((w.scroll.y - 10) / line_height)
    last_visible_line := int((w.scroll.y + f32(screen_height) + 10) / line_height)
    first_visible_line = max(0, first_visible_line)
    last_visible_line = min(len(w.buffer.line_starts) - 1, last_visible_line)

    ctx := Draw_Context {
        position = rl.Vector2{w.rect.x + 10, w.rect.y + 10},
        screen_width = screen_width,
        screen_height = screen_height,
        first_line = first_visible_line,
        last_line = last_visible_line,
        line_height = int(line_height),
    }

    // Set up camera for w.
    camera := rl.Camera2D {
        offset = {w.rect.x, w.rect.y},
        target = {w.scroll.x, w.scroll.y},
        rotation = 0,
        zoom = 1,
    }

    rl.BeginMode2D(camera)
    defer rl.EndMode2D()

    buffer_draw(w.buffer, font, ctx, allocator)
}


