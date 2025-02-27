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
	buffer:       Buffer, // NOTE: This is probably being removed for a window system.
	font:         Font,
	status_line:  Status_Line,
	keymap:       Keymap,
	camera:       rl.Camera2D,
	target_x:     f32,
	target_y:     f32,
	should_close: bool,
}

pulse_init :: proc(font_path: string, allocator := context.allocator) -> Pulse {
	buffer := buffer_init(allocator)
	font := load_font_with_codepoints(font_path, 35, text_color, allocator) // Default font
	status_line := status_line_init(font)
	camera := rl.Camera2D {
		offset   = {0, 0},
		target   = {0, 0},
		rotation = 0,
		zoom     = 1,
	}
	keymap := keymap_init(.VIM, allocator) // Default to vim.

	return Pulse {
		buffer = buffer,
		font = font,
		status_line = status_line,
		camera = camera,
		target_x = 0,
		target_y = 0,
		keymap = keymap,
	}
}

pulse_update :: proc(p: ^Pulse) {
	keymap_update(p)
	status_line_update(p)
	pulse_scroll(p)
}

// TODO: Mouse interaction.
pulse_scroll :: proc(p: ^Pulse) {
	// Vertical scrolling logic.
	line_height := f32(p.font.size) + p.font.spacing
	cursor_world_y := 10 + f32(p.buffer.cursor.line) * line_height // World Y of cursor.
	window_height := f32(rl.GetScreenHeight())
	margin_y :: 100.0
	line_count := f32(len(p.buffer.line_starts))
	document_height := 10 + line_count * line_height
	max_target_y := max(0, document_height - window_height)

	// Calculate cursor position relative to current viewport.
	cursor_screen_y := cursor_world_y - p.camera.target.y

	if cursor_screen_y < margin_y {
		p.target_y = cursor_world_y - margin_y
	} else if cursor_screen_y > (window_height - margin_y) {
		p.target_y = cursor_world_y - (window_height - margin_y)
	}
	// NOTE: Clamp to prevent showing empty space beyond the document.
	p.target_y = clamp(p.target_y, 0, max_target_y)

	// Horizontal scrolling logic.
	line_start := p.buffer.line_starts[p.buffer.cursor.line]
	text_slice := p.buffer.data[line_start:p.buffer.cursor.pos]
	temp_len := len(text_slice)
	temp := make([]u8, temp_len + 1)

	defer delete(temp)
	if temp_len > 0 do copy(temp, text_slice)
	temp[temp_len] = 0

	text_width :=
		rl.MeasureTextEx(p.font.ray_font, cstring(raw_data(temp)), f32(p.font.size), p.font.spacing).x
	cursor_x := f32(10) + text_width
	window_width := f32(rl.GetScreenWidth())
	viewport_left := p.camera.target.x
	viewport_right := viewport_left + window_width
	margin_x :: 50.0

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

pulse_draw :: proc(p: ^Pulse, allocator := context.allocator) {
	screen_width := rl.GetScreenWidth()
	screen_height := rl.GetScreenHeight()
	status_line_draw(&p.status_line, screen_width, screen_height)
	line_height := f32(p.font.size) + p.font.spacing

	first_visible_line := int((p.camera.target.y - 10) / line_height)
	last_visible_line := int((p.camera.target.y + f32(screen_height) + 10) / line_height)
	first_visible_line = max(0, first_visible_line)
	last_visible_line = min(len(p.buffer.line_starts) - 1, last_visible_line)

	ctx := Draw_Context {
		position      = rl.Vector2{10, 10},
		screen_width  = screen_width,
		screen_height = screen_height,
		first_line    = first_visible_line,
		last_line     = last_visible_line,
		line_height   = int(line_height),
	}

	rl.ClearBackground(background_color)
	rl.BeginMode2D(p.camera)
	defer rl.EndMode2D()

	buffer_draw(&p.buffer, p.font, ctx)
}
