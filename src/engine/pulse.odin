package engine

import "core:fmt"
import rl "vendor:raylib"

//
// Globals
//

background_color :: rl.Color{28, 28, 28, 255}
text_color :: rl.Color{235, 219, 178, 255}
scroll_smoothness :: 0.2

// Main state of the editor,
Pulse :: struct {
	windows:        [dynamic]Window,
	current_window: ^Window,
	font:           Font,
	status_line:    Status_Line,
	keymap:         Keymap,
	should_close:   bool,
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

	return Pulse {
		windows = windows,
		current_window = &windows[0],
		font = font,
		status_line = status_line,
		keymap = keymap,
	}
}

pulse_update :: proc(p: ^Pulse) {
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

        // Draw border around focused window.
        // if window.is_focus {
        //     rl.DrawRectangleLinesEx(window.rect, 2, rl.YELLOW)
        // }
    }

    // Draw status line.
    status_line_draw(&p.status_line, screen_width, screen_height)
}
