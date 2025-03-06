package engine

import "core:fmt"
import rl "vendor:raylib"

Window :: struct {
	buffer:   ^Buffer,
	cursor:   Cursor,
	rect:     rl.Rectangle,
	scroll:   rl.Vector2,
	is_focus: bool,
	target_x: f32,
	target_y: f32,
}

Split_Type :: enum {
	NONE,
	VERTICAL,
	HORIZONTAL,
}

Split_Edge :: struct {
	type:       Split_Type,
	start, end: rl.Vector2,
}

window_init :: proc(
	buffer: ^Buffer,
	rect: rl.Rectangle,
	allocator := context.allocator,
) -> Window {
	assert(buffer != nil, "Buffer must be valid")
	assert(rect.width >= 0 && rect.height >= 0, "Window dimensions must be non-negative")

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
	assert(w != nil, "Window must be valid")
	buffer_update_line_starts(w)
}

// FIX: window does not scroll on empty buffers, like if I press enter endlessly it does not scroll at all.
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
	assert(w.cursor.line >= 0 && w.cursor.line <= len(w.buffer.line_starts), "Cursor line index out of bounds")
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
	w.scroll.y = rl.Lerp(w.scroll.y, w.target_y, SCROLL_SMOOTHNESS )
	w.scroll.x = rl.Lerp(w.scroll.x, w.target_x, SCROLL_SMOOTHNESS )
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

window_split_vertical :: proc(p: ^Pulse, allocator := context.allocator) {
	assert(len(p.windows) > 0, "Cannot split on an empty window list")
	assert(p.windows[0].buffer != nil, "Root window has corrupt buffer")

	if p.split_type != .NONE {
		window_remove_split(p)
	}

	p.split_type = .VERTICAL

	screen_width := f32(rl.GetScreenWidth())
	screen_height := f32(rl.GetScreenHeight())
	split_pos := screen_width * 0.5
	assert(split_pos > 0 && split_pos < screen_width, "Invalid vertical split position")

	if len(p.windows) > 0 {
		p.windows[0].rect = rl.Rectangle {
			x      = 0,
			y      = 0,
			width  = split_pos,
			height = screen_height,
		}
	}

	if len(p.windows) == 1 {
		new_window := window_init(
			p.windows[0].buffer,
			rl.Rectangle {
				x = split_pos,
				y = 0,
				width = screen_width - split_pos,
				height = screen_height,
			},
			allocator,
		)

		new_window.scroll = p.windows[0].scroll
		new_window.cursor = p.windows[0].cursor
		new_window.is_focus = false

		append(&p.windows, new_window)
		p.current_window = &p.windows[0]
	} else if len(p.windows) > 1 {
		p.windows[1].rect = rl.Rectangle {
			x      = split_pos,
			y      = 0,
			width  = screen_width - split_pos,
			height = screen_height,
		}
	}

	for &w in p.windows {
		window_update(&w)
	}
}

window_split_horizontal :: proc(p: ^Pulse, allocator := context.allocator) {
	assert(len(p.windows) > 0, "Cannot split on an empty window list")
	assert(p.windows[0].buffer != nil, "Root window has corrupt buffer")

	if p.split_type != .NONE {
		window_remove_split(p)
	}

	p.split_type = .HORIZONTAL

	screen_width := f32(rl.GetScreenWidth())
	screen_height := f32(rl.GetScreenHeight())
	split_pos := screen_height * 0.5
	assert(split_pos > 0 && split_pos < screen_width, "Invalid horizontal split position")

	if len(p.windows) > 0 {
		p.windows[0].rect = rl.Rectangle {
			x      = 0,
			y      = 0,
			width  = screen_width,
			height = split_pos,
		}
	}

	if len(p.windows) == 1 {
		new_window := window_init(
			p.windows[0].buffer,
			rl.Rectangle {
				x = 0,
				y = split_pos,
				width = screen_width,
				height = screen_height - split_pos,
			},
			allocator,
		)

		new_window.scroll = p.windows[0].scroll
		new_window.cursor = p.windows[0].cursor
		new_window.is_focus = false

		append(&p.windows, new_window)
		p.current_window = &p.windows[0]
	} else if len(p.windows) > 1 {
		p.windows[1].rect = rl.Rectangle {
			x      = 0,
			y      = split_pos,
			width  = screen_width,
			height = screen_height - split_pos,
		}
	}

	for &w in p.windows {
		window_update(&w)
	}
}


