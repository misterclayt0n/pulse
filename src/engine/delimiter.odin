package engine

import "core:unicode/utf8"

Matching_Delimiters :: []struct {
	open:  rune,
	close: rune,
}{{'(', ')'}, {'[', ']'}, {'{', '}'}}

// Find the enclosing opening delimiter.
find_enclosing_open_delim :: proc(
	buffer: ^Buffer,
	pos: int,
	open_delim, close_delim: rune,
) -> int {
	counter := 0
	current_pos := pos
	for current_pos > 0 {
		current_pos = prev_rune_start(buffer.data[:], current_pos)
		r, _ := utf8.decode_rune(buffer.data[current_pos:])
		if r == close_delim {
			counter += 1
		} else if r == open_delim {
			counter -= 1
			if counter < 0 {
				return current_pos // Found the enclosing opening delimiter.
			}
		}
	}
	return -1 // Not found.
}

// Find the enclosing closing delimiter.
find_enclosing_close_delim :: proc(
	buffer: ^Buffer,
	pos: int,
	open_delim, close_delim: rune,
) -> int {
	counter := 0
	current_pos := pos
	for current_pos < len(buffer.data) {
		r, n := utf8.decode_rune(buffer.data[current_pos:])
		if r == open_delim {
			counter += 1
		} else if r == close_delim {
			counter -= 1
			if counter < 0 {
				return current_pos // Found the enclosing closing delimiter.
			}
		}
		current_pos += n
	}
	return -1 // Not found.
}

find_nearest_quote_left :: proc(buffer: ^Buffer, pos: int, quote: rune) -> int {
	current_pos := pos
	for current_pos > 0 {
		current_pos = prev_rune_start(buffer.data[:], current_pos)
		r, _ := utf8.decode_rune(buffer.data[current_pos:])
		if r == quote {
			return current_pos
		}
	}
	return -1
}

find_nearest_quote_right :: proc(buffer: ^Buffer, pos: int, quote: rune) -> int {
	current_pos := pos
	for current_pos < len(buffer.data) {
		r, n := utf8.decode_rune(buffer.data[current_pos:])
		if r == quote {
			return current_pos
		}
		current_pos += n
	}
	return -1
}

find_next_open_delim :: proc(buffer: ^Buffer, pos: int, open_delim: rune) -> int {
	current_pos := pos
	for current_pos < len(buffer.data) {
		r, n := utf8.decode_rune(buffer.data[current_pos:])
		if r == open_delim {
			return current_pos
		}
		current_pos += n
	}
	return -1 // Not found
}

find_inner_delimiter_range :: proc(
    buffer: ^Buffer,
    pos: int,
    open_delim, close_delim: rune,
) -> (
    start: int,
    end: int,
    found: bool,
) {
    if open_delim == close_delim { // Quotes (e.g., " or ').
        left := find_nearest_quote_left(buffer, pos, open_delim)
        if left == -1 do return 0, 0, false
        right := find_nearest_quote_right(buffer, pos, close_delim)
        if right == -1 do return 0, 0, false
        if left < pos && pos < right {
            _, n_open := utf8.decode_rune(buffer.data[left:])
            start = left + n_open // After the opening quote.
            end = right // At the closing quote.
            found = true
        }
    } else { // Parentheses, brackets, etc.
        // Check if cursor is on a delimiter.
        is_delim, is_open, delim := is_on_delimiter(buffer, pos)
        if is_delim {
            if is_open && delim == open_delim {
                // On opening delimiter (e.g., cursor on '(').
                r, n := utf8.decode_rune(buffer.data[pos:])
                right := find_enclosing_close_delim(buffer, pos + n, open_delim, close_delim)
                if right != -1 {
                    start = pos + n // After the opening delimiter.
                    end = right // At the closing delimiter.
                    found = true
                }
            } else if !is_open && delim == close_delim {
                // On closing delimiter (e.g., cursor on ')').
                left := find_enclosing_open_delim(buffer, pos - 1, open_delim, close_delim)
                if left != -1 {
                    _, n_open := utf8.decode_rune(buffer.data[left:])
                    start = left + n_open // After the opening delimiter.
                    end = pos // At the closing delimiter.
                    found = true
                }
            }
        } else {
            // Not on a delimiter, check if inside an enclosing pair.
            left := find_enclosing_open_delim(buffer, pos, open_delim, close_delim)
            right := find_enclosing_close_delim(buffer, pos, open_delim, close_delim)
            if left != -1 && right != -1 && left < pos && pos < right {
                // Inside a pair.
                _, n_open := utf8.decode_rune(buffer.data[left:])
                start = left + n_open // After the opening delimiter.
                end = right // At the closing delimiter.
                found = true
            } else {
                // Not inside a pair, find the next opening delimiter.
                next_open := find_next_open_delim(buffer, pos, open_delim)
                if next_open != -1 {
                    _, n_open := utf8.decode_rune(buffer.data[next_open:])
                    right := find_enclosing_close_delim(buffer, next_open + n_open, open_delim, close_delim)
                    if right != -1 {
                        start = next_open + n_open // After the opening delimiter.
                        end = right // At the closing delimiter.
                        found = true
                    }
                }
            }
        }
    }
    return start, end, found
}

get_matching_delimiters :: proc(delim: rune) -> (open: rune, close: rune) {
	for pair in Matching_Delimiters {
		if delim == pair.open || delim == pair.close {
			return pair.open, pair.close
		}
	}
	return 0, 0 // Invalid delimiter.
}

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
// Helpers
// 

// Helper function to check if cursor is on a delimiter
is_on_delimiter :: proc(buffer: ^Buffer, pos: int) -> (is_delim: bool, is_open: bool, delim: rune) {
    if pos >= len(buffer.data) do return false, false, 0
    r, _ := utf8.decode_rune(buffer.data[pos:])
    for pair in Matching_Delimiters {
        if r == pair.open {
            return true, true, r
        } else if r == pair.close {
            return true, false, r
        }
    }
    return false, false, 0
}

