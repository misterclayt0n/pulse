package engine

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:math/big"
import rl "vendor:raylib"
import "core:simd"
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
	"i(",
	"i[",
	"i{",
	"i\"",
	"i'",
	"ciw", // Change inner word.
	"cip", // Change inner paragraph.
	"ci(",
	"ci[",
	"ci{",
	"ci\"",
	"ci'",
	"di(",
	"di[",
	"di{",
	"di\"",
	"di'",
	"dip", // Delete inner paragraph
	"diw",
    "a(",
    "a[",
    "a{",
    "a\"",
    "a'",
    "da(",
    "da[",
    "da{",
    "da\"",
    "da'",
    "ca(",
    "ca[",
    "ca{",
    "ca\"",
    "ca'",
    "ap",
    "dap",
    "cap",
    "select",
    "search",
    "ga"
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
		cursor_move(&p.current_window.cursor, p.current_window.buffer, .FILE_BEGINNING)
	case "dd":
		buffer_delete_line(p.current_window)
	case "cc":
		buffer_change_line(p.current_window)
		change_mode(p, .INSERT)
	case " w":
		status_line_log(&p.status_line, "Saving file from leader w")

	// Inner commands.

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
    case "diw": 
	    delete_inner_word(p)

	// Around commands.

    case "a(":
        select_around_delimiter(p, '(')
    case "a[":
        select_around_delimiter(p, '[')
    case "a{":
        select_around_delimiter(p, '{')
    case "a\"":
        select_around_delimiter(p, '"')
    case "a'":
        select_around_delimiter(p, '\'')
    case "da(":
        delete_around_delimiter(p, '(')
    case "da[":
        delete_around_delimiter(p, '[')
    case "da{":
        delete_around_delimiter(p, '{')
    case "da\"":
        delete_around_delimiter(p, '"')
    case "da'":
        delete_around_delimiter(p, '\'')
    case "ca(":
        change_around_delimiter(p, '(')
    case "ca[":
        change_around_delimiter(p, '[')
    case "ca{":
        change_around_delimiter(p, '{')
    case "ca\"":
        change_around_delimiter(p, '"')
    case "ca'":
        change_around_delimiter(p, '\'')
    case "ap":
        select_inner_paragraph(p)
    case "dap":
        delete_inner_paragraph(p)
    case "cap":
        change_inner_paragraph(p)
    case "select":
    	assert(p.current_window.mode == .VISUAL || p.current_window.mode == .VISUAL_LINE)
	    select_command(p)
	case "search":
		search_command(p)
	case "ga":
		add_global_cursors(p, context.temp_allocator)
	}
}

