package engine

import "core:fmt"
import "core:sort"
import rl "vendor:raylib"

//
// Globals
//

background_color :: rl.Color{28, 28, 28, 255}
text_color :: rl.Color{235, 219, 178, 255}
scroll_smoothness :: 0.2
split_color :: rl.Color{60, 60, 60, 255}

// Main state of the editor,
Pulse :: struct {
	windows:        [dynamic]Window,
	current_window: ^Window,
	font:           Font,
	status_line:    Status_Line,
	keymap:         Keymap,
	should_close:   bool,
	screen_size:    rl.Vector2,
}

pulse_init :: proc(font_path: string, allocator := context.allocator) -> Pulse {
	buffer := new(Buffer, allocator)
	buffer^ = buffer_init(allocator)
	font := load_font_with_codepoints(font_path, 25, text_color, allocator) // Default font.

	// Create initial window that takes up entire screen.
	screen_width := f32(rl.GetScreenWidth())
	screen_height := f32(rl.GetScreenHeight())

	initial_window := window_init(buffer, {0, 0, screen_width, screen_height}, allocator)
	windows := make([dynamic]Window, allocator)
	append(&windows, initial_window)

	status_line := status_line_init(font)
	keymap := keymap_init(.VIM, allocator) // Default to vim.

	screen_size: rl.Vector2 = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	return Pulse {
		windows = windows,
		current_window = &windows[0],
		font = font,
		status_line = status_line,
		keymap = keymap,
		screen_size = screen_size,
	}
}

pulse_update :: proc(p: ^Pulse) {
	current_screen_size: rl.Vector2 = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	if current_screen_size != p.screen_size {
		// Find root window and resize it.
		for &w in p.windows {
			if w.parent == nil {
				window_resize_tree(&w, {0, 0, current_screen_size.x, current_screen_size.y})
				break
			}
		}

		p.screen_size = current_screen_size
	}

	keymap_update(p)
	status_line_update(p)

	// Update all windows.
	for &w in p.windows {
		window_update(&w)
		if w.is_focus do window_scroll(&w, p.font)
	}
}

pulse_draw :: proc(p: ^Pulse, allocator := context.allocator) {
	screen_width := rl.GetScreenWidth()
	screen_height := rl.GetScreenHeight()

	rl.ClearBackground(background_color)

	// Draw all windows.
	for i := 0; i < len(p.windows); i += 1 {
		window := &p.windows[i]
		window_draw(window, p.font, allocator)

		if window.split_type != .NONE {
			switch window.split_type {
			case .VERTICAL:
				// Vertical line on right edge.
				split_x := window.rect.x + window.rect.width
				rl.DrawLineEx(
					{split_x, window.rect.y},
					{split_x, window.rect.y + window.rect.height},
					1.0,
					split_color,
				)
			case .HORIZONTAL:
				// Horizontal line on bottom edge.
				split_y := window.rect.y + window.rect.height
				rl.DrawLineEx(
					{window.rect.x, split_y},
					{window.rect.x + window.rect.width, split_y},
					1.0,
					split_color,
				)
			case .NONE: // Unreachable.
			}
		}
	}

	// Draw status line.
	status_line_draw(&p.status_line, screen_width, screen_height)
}
