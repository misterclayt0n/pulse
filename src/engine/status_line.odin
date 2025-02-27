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
	command_buf: Buffer,
}

status_line_init :: proc(font: Font, allocator := context.allocator) -> Status_Line {
	buffer := buffer_init(allocator)

	return Status_Line {
		text_color  = rl.WHITE,
		bg_color    = rl.Color{40, 40, 40, 255},
		mode        = "NORMAL",
		filename    = "some file",
		font        = font,
		padding     = 10,
		command_buf = buffer,
	}
}

status_line_update :: proc(p: ^Pulse) {
	// Update status line information.
	switch p.keymap.mode {
	case .VIM:
		p.status_line.mode = fmt.tprintf("%v", p.keymap.vim_state.mode)
	case .EMACS:
		p.status_line.mode = "EMACS"
	}

	// Update line/col from main buffer.
	p.status_line.line_number = p.buffer.cursor.line
	p.status_line.col_number  = p.buffer.cursor.col
}

status_line_draw :: proc(s: ^Status_Line, screen_width, screen_height: i32) {
    // Draw background.
    line_height := s.font.size + i32(s.font.spacing)

    bg_rect := rl.Rectangle{
        x = 0, y = f32(screen_height) - f32(line_height) - s.padding,
        width = f32(screen_width), height = f32(screen_height)
    }
    rl.DrawRectangleRec(bg_rect, s.bg_color)

    // Prepare status text.
    status_text: string
    command_text := string(s.command_buf.data[:])
    
    if s.mode == "COMMAND" {
        status_text = fmt.tprintf(":%s", command_text)
    } else {
        status_text = fmt.tprintf("%s | %s | %d:%d", s.mode, s.filename, s.line_number + 1, s.col_number + 1)
    }

    // Draw status text.
    text_pos := rl.Vector2{s.padding, f32(screen_height) - f32(line_height) - s.padding/2}
    rl.DrawTextEx(
        s.font.ray_font,
        cstring(raw_data(status_text)),
        text_pos,
        f32(s.font.size),
        s.font.spacing,
        s.text_color)

    // Draw command cursor.
    if s.mode == "COMMAND" {
        // Include colon in cursor measurement.
        cursor_text := fmt.tprintf(":%.*s", s.command_buf.cursor.pos, s.command_buf.data)
        text_width := rl.MeasureTextEx(
            s.font.ray_font,
            cstring(raw_data(cursor_text)),
            f32(s.font.size),
            s.font.spacing).x

        // Create temporary draw context for cursor.
        ctx := Draw_Context {
            position = {s.padding, text_pos.y},
            screen_width = screen_width,
            screen_height = screen_height,
            line_height = int(line_height),
        }

        // Adjust cursor position for colon.
        s.command_buf.cursor.pos += 1  // Account for colon.
        buffer_draw_cursor(&s.command_buf, s.font, ctx)
        s.command_buf.cursor.pos -= 1  // Reset position.
    }
}
