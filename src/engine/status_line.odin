package engine

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Status_Line :: struct {
	text_color:        rl.Color,
	bg_color:          rl.Color,
	mode:              string,
	filename:          string,
	line_number:       int,
	col_number:        int,
	font:              Font,
	padding:           f32,
	command_buf:       Buffer,
	command_indicator: string,
}

status_line_init :: proc(font: Font, allocator := context.allocator) -> Status_Line {
	buffer := buffer_init(allocator)
	buffer.is_cli = true

	return Status_Line {
		text_color = rl.WHITE,
		bg_color = rl.Color{40, 40, 40, 255},
		mode = "NORMAL",
		filename = "some file",
		font = font,
		padding = 10,
		command_buf = buffer,
		command_indicator = "",
	}
}

status_line_update :: proc(p: ^Pulse) {
	// Update status line information.
	p.status_line.mode = fmt.tprintf("%v", p.keymap.vim_state.mode)

	// Update line/col from main buffer.
	p.status_line.line_number = p.current_window.buffer.cursor.line
	p.status_line.col_number = p.current_window.buffer.cursor.col
}

status_line_draw :: proc(s: ^Status_Line, screen_width, screen_height: i32) {
	// Draw background.
	line_height := s.font.size + i32(s.font.spacing)
	status_height := line_height + i32(s.padding) // Total height considering padding.

	bg_rect := rl.Rectangle {
		x      = 0,
		y      = f32(screen_height) - f32(status_height),
		width  = f32(screen_width),
		height = f32(status_height),
	}
	rl.DrawRectangleRec(bg_rect, s.bg_color)

	// Prepare status text.
	status_text: string
	command_text := string(s.command_buf.data[:])

	if s.mode == "COMMAND" || s.mode == "COMMAND_NORMAL" {
		status_text = fmt.tprintf("%s%s", s.command_indicator, command_text)
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

	// Draw command cursor.
	if s.mode == "COMMAND" || s.mode == "COMMAND_NORMAL" {
		// Measure command indicator width.
		indicator_width :=
			rl.MeasureTextEx(s.font.ray_font, cstring(raw_data(s.command_indicator)), f32(s.font.size), s.font.spacing).x

		// Create temporary draw context for cursor.
		ctx := Draw_Context {
			position      = {s.padding + indicator_width, text_pos.y},
			screen_width  = screen_width,
			screen_height = screen_height,
			line_height   = int(line_height),
		}

		buffer_draw_cursor(&s.command_buf, s.font, ctx)
	}
}