// TODO: This function probably needs to get more robust.
execute_command :: proc(p: ^Pulse) {
	assert(p.current_window.mode == .COMMAND)
	cmd := strings.clone_from_bytes(p.status_line.command_window.buffer.data[:])
	cmd = strings.trim_space(cmd) // Remove leading/trailing whitespace.
	defer delete(cmd)

	// Handle different commands like "select".
	if p.keymap.vim_state.last_command == "select" do handle_select_command(p, cmd)
	if p.keymap.vim_state.last_command == "search" do handle_search_command(p, cmd)
	
	else {
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
}

//
// Inner motions
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
delete_inner_word :: proc(p: ^Pulse) {
	assert(p.current_window.mode == .NORMAL, "Need to be in normal mode to use this motion")
	start, end := find_word_boundaries(p.current_window.buffer, p.current_window.cursor.pos)

	if start < end {
		buffer_delete_range(p.current_window, start, end)
		p.current_window.cursor.pos = start
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

//
// Around motions
//

@(private)
select_around_delimiter :: proc(p: ^Pulse, delim: rune) {
    assert(p.current_window.mode == .VISUAL, "Cannot select if not in visual mode")
    buffer := p.current_window.buffer
    pos := p.current_window.cursor.pos
    open_delim, close_delim := get_matching_delimiters(delim)
    if open_delim == 0 || close_delim == 0 do return

    start, end, found := find_around_delimiter_range(buffer, pos, open_delim, close_delim)
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
delete_around_delimiter :: proc(p: ^Pulse, delim: rune) {
    buffer := p.current_window.buffer
    pos := p.current_window.cursor.pos
    open_delim, close_delim := get_matching_delimiters(delim)
    if open_delim == 0 || close_delim == 0 do return

    start, end, found := find_around_delimiter_range(buffer, pos, open_delim, close_delim)
    if found {
        buffer_delete_range(p.current_window, start, end)
        p.current_window.cursor.pos = start
        buffer_update_cursor_line_col(p.current_window)
    }
}

@(private)
change_around_delimiter :: proc(p: ^Pulse, delim: rune) {
    buffer := p.current_window.buffer
    pos := p.current_window.cursor.pos
    open_delim, close_delim := get_matching_delimiters(delim)
    if open_delim == 0 || close_delim == 0 do return

    start, end, found := find_around_delimiter_range(buffer, pos, open_delim, close_delim)
    if found {
        buffer_delete_range(p.current_window, start, end)
        p.current_window.cursor.pos = start
        buffer_update_cursor_line_col(p.current_window)
        change_mode(p, .INSERT)
    }
}

@(private)
search_command :: proc(p: ^Pulse) {
	p.status_line.current_prompt = SEARCH_COMMAND_STRING
	p.current_window.mode = .COMMAND
    p.keymap.vim_state.command_normal = false
    p.keymap.vim_state.last_command = "search"
    clear(&p.status_line.command_window.buffer.data)
    p.status_line.command_window.cursor.pos = 0
    clear(&p.current_window.temp_match_ranges)
}

@(private)
select_command :: proc(p: ^Pulse) {
	sel := p.current_window.cursor.sel
    pos := p.current_window.cursor.pos
    start := min(sel, pos)
    end := max(sel, pos)
    buffer_len := len(p.current_window.buffer.data)
    
    // If selecting to the end, clamp end to buffer length.
    if end == buffer_len {
        end = buffer_len
    } else if end < buffer_len {
        end += 1 // Exclusive end for slicing, only if not at buffer end.
    }
    
    p.keymap.vim_state.pattern_selection_start = start
    p.keymap.vim_state.pattern_selection_end = end
    
    // Prompt for pattern in status line.
    p.status_line.current_prompt = SELECT_COMMAND_STRING
    p.current_window.mode = .COMMAND
    p.keymap.vim_state.command_normal = false
    p.keymap.vim_state.last_command = "select"
    clear(&p.status_line.command_window.buffer.data)
    p.status_line.command_window.cursor.pos = len(p.status_line.command_window.buffer.data)
}

handle_search_command :: proc(p: ^Pulse, cmd: string) {
    pattern := strings.trim_space(cmd)
    if len(pattern) == 0 {
        status_line_log(&p.status_line, "Empty search pattern")
        clear(&p.current_window.temp_match_ranges)
        return
    }
    p.keymap.vim_state.last_search_pattern = strings.clone(pattern, context.temp_allocator)

    buffer := p.current_window.buffer
    full_text := buffer.data[:]
    occurrences := find_all_occurrences(full_text, pattern)
    defer delete(occurrences)

    // Store the searched text and trigger the temp highlight.
    p.current_window.searched_text = strings.clone(pattern, context.allocator) // Persistent storage.
    p.current_window.highlight_searched = true
    p.current_window.highlight_timer = 0.0

    // Update temp_match_ranges with all matches.
    clear(&p.current_window.temp_match_ranges)

    // Move cursor to the first match in the buffer, regardless of current position.
    if len(occurrences) > 0 {
        match_start := occurrences[0][0]
        p.current_window.cursor.pos = match_start
        p.current_window.cursor.line = get_line_from_pos(buffer, match_start)
        p.current_window.cursor.col = match_start - buffer.line_starts[p.current_window.cursor.line]
        p.current_window.cursor.sel = -1
        status_line_log(&p.status_line, "Found '%s'", pattern)
    } else {
        status_line_log(&p.status_line, "No matches found for '%s'", pattern)
    }

    p.current_window.mode = .NORMAL
    p.status_line.current_prompt = ""
    clear(&p.keymap.vim_state.normal_cmd_buffer)
}

handle_select_command :: proc(p: ^Pulse, cmd: string) {
    pattern := cmd
    if strings.has_prefix(pattern, SELECT_COMMAND_STRING) {
        pattern = strings.trim_prefix(pattern, SELECT_COMMAND_STRING)
    }
    if len(pattern) > 0 {
        buffer := p.current_window.buffer
        start := p.keymap.vim_state.pattern_selection_start
        end := p.keymap.vim_state.pattern_selection_end
        selected_text := strings.trim_space(string(buffer.data[start:end]))
        occurrences := find_all_occurrences(transmute([]u8)selected_text, pattern)

        // Clear existing additional cursors.
        clear(&p.current_window.additional_cursors)

        // Add cursors for occurrences starting from the second one.
        for i := 1; i < len(occurrences); i += 1 {
            occ := occurrences[i]
            occ_start := start + occ[0] // == "occ.start"
            occ_end := start + occ[1] // == "occ.end"
            new_cursor := Cursor {
                pos = occ_end - 1, // Last character of match.
                sel = occ_start,   // Start of match.
                line = get_line_from_pos(buffer, occ_end - 1),
                col = (occ_end - 1) - buffer.line_starts[get_line_from_pos(buffer, occ_end - 1)],
                preferred_col = -1,
                style = .BLOCK,
                color = CURSOR_COLOR,
                blink = false,
            }
            append(&p.current_window.additional_cursors, new_cursor)
        }

        // Set main cursor to the first occurrence (if any).
        if len(occurrences) > 0 {
            occ_start := start + occurrences[0][0] // == "occ.start".
            occ_end := start + occurrences[0][1] // == "occ.end".
            p.current_window.cursor.sel = occ_start
            p.current_window.cursor.pos = occ_end - 1
            p.current_window.cursor.line = get_line_from_pos(buffer, occ_end - 1)
            p.current_window.cursor.col = (occ_end - 1) - buffer.line_starts[p.current_window.cursor.line]
        } else {
            status_line_log(&p.status_line, "No occurrences of '%s'", pattern)
        }
    }
    
    // Set visual mode directly to preserve selections.
    p.current_window.mode = .VISUAL
    clear(&p.keymap.vim_state.normal_cmd_buffer)
    for rl.GetCharPressed() != 0 {} // Consume pending input.
    p.status_line.current_prompt = ""
    clear(&p.current_window.temp_match_ranges) 
}

@(private)
find_all_occurrences :: proc(text: []u8, pattern: string) -> [dynamic][2]int {
    ranges := make([dynamic][2]int, 0, 10)
    pattern_bytes := transmute([]u8)pattern
    pattern_len := len(pattern_bytes)
    text_len := len(text)
    if pattern_len == 0 || pattern_len > text_len do return ranges

    // Preprocess the bad character table.
    bad_char := make([]int, 256, context.temp_allocator) // ASCII size
    for i in 0 ..< 256 {
        bad_char[i] = pattern_len // Default skip is pattern length
    }
    for i in 0 ..< pattern_len - 1 {
        bad_char[pattern_bytes[i]] = pattern_len - i - 1 // Distance from rightmost occurrence
    }

    // Search loop using Boyer-Moore.
    pos := 0
    for pos <= text_len - pattern_len {
        // Compare from right to left.
        j := pattern_len - 1
        for j >= 0 && text[pos + j] == pattern_bytes[j] {
            j -= 1
        }

        if j < 0 {
            // Full match found.
            append(&ranges, [2]int{pos, pos + pattern_len})
            pos += pattern_len // Skip to avoid overlaps (adjust if overlaps are desired)
        } else {
            // Mismatch: Skip based on bad character rule.
            mismatch_char := text[pos + j]
            skip := bad_char[mismatch_char]
            pos += max(1, skip) // Ensure at least one byte is skipped
        }
    }

    return ranges
}
