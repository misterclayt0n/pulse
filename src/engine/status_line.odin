package engine

import "core:fmt"
import "core:mem"
import "core:strings"
import rl "vendor:raylib"

Status_Line :: struct {
	allocator:         mem.Allocator,
	text_color:        rl.Color,
	bg_color:          rl.Color,
	mode:              string,
	filename:          string,
	line_number:       int,
	col_number:        int,
	font:              Font,
	padding:           f32,
	command_window:    ^Window,
	command_indicator: string,
	current_prompt:    string,

	// Logging.
	message:           string,
	message_timestamp: f64, // Time when message will expire.
	message_duration:  f64, // How long to show messages (seconds).
	message_color:     rl.Color,
}

status_line_init :: proc(font: Font, allocator := context.allocator) -> Status_Line {
	command_buffer := new(Buffer, allocator)
	command_buffer^ = buffer_init(allocator)
	command_buffer.is_cli = true
	assert(command_buffer != nil, "Command buffer allocation failed")

	command_window := new(Window, allocator)
	command_window^ = window_init(command_buffer, font, {0, 0, 0, 0}) // Rect will be updated during draw.
	assert(command_window != nil, "Command window allocation failed")

	return Status_Line {
		allocator         = allocator,
		text_color        = rl.WHITE,
		bg_color          = rl.Color{40, 40, 40, 255},
		mode              = "NORMAL",
		filename          = "some file", // TODO: Grab filename from Buffer.
		font              = font,
		padding           = 10,
		command_window    = command_window,
		command_indicator = COMMAND_INDICATOR_STRING,
		current_prompt    = "",
		message           = "",
		message_duration  = MESSAGE_DURATION, // Show messages for 3 seconds.
		message_color     = rl.GOLD,
	}
}

status_line_update :: proc(p: ^Pulse) {
	assert(p.current_window != nil, "Current window is nil")
	assert(p.current_window.cursor.line >= 0, "Cursor line must not be negative")
	assert(p.current_window.cursor.col >= 0, "Cursor column must not be negative")

	// Update status line information.
	p.status_line.mode = fmt.tprintf("%v", p.current_window.mode)

	// Update line/col from main buffer.
	p.status_line.line_number = p.current_window.cursor.line
	p.status_line.col_number = p.current_window.cursor.col

	// Clear expired messages.
	if rl.GetTime() > p.status_line.message_timestamp do p.status_line.message = ""
}

status_line_draw :: proc(s: ^Status_Line, screen_width, screen_height: i32) {
	// Draw background.
	line_height := s.font.size
	status_height := s.font.size + i32(s.padding) // Total height considering padding.

	bg_rect := rl.Rectangle {
		x      = 0,
		y      = f32(screen_height) - f32(status_height),
		width  = f32(screen_width),
		height = f32(status_height),
	}
	rl.DrawRectangleRec(bg_rect, s.bg_color)

	// Prepare status text.
	status_text: string
	command_text := string(s.command_window.buffer.data[:])

	if s.mode == "COMMAND" || s.mode == "COMMAND_NORMAL" {
		if s.current_prompt != "" {
			status_text = fmt.tprintf("%s%s", s.current_prompt, command_text)
		} else {
			status_text = fmt.tprintf("%s%s", s.command_indicator, command_text)
		}
	} else {
		status_text = fmt.tprintf(
			"%s | %s | %d:%d",
			s.mode,
			s.filename,
			s.line_number + 1,
			s.col_number + 1,
		)
	}

	// Draw status text.
	text_pos := rl.Vector2{s.padding, f32(screen_height) - f32(line_height) - s.padding / 2}
	rl.DrawTextEx(
		s.font.ray_font,
		cstring(raw_data(status_text)),
		text_pos,
		f32(s.font.size),
		s.font.spacing,
		s.text_color,
	)

	if s.mode == "COMMAND" || s.mode == "COMMAND_NORMAL" {
		assert(s.command_window != nil, "Command window must be valid")
		assert(len(s.command_window.buffer.data) >= 0, "Buffer data length should be non-negative")
		// Measure command indicator width.
		indicator_width: f32
		if s.current_prompt != "" {
			indicator_width = rl.MeasureTextEx(s.font.ray_font, cstring(raw_data(s.current_prompt)), f32(s.font.size), s.font.spacing).x
		} else {
			indicator_width = rl.MeasureTextEx(s.font.ray_font, cstring(raw_data(s.command_indicator)), f32(s.font.size), s.font.spacing).x
		}

		// Create temporary draw context for cursor.
		ctx := Draw_Context {
			position      = {s.padding + indicator_width, text_pos.y},
			screen_width  = screen_width,
			screen_height = screen_height,
			line_height   = int(line_height),
		}

		cursor_draw(s.command_window, s.font, ctx)
	}

	msg_width :=
		rl.MeasureTextEx(s.font.ray_font, cstring(raw_data(s.message)), f32(s.font.size), s.font.spacing).x

	msg_pos := rl.Vector2 {
		f32(screen_width) - msg_width - s.padding,
		f32(screen_height) - f32(line_height) - s.padding / 2,
	}

	rl.DrawTextEx(
		s.font.ray_font,
		cstring(raw_data(s.message)),
		msg_pos,
		f32(s.font.size),
		s.font.spacing,
		s.message_color,
	)
}

// This function also inserts a newline at the end of the formatted string.
status_line_log :: proc(s: ^Status_Line, format: string, args: ..any) {
	format := format
	if s.message != "" {
		delete(s.message, s.allocator)
	}

	formatted := fmt.tprintf("%s\n\n", format)
	s.message = fmt.tprintf(formatted, ..args)
	s.message_timestamp = rl.GetTime() + s.message_duration
}

status_line_clear_message :: proc(s: ^Status_Line) {
	s.message = ""
	s.message_timestamp = 0
}
