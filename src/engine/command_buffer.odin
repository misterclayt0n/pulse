package engine

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import "core:unicode/utf8"

// NOTE: Leader key is hard coded as space.
Known_Commands :: []string {
	"gg", 
	"gd", // TODO: Go to definition
	"dd",
	"cc",
	"yy", // TODO: Yank line.
	" w", // <leader>w - save file
	"iw", // Select inner word.
	"ip", // Select inner paragraph.
	"ciw", // Change inner word.
	"i(",
	"i[",
	"i{",
	"i\"",
	"i'",
	"ci(",
	"ci[",
	"ci{",
	"ci\"",
	"ci'",
	"cip", // Change inner paragraph.
	"di(",
	"di[",
	"di{",
	"di\"",
	"di'",
	"dip", // Delete inner paragraph
}

is_command :: proc(window: ^Window, cmd: string) -> bool {
	if window.mode == .NORMAL && (cmd == "d" || cmd == "g" || cmd == "c") {
		window.cursor.color = COMMAND_BUFFER_CURSOR_COLOR
	}
	
	for known in Known_Commands {
		if cmd == known {
			return true
		} 
	}

	return false
}

is_prefix_of_command :: proc(cmd: string) -> bool {
	for known in Known_Commands {
		if strings.has_prefix(known, cmd) do return true
	}

	return false
}

execute_normal_command :: proc(p: ^Pulse, cmd: string) {
	switch cmd {
	case "gg":
		buffer_move_cursor(p.current_window, .FILE_BEGINNING)
	case "dd":
		buffer_delete_line(p.current_window)
	case "cc":
		buffer_change_line(p.current_window)
		change_mode(p, .INSERT)
	case " w":
		status_line_log(&p.status_line, "Saving file from leader w")
	case "iw":
		select_inner_word(p)
	case "ciw":
		change_inner_word(p)
	case "i(":
        select_inner_delimiter(p, '(')
    case "i[":
        select_inner_delimiter(p, '[')
    case "i{":
        select_inner_delimiter(p, '{')
    case "i\"":
        select_inner_delimiter(p, '"')
    case "i'":
        select_inner_delimiter(p, '\'')
    case "ip":
    	select_inner_paragraph(p)
    case "ci(":
        change_inner_delimiter(p, '(')
    case "ci[":
        change_inner_delimiter(p, '[')
    case "ci{":
        change_inner_delimiter(p, '{')
    case "ci\"":
        change_inner_delimiter(p, '"')
    case "ci'":
        change_inner_delimiter(p, '\'')
    case "cip":
    	change_inner_paragraph(p)
    case "di(":
        delete_inner_delimiter(p, '(')
    case "di[":
        delete_inner_delimiter(p, '[')
    case "di{":
        delete_inner_delimiter(p, '{')
    case "di\"":
        delete_inner_delimiter(p, '"')
    case "di'":
        delete_inner_delimiter(p, '\'')
    case "dip":
    	delete_inner_paragraph(p)
	}
}

// TODO: This function probably needs to get more robust
execute_command :: proc(p: ^Pulse) {
	cmd := strings.clone_from_bytes(p.status_line.command_window.buffer.data[:])
	cmd = strings.trim_space(cmd) // Remove leading/trailing whitespace.
	defer delete(cmd)

	// Handle different commands.
	switch cmd {
	case "w":
		// TODO: Input filename here.
		status_line_log(&p.status_line, "File saved successfully")
	case "q":
		// TODO: This should probably close the buffer/window, not the entire editor probably.
		p.should_close = true
	case "wq":
		// TODO: Input filename here.
		status_line_log(&p.status_line, "Saved file sucessfully")
		p.should_close = true
	case "vsplit":
		status_line_log(&p.status_line, "Vertical split")
		window_split_vertical(p)
	case "split":
		status_line_log(&p.status_line, "Horizontal split")
		window_split_horizontal(p)
	case "close":
		status_line_log(&p.status_line, "Split closed")
		window_close_current(p)
	case:
		status_line_log(&p.status_line, "Unknown command: %s", cmd)
	}
}

// 
// Specific commands 
//

@(private)
select_inner_word :: proc(p: ^Pulse) {
	assert(p.current_window.mode == .VISUAL, "Cannot select inner mode if not in visual mode")
	start, end := find_word_boundaries(p.current_window.buffer, p.current_window.cursor.pos)

	if start < end {
		p.current_window.cursor.sel = start
		if end > start {
			// Move cursor to the last character of the word.
			last_rune_start := prev_rune_start(p.current_window.buffer.data[:], end)
			p.current_window.cursor.pos = last_rune_start
		} else {
			p.current_window.cursor.pos = start
		}
	}
}

