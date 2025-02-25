package engine

import "core:fmt"
import rl "vendor:raylib"

Status_Line :: struct {
	text_color:  rl.Color,
	bg_color:    rl.Color,
	mode:        string,
	filename:    string,
	line_number: int,
	col_number:  int,
	font:        Font,
	padding:     f32,
}

status_line_init :: proc(font: Font) -> Status_Line {
	return Status_Line {
		text_color = rl.WHITE,
		bg_color = rl.Color{40, 40, 40, 255},
		mode = "NORMAL",
		filename = "some file",
		font = font,
		padding = 10,
	}
}

status_line_draw :: proc(s: ^Status_Line, screen_width, screen_height: i32) {
	// Draw background.
	line_height := s.font.size + i32(s.font.spacing)
	bg_rect := rl.Rectangle {
		x      = 0,
		y      = f32(screen_height) - f32(line_height) - s.padding,
		width  = f32(screen_width),
		height = f32(screen_height),
	}
	rl.DrawRectangleRec(bg_rect, s.bg_color)

	status_text := fmt.tprintf(
		"%s | %s | Ln %d, Col %d",
		s.mode,
		s.filename,
		s.line_number + 1,
		s.col_number + 1,
	)

	// Draw text.
	text_pos := rl.Vector2{s.padding, f32(screen_height) - f32(line_height) - s.padding / 2}
	rl.DrawTextEx(
		s.font.ray_font,
		cstring(raw_data(status_text)),
		text_pos,
		f32(s.font.size),
		s.font.spacing,
		s.text_color,
	)
}
