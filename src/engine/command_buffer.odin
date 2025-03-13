package engine

import "core:fmt"
import "core:strings"

// NOTE: Leader key is hard coded as space.
Known_Commands :: []string {
	"gg", // TODO: Top of the buffer.
	"gd", // TODO: Go to definition
	"dd",
	"cc",
	"yy", // TODO: Yank line.
	" w", // <leader>w - save file
	"iw", // Select inner word in visual mode.
}

is_complete_command :: proc(cmd: string) -> bool {
	for known in Known_Commands {
		if cmd == known do return true
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
		if p.current_window.mode == .VISUAL {
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