window_remove_split :: proc(p: ^Pulse) {
	if p.split_type == .NONE || len(p.windows) <= 1 {
		return
	}

	focused_window_index := -1
	for i := 0; i < len(p.windows); i += 1 {
		if p.windows[i].is_focus {
			focused_window_index = i
			break
		}
	}

	if focused_window_index == -1 {
		focused_window_index = 0
	}

	p.windows[focused_window_index].rect = rl.Rectangle {
		x      = 0,
		y      = 0,
		width  = f32(rl.GetScreenWidth()),
		height = f32(rl.GetScreenHeight()),
	}

	for i := len(p.windows) - 1; i >= 0; i -= 1 {
		if i != focused_window_index {
			ordered_remove(&p.windows, i)
		}
	}

	p.current_window = &p.windows[0]
	p.split_type = .NONE

	window_update(p.current_window)
}

window_close_current :: proc(p: ^Pulse) {
	old_count := len(p.windows)
	defer assert(len(p.windows) == old_count - 1, "Close failed to remove window")

	if len(p.windows) <= 1 do return

	current_index := -1
	for &w, i in p.windows {
		if &w == p.current_window {
			current_index += 1
			break
		}
	}
	if current_index == -1 do return

	// Remove current window.
	ordered_remove(&p.windows, current_index)

	if len(p.windows) == 1 {
		p.current_window = &p.windows[0]
		p.current_window.rect = {
			x      = 0,
			y      = 0,
			width  = f32(rl.GetScreenWidth()),
			height = f32(rl.GetScreenHeight()),
		}
		p.current_window.is_focus = true
		p.split_type = .NONE
		window_update(p.current_window)

		defer {
			assert(p.split_type == .NONE, "Close left split type active")
			assert(
				p.current_window.rect.width == f32(rl.GetScreenWidth()),
				"Remaining window width mismatch",
			)
			assert(
				p.current_window.rect.height == f32(rl.GetScreenHeight()),
				"Remaining window height mismatch",
			)
		}
	}
}

window_resize_tree :: proc(p: ^Pulse, new_screen_size: rl.Vector2) {
	assert(new_screen_size.x > 0 && new_screen_size.y > 0, "Invalid screen size")

	screen_width := new_screen_size.x
	screen_height := new_screen_size.y

	if len(p.windows) == 0 {
		return
	}

	if p.split_type == .NONE {
		if len(p.windows) >= 1 {
			p.windows[0].rect = rl.Rectangle {
				x      = 0,
				y      = 0,
				width  = screen_width,
				height = screen_height,
			}
		}
	} else if p.split_type == .VERTICAL {
		if len(p.windows) >= 2 {
			split_pos := screen_width * 0.5 // Maintain 50/50 split.

			p.windows[0].rect = rl.Rectangle {
				x      = 0,
				y      = 0,
				width  = split_pos,
				height = screen_height,
			}

			p.windows[1].rect = rl.Rectangle {
				x      = split_pos,
				y      = 0,
				width  = screen_width - split_pos,
				height = screen_height,
			}
		}
	} else if p.split_type == .HORIZONTAL {
		if len(p.windows) >= 2 {
			split_pos := screen_height * 0.5 // Same thing here.

			p.windows[0].rect = rl.Rectangle {
				x      = 0,
				y      = 0,
				width  = screen_width,
				height = split_pos,
			}

			p.windows[1].rect = rl.Rectangle {
				x      = 0,
				y      = split_pos,
				width  = screen_width,
				height = screen_height - split_pos,
			}
		}
	}
}

