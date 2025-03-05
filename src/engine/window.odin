package engine

import rl "vendor:raylib"

Window :: struct {
	buffer:     ^Buffer,
	cursor:     Cursor,
	rect:       rl.Rectangle,
	scroll:     rl.Vector2,
	is_focus:   bool,
	target_x:   f32,
	target_y:   f32,
	split_type: Split_Type,
	parent:     ^Window,
	children:   [2]^Window,
}

Split_Type :: enum {
	NONE,
	VERTICAL,
	HORIZONTAL,
}

window_init :: proc(
	buffer: ^Buffer,
	rect: rl.Rectangle,
	allocator := context.allocator,
) -> Window {
	return Window {
		buffer = buffer,
		rect = rect,
		scroll = {0, 0},
		is_focus = true,
		target_x = 0,
		target_y = 0,
		cursor = Cursor {
			pos           = 0,
			sel           = 0,
			line          = 0,
			col           = 0,
			preferred_col = -1,
			style         = .BLOCK,
			color         = rl.GRAY,
			blink         = false, // FIX: This shit.
		},
	}
}

window_update :: proc(w: ^Window) {
	buffer_update_line_starts(w)
}

window_scroll :: proc(w: ^Window, font: Font) {
	// Vertical scrolling logic.
	line_height := f32(font.size) + font.spacing
	cursor_world_y := 10 + f32(w.cursor.line) * line_height // World Y of cursor.
	window_height := w.rect.height
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
	line_start := w.buffer.line_starts[w.cursor.line]
	text_slice := w.buffer.data[line_start:w.cursor.pos]
	temp_len := len(text_slice)
	temp := make([]u8, temp_len + 1)

	defer delete(temp)
	if temp_len > 0 do copy(temp, text_slice)
	temp[temp_len] = 0

	text_width :=
		rl.MeasureTextEx(font.ray_font, cstring(raw_data(temp)), f32(font.size), font.spacing).x
	cursor_x := f32(10) + text_width
	window_width := w.rect.width
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

	// Calculate visible lines based on w scroll position..
	first_visible_line := int((w.scroll.y - 10) / line_height)
	last_visible_line := int((w.scroll.y + f32(screen_height) + 10) / line_height)
	first_visible_line = max(0, first_visible_line)
	last_visible_line = min(len(w.buffer.line_starts) - 1, last_visible_line)

	// Set up camera to use scroll position but draw text at fixed origin.
	camera := rl.Camera2D {
		offset   = {w.rect.x, w.rect.y}, // Screen position of the window.
		target   = {w.scroll.x, w.scroll.y}, // Scroll offset in text space.
		rotation = 0,
		zoom     = 1,
	}

	// Set scissor to strictly clip to window bounds.
	rl.BeginScissorMode(i32(w.rect.x), i32(w.rect.y), i32(w.rect.width), i32(w.rect.height))
	defer rl.EndScissorMode()

	rl.BeginMode2D(camera)
	defer rl.EndMode2D()

	ctx := Draw_Context {
		position      = {10, 10},
		screen_width  = i32(w.rect.width),
		screen_height = i32(w.rect.height),
		first_line    = first_visible_line,
		last_line     = last_visible_line,
		line_height   = int(line_height),
	}

	buffer_draw(w, font, ctx, allocator)
}

window_split_vertical :: proc(p: ^Pulse, w: ^Window, allocator := context.allocator) {
	w.split_type = .VERTICAL

	original_rect := w.rect
	new_width := original_rect.width / 2

	w.rect.width = new_width

	// Right side.
	new_window := window_init(
		w.buffer,
		rl.Rectangle {
			x = original_rect.x + new_width,
			y = original_rect.y,
			width = new_width,
			height = original_rect.height,
		},
		allocator,
	)

	new_window.is_focus = false
	new_window.scroll = w.scroll
	new_window.cursor = w.cursor

	// w.children[0] = w // NOTE: Self-reference isn't needed here, but keeping structure.
	w.children[1] = new(Window, allocator)
	w.children[1]^ = new_window
	new_window.parent = w
	// w.children[1] = &new_window

	append(&p.windows, new_window)

	window_update(w)
	window_update(&new_window)
}

window_resize_tree :: proc(w: ^Window, new_rect: rl.Rectangle) {
	// Update this window's rectangle
	w.rect = new_rect

	if w.split_type == .NONE do return // Early exit for leaf nodes

	#partial switch w.split_type {
	case .VERTICAL:
		if w.children[0] != nil && w.children[1] != nil {
			split_pos := new_rect.width / 2
			window_resize_tree(w.children[0], {new_rect.x, new_rect.y, split_pos, new_rect.height})
			window_resize_tree(
				w.children[1],
				{new_rect.x + split_pos, new_rect.y, new_rect.width - split_pos, new_rect.height},
			)
		}
	case .HORIZONTAL:
		if w.children[0] != nil && w.children[1] != nil {
			split_pos := new_rect.height / 2
			window_resize_tree(w.children[0], {new_rect.x, new_rect.y, new_rect.width, split_pos})
			window_resize_tree(
				w.children[1],
				{new_rect.x, new_rect.y + split_pos, new_rect.width, new_rect.height - split_pos},
			)
		}
	}
}