@(private)
change_inner_word :: proc(p: ^Pulse) {
	assert(p.current_window.mode == .NORMAL, "Need to be in normal mode to use this motion")
	start, end := find_word_boundaries(p.current_window.buffer, p.current_window.cursor.pos)

	if start < end {
		// Delete the word.
		buffer_delete_range(p.current_window, start, end)
		p.current_window.cursor.pos = start
		change_mode(p, .INSERT)
	}
}

@(private)
select_inner_paragraph :: proc(p: ^Pulse) {
	assert(p.current_window.mode == .VISUAL, "Must be in visual mode for vip")
	buffer := p.current_window.buffer
	current_line := p.current_window.cursor.line

	start_line := find_paragraph_start(buffer, current_line)
	end_line := find_paragraph_end(buffer, current_line)

	if start_line <= end_line {
		start_pos := buffer.line_starts[start_line]
		end_pos := len(buffer.data)
		if end_line < len(buffer.line_starts) - 1 {
			end_pos = buffer.line_starts[end_line + 1] - 1 // End of last line.
		}

		p.current_window.cursor.sel = start_pos
		p.current_window.cursor.pos = end_pos - 1 // Last character of the paragraph.
		buffer_update_cursor_line_col(p.current_window)
	}
}

@(private)
delete_inner_paragraph :: proc(p: ^Pulse) {
	buffer := p.current_window.buffer
	current_line := p.current_window.cursor.line
	
	start_line := find_paragraph_start(buffer, current_line)
	end_line := find_paragraph_end(buffer, current_line)
	
	if start_line <= end_line {
		start_pos := buffer.line_starts[start_line]
		end_pos := len(buffer.data)
		if end_line < len(buffer.line_starts) - 1 {
			end_pos = buffer.line_starts[end_line + 1] // Include the newline.
		}

		buffer_delete_range(p.current_window, start_pos, end_pos)
		p.current_window.cursor.pos = start_pos
		buffer_update_cursor_line_col(p.current_window)
	}
}
@(private)
change_inner_paragraph :: proc(p: ^Pulse) {
	buffer := p.current_window.buffer
	current_line := p.current_window.cursor.line
	
	start_line := find_paragraph_start(buffer, current_line)
	end_line := find_paragraph_end(buffer, current_line)
	
	if start_line <= end_line {
		start_pos := buffer.line_starts[start_line]
		end_pos := len(buffer.data)
		if end_line < len(buffer.line_starts) - 1 {
			end_pos = buffer.line_starts[end_line + 1] // Include the newline.
		}

		buffer_delete_range(p.current_window, start_pos, end_pos)
		p.current_window.cursor.pos = start_pos
		buffer_update_cursor_line_col(p.current_window)
		change_mode(p, .INSERT)
	}
}


@(private)
select_inner_delimiter :: proc(p: ^Pulse, delim: rune) {
	assert(p.current_window.mode == .VISUAL, "Cannot select if not in visual mode")
	buffer := p.current_window.buffer
	pos := p.current_window.cursor.pos
	open_delim, close_delim := get_matching_delimiters(delim)
	if open_delim == 0 || close_delim == 0 do return
	start, end, found := find_inner_delimiter_range(buffer, pos, open_delim, close_delim)

	if found {
		p.current_window.cursor.sel = start
		if end > start {
			last_rune_start := prev_rune_start(buffer.data[:], end)
			p.current_window.cursor.pos = last_rune_start
		} else {
			p.current_window.cursor.pos = start
		}
		buffer_update_cursor_line_col(p.current_window)
	}
}

@(private)
change_inner_delimiter :: proc(p: ^Pulse, delim: rune) {
	buffer := p.current_window.buffer
	pos := p.current_window.cursor.pos
	open_delim, close_delim := get_matching_delimiters(delim)
	if open_delim == 0 || close_delim == 0 do return
	start, end, found := find_inner_delimiter_range(buffer, pos, open_delim, close_delim)
	if found {
		buffer_delete_range(p.current_window, start, end)
		p.current_window.cursor.pos = start
		buffer_update_cursor_line_col(p.current_window)
		change_mode(p, .INSERT)
	}
}

@(private)
delete_inner_delimiter :: proc(p: ^Pulse, delim: rune) {
	buffer := p.current_window.buffer
	pos := p.current_window.cursor.pos
	open_delim, close_delim := get_matching_delimiters(delim)
	if open_delim == 0 || close_delim == 0 do return
	start, end, found := find_inner_delimiter_range(buffer, pos, open_delim, close_delim)
	if found {
		buffer_delete_range(p.current_window, start, end)
		p.current_window.cursor.pos = start
		buffer_update_cursor_line_col(p.current_window)
	}
}

