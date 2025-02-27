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
	command:     string,
}

status_line_init :: proc(font: Font) -> Status_Line {
	return Status_Line {
		text_color = rl.WHITE,
		bg_color   = rl.Color{40, 40, 40, 255},
		mode       = "NORMAL",
		filename   = "some file",
		font       = font,
		padding    = 10,
	}
}

status_line_update :: proc(p: ^Pulse) {
	// Update status line information.
	switch p.keymap.mode {
	case .VIM:
		p.status_line.mode = fmt.tprintf("%v", p.keymap.vim_state.mode)
		// Update command buffer display.
		if p.keymap.vim_state.mode == .COMMAND {
			p.status_line.command = string(p.keymap.vim_state.command_buf[:])
		} else {
			p.status_line.command = ""
		}
	case .EMACS:
		p.status_line.mode    = "EMACS"
		p.status_line.command = ""
	}

	// Update status line information.
	p.status_line.line_number = p.buffer.cursor.line
	p.status_line.col_number  = p.buffer.cursor.col
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

	status_text: string
    if s.mode == "COMMAND" {
        // Command mode display.
        status_text = fmt.tprintf(":%s", s.command)
    } else {
        // Normal status display.
        status_text = fmt.tprintf(
            "%s | %s | %d:%d",
            s.mode,
            s.filename,
            s.line_number + 1,
            s.col_number + 1,
        )
    }

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