// This function finds all split edges by analyzing window boundaries.
find_all_split_edges :: proc(
	windows: [dynamic]Window,
	edges: ^[dynamic]Split_Edge,
	allocator := context.allocator,
) {
	if len(windows) <= 1 do return

	// For each pair of windows, check if they share an edge.
	for i := 0; i < len(windows); i += 1 {
		w1 := &windows[i]

		for j := i + 1; j < len(windows); j += 1 {
			w2 := &windows[j]

			// Check if windows share an edge.

			// Vertical edge (right of w1 = left of w2 or right of w2 = left of w1).
			if abs(w1.rect.x + w1.rect.width - w2.rect.x) < 1.0 ||
			   abs(w2.rect.x + w2.rect.width - w1.rect.x) < 1.0 {

				// Find shared vertical segment.
				y_top := max(w1.rect.y, w2.rect.y)
				y_bottom := min(w1.rect.y + w1.rect.height, w2.rect.y + w2.rect.height)

				if y_bottom > y_top {
					edge: Split_Edge
					edge.type = .VERTICAL

					if abs(w1.rect.x + w1.rect.width - w2.rect.x) < 1.0 {
						// w1 is to the left of w2.
						edge.start = {w1.rect.x + w1.rect.width, y_top}
						edge.end = {w1.rect.x + w1.rect.width, y_bottom}
					} else {
						// w2 is to the left of w1.
						edge.start = {w2.rect.x + w2.rect.width, y_top}
						edge.end = {w2.rect.x + w2.rect.width, y_bottom}
					}

					append(edges, edge)
				}
			}

			// Horizontal edge (bottom of w1 = top of w2 or bottom of w2 = top of w1).
			if abs(w1.rect.y + w1.rect.height - w2.rect.y) < 1.0 ||
			   abs(w2.rect.y + w2.rect.height - w1.rect.y) < 1.0 {

				// Find shared horizontal segment.
				x_left := max(w1.rect.x, w2.rect.x)
				x_right := min(w1.rect.x + w1.rect.width, w2.rect.x + w2.rect.width)

				if x_right > x_left {
					edge: Split_Edge
					edge.type = .HORIZONTAL

					if abs(w1.rect.y + w1.rect.height - w2.rect.y) < 1.0 {
						// w1 is above w2.
						edge.start = {x_left, w1.rect.y + w1.rect.height}
						edge.end = {x_right, w1.rect.y + w1.rect.height}
					} else {
						// w2 is above w1.
						edge.start = {x_left, w2.rect.y + w2.rect.height}
						edge.end = {x_right, w2.rect.y + w2.rect.height}
					}

					append(edges, edge)
				}
			}
		}
	}
}

// 
// Focus
//

// Toggle focus between the 2 windows.
window_switch_focus :: proc(p: ^Pulse) {
	if p.split_type == .NONE || len(p.windows) != 2 {
		return
	}

	new_focus_index := 1 if p.current_window == &p.windows[0] else 0
	p.current_window.is_focus = false
	p.current_window = &p.windows[new_focus_index]
	p.current_window.is_focus = true
}

window_focus_left :: proc(p: ^Pulse) {
	if p.split_type == .VERTICAL && len(p.windows) == 2 {
		p.current_window.is_focus = false
		p.current_window = &p.windows[0]
		p.current_window.is_focus = true
	}
}

window_focus_right :: proc(p: ^Pulse) {
	if p.split_type == .VERTICAL && len(p.windows) == 2 {
		p.current_window.is_focus = false
		p.current_window = &p.windows[1]
		p.current_window.is_focus = true
	}
}

window_focus_top :: proc(p: ^Pulse) {
	if p.split_type == .HORIZONTAL && len(p.windows) == 2 {
		p.current_window.is_focus = false
		p.current_window = &p.windows[0]
		p.current_window.is_focus = true
	}
}

window_focus_bottom :: proc(p: ^Pulse) {
	if p.split_type == .HORIZONTAL && len(p.windows) == 2 {
		p.current_window.is_focus = false
		p.current_window = &p.windows[1]
		p.current_window.is_focus = true
	}
}
