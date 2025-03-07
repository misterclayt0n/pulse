package engine

import "core:fmt"
import "core:sort"
import rl "vendor:raylib"

// 
// Sanity checks.
// 

#assert(
	DEFAULT_FONT_SIZE >= MIN_FONT_SIZE && DEFAULT_FONT_SIZE <= MAX_FONT_SIZE,
	"Default font size out of range",
)
#assert(MIN_FONT_SIZE > 0, "Minimum font size must be positive")
#assert(MAX_FONT_SIZE > MIN_FONT_SIZE, "Max font size must be greater than minimum")

// Main state of the editor,
Pulse :: struct {
	windows:        [dynamic]Window,
	current_window: ^Window,
	font:           Font,
	status_line:    Status_Line,
	keymap:         Keymap,
	should_close:   bool,
	screen_size:    rl.Vector2,
	split_type:     Split_Type,
}

pulse_init :: proc(font_path: string, allocator := context.allocator) -> Pulse {
	buffer := new(Buffer, allocator)
	assert(buffer != nil, "Buffer allocation failed")
	buffer^ = buffer_init(allocator)

	font := load_font_with_codepoints(font_path, DEFAULT_FONT_SIZE, TEXT_COLOR, allocator) // Default font.
	assert(font.size == DEFAULT_FONT_SIZE, "Invalid font size")

	// Create initial window that takes up entire screen.
	screen_width := f32(rl.GetScreenWidth())
	screen_height := f32(rl.GetScreenHeight())
	assert(screen_width > 0, "Screen width must be positive")
	assert(screen_height > 0, "Screen height must be positive")

	initial_window := window_init(buffer, {0, 0, screen_width, screen_height}, allocator)
	assert(initial_window.buffer != nil, "Window buffer is invalid")

	windows := make([dynamic]Window, allocator)
	append(&windows, initial_window)
	assert(len(windows) > 0, "Windows array must not be empty")
	assert(&windows[0] != nil, "Current window pointer is invalid")

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

pulse_update :: proc(p: ^Pulse, allocator := context.allocator) {
	current_screen_size: rl.Vector2 = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	assert(current_screen_size.x > 0, "Screen width must be greater than 0")
	assert(current_screen_size.y > 0, "Screen height must be greater than 0")

	if current_screen_size != p.screen_size {
		window_resize_tree(p, current_screen_size)
		p.screen_size = current_screen_size
		assert(p.screen_size == current_screen_size, "Screen size update failed")
	}

	keymap_update(p, allocator)
	status_line_update(p)

	// Update all windows.
	for &w in p.windows {
		assert(&w != nil, "Encountered nil window in windows array")

		buffer_clamp_cursor_to_valid_range(&w)
		if w.is_focus {
			buffer_clamp_cursor_to_valid_range(&w)
			window_update(&w) // Recompute line_starts/cursor.line only here
			window_scroll(&w, p.font)
		}
	}
}

pulse_draw :: proc(p: ^Pulse, allocator := context.allocator) {
	screen_width := rl.GetScreenWidth()
	screen_height := rl.GetScreenHeight()
	assert(screen_width > 0, "Invalid screen width")
	assert(screen_height > 0, "Invalid screen height")

	rl.ClearBackground(BACKGROUND_COLOR)

	// Draw all windows.
	assert(len(p.windows) > 0, "No windows to draw")
	for i := 0; i < len(p.windows); i += 1 {
		window := &p.windows[i]
		window_draw(p, window, p.font, allocator)
	}

	// Find and draw all split edges
	edges := make([dynamic]Split_Edge, allocator)
	defer delete(edges)

	find_all_split_edges(p.windows, &edges, allocator)

	for edge in edges {
		assert(
			edge.start.x >= 0 && edge.start.x <= f32(screen_width),
			"Edge start x out of bounds",
		)
		assert(edge.end.x >= 0 && edge.end.x <= f32(screen_width), "Edge end x out of bounds")
		assert(
			edge.start.y >= 0 && edge.start.y <= f32(screen_height),
			"Edge start y out of bounds",
		)
		assert(edge.end.y >= 0 && edge.end.y <= f32(screen_height), "Edge end y out of bounds")

		rl.DrawLineEx(edge.start, edge.end, 1.0, SPLIT_COLOR)
	}

	// Draw status line.
	assert(p.status_line.command_window != nil, "Invalid status line command window")
	status_line_draw(&p.status_line, screen_width, screen_height)
}
