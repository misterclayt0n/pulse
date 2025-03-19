package engine

import "core:unicode/utf8"
import "core:strings"

Matching_Delimiters :: []struct {
	open:  rune,
	close: rune,
}{{'(', ')'}, {'[', ']'}, {'{', '}'}}

// Find the enclosing opening delimiter.
find_enclosing_open_delim :: proc(buffer: ^Buffer, pos: int, open_delim, close_delim: rune) -> int {
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
find_enclosing_close_delim :: proc(buffer: ^Buffer, pos: int, open_delim, close_delim: rune) -> int {
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

// REFACTOR: This code has become pretty much unreadable kkkkkk.
find_inner_delimiter_range :: proc(buffer: ^Buffer, pos: int, open_delim, close_delim: rune) -> (start: int, end: int, found: bool) {
	if open_delim == close_delim { 	// Quotes.
		// Check if inside a pair.
		left := find_nearest_quote_left(buffer, pos, open_delim)
		right := find_nearest_quote_right(buffer, pos, open_delim)
		if left != -1 && right != -1 && left < pos && pos < right {
			_, n_open := utf8.decode_rune(buffer.data[left:])
			start = left + n_open
			end = right
			found = true
			return start, end, found
		}
		// Not inside a pair, find the nearest pair.
		prev_first, prev_second, prev_found := find_previous_quote_pair(buffer, pos, open_delim)
		next_first, next_second, next_found := find_next_quote_pair(buffer, pos, open_delim)

		if prev_found && next_found {
			dist_prev := pos - prev_second
			dist_next := next_first - pos
			if dist_prev <= dist_next {
				_, n_open := utf8.decode_rune(buffer.data[prev_first:])
				start = prev_first + n_open
				end = prev_second
			} else {
				_, n_open := utf8.decode_rune(buffer.data[next_first:])
				start = next_first + n_open
				end = next_second
			}
			found = true
		} else if prev_found {
			_, n_open := utf8.decode_rune(buffer.data[prev_first:])
			start = prev_first + n_open
			end = prev_second
			found = true
		} else if next_found {
			_, n_open := utf8.decode_rune(buffer.data[next_first:])
			start = next_first + n_open
			end = next_second
			found = true
		}
		return start, end, found
	} else { 	// Parentheses, brackets, etc.
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
					right := find_enclosing_close_delim(
						buffer,
						next_open + n_open,
						open_delim,
						close_delim,
					)
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

find_around_delimiter_range :: proc(buffer: ^Buffer, pos: int, open_delim, close_delim: rune) -> (start: int, end: int, found: bool) {
    if open_delim == close_delim { // Quotes (e.g., " or ').
        // Check if inside a pair.
        left := find_nearest_quote_left(buffer, pos, open_delim)
        right := find_nearest_quote_right(buffer, pos, open_delim)
        if left != -1 && right != -1 && left < pos && pos <= right {
            start = left // Include the opening quote.
            r, n := utf8.decode_rune(buffer.data[right:])
            end = right + n // Include the closing quote.
            found = true
            return start, end, found
        }
        
        // Not inside a pair, find the nearest pair.
        prev_first, prev_second, prev_found := find_previous_quote_pair(buffer, pos, open_delim)
        next_first, next_second, next_found := find_next_quote_pair(buffer, pos, open_delim)

        if prev_found && next_found {
            dist_prev := pos - prev_second
            dist_next := next_first - pos
            if dist_prev <= dist_next {
                start = prev_first
                r, n := utf8.decode_rune(buffer.data[prev_second:])
                end = prev_second + n
            } else {
                start = next_first
                r, n := utf8.decode_rune(buffer.data[next_second:])
                end = next_second + n
            }
            found = true
        } else if prev_found {
            start = prev_first
            r, n := utf8.decode_rune(buffer.data[prev_second:])
            end = prev_second + n
            found = true
        } else if next_found {
            start = next_first
            r, n := utf8.decode_rune(buffer.data[next_second:])
            end = next_second + n
            found = true
        }
        return start, end, found
    } else { // Parentheses, brackets, etc.
        // Check if cursor is on a delimiter.
        is_delim, is_open, delim := is_on_delimiter(buffer, pos)
        if is_delim {
            if is_open && delim == open_delim {
                // On opening delimiter (e.g., cursor on '(').
                right := find_enclosing_close_delim(buffer, pos + 1, open_delim, close_delim)
                if right != -1 {
                    start = pos // Include the opening delimiter.
                    r, n := utf8.decode_rune(buffer.data[right:])
                    end = right + n // Include the closing delimiter.
                    found = true
                }
            } else if !is_open && delim == close_delim {
                // On closing delimiter (e.g., cursor on ')').
                left := find_enclosing_open_delim(buffer, pos - 1, open_delim, close_delim)
                if left != -1 {
                    start = left // Include the opening delimiter.
                    end = pos + 1 // Include the closing delimiter.
                    found = true
                }
            }
        } else {
            // Not on a delimiter, check if inside an enclosing pair.
            left := find_enclosing_open_delim(buffer, pos, open_delim, close_delim)
            right := find_enclosing_close_delim(buffer, pos, open_delim, close_delim)
            if left != -1 && right != -1 && left < pos && pos <= right {
                start = left // Include the opening delimiter.
                r, n := utf8.decode_rune(buffer.data[right:])
                end = right + n // Include the closing delimiter.
                found = true
            } else {
                // Not inside a pair, find the next opening delimiter.
                next_open := find_next_open_delim(buffer, pos, open_delim)
                if next_open != -1 {
                    right := find_enclosing_close_delim(buffer, next_open + 1, open_delim, close_delim)
                    if right != -1 {
                        start = next_open // Include the opening delimiter.
                        r, n := utf8.decode_rune(buffer.data[right:])
                        end = right + n // Include the closing delimiter.
                        found = true
                    }
                }
            }
        }
    }
    
    return start, end, found
}

get_matching_delimiters :: proc(delim: rune) -> (open: rune, close: rune) {
	if delim == '"' || delim == '\'' {
		return delim, delim
	}

	for pair in Matching_Delimiters {
		if delim == pair.open || delim == pair.close {
			return pair.open, pair.close
		}
	}
	
	return 0, 0 // Invalid delimiter.
}

//
// Helpers
// 

// Helper function to check if cursor is on a delimiter.
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

find_previous_quote_pair :: proc(buffer: ^Buffer, pos: int, quote: rune) -> (first: int, second: int, found: bool) {
	second_quote_pos := find_nearest_quote_left(buffer, pos, quote) // Closing quote of the previous pair.
	if second_quote_pos == -1 do return 0, 0, false
	first_quote_pos := find_nearest_quote_left(buffer, second_quote_pos, quote) // Opening quote.
	if first_quote_pos == -1 do return 0, 0, false
	return first_quote_pos, second_quote_pos, true
}

find_next_quote_pair :: proc(buffer: ^Buffer, pos: int, quote: rune) -> (first: int, second: int, found: bool) {
	first_quote_pos := find_nearest_quote_right(buffer, pos, quote) // Opening quote of the next pair.
	if first_quote_pos == -1 do return 0, 0, false
	second_quote_pos := find_nearest_quote_right(buffer, first_quote_pos + 1, quote) // Closing quote.
	if second_quote_pos == -1 do return 0, 0, false
	return first_quote_pos, second_quote_pos, true
}

find_paragraph_start :: proc(buffer: ^Buffer, current_line: int) -> int {
	line := current_line
	
	// Move up until we hit a blank line or the start of the file.
	for line > 0 && !is_blank_line(buffer, line - 1) do line -= 1 
	
	// Move down to the first non-blank line (start of paragraph).
	for line < len(buffer.line_starts) && is_blank_line(buffer, line) do line += 1

	return line
}

find_paragraph_end :: proc(buffer: ^Buffer, current_line: int) -> int {
	line := current_line

	// Move down until we hit a blank line or the end of the file.
	for line < len(buffer.line_starts) - 1 && !is_blank_line(buffer, line + 1) do line += 1

	// Move up to the last non-blank line (end of paragraph).
	for line >= 0 && is_blank_line(buffer, line) do line -= 1

	return max(line, 0) // Ensure we never go below 0.
}

is_blank_line :: proc(buffer: ^Buffer, line: int) -> bool {
	if line < 0 || line > len(buffer.line_starts) do return true // Treat out-of-bounds as blank for boundary purposes.
	start := buffer.line_starts[line]
	end := len(buffer.data)
	if line < len(buffer.line_starts) - 1 {
		end = buffer.line_starts[line + 1 ] - 1 // Up to but not including the newline.
	}

	for i := start; i < end; i += 1 {
		r, _ := utf8.decode_rune(buffer.data[i:])
		if !strings.is_space(r) do return false // Found a non-whitespace character.
	}

	return true
}

get_matching_open_delimiter :: proc(delim: rune) -> rune {
    assert(delim == '}' || delim == ')' || delim == ']', "Input must be a recognized closing delimiter")
    switch delim {
    case '}': return '{'
    case ')': return '('
    case ']': return '['
    }

    return 0 // Not recognized closing delimiter.
} 

find_matching_open_delimiter :: proc(buffer: ^Buffer, pos: int, open_delim, close_delim: rune) -> int {
    assert(pos >= 0 && pos < len(buffer.data), "Starting position must be within buffer bounds")
    counter := 0
    current_pos := pos
    for current_pos >= 0 {
        r, _ := utf8.decode_rune(buffer.data[current_pos:])
        if r == close_delim {
            counter += 1
        } else if r == open_delim {
            counter -= 1
            if counter == 0 {
                return current_pos // Found the matching opening delimiter
            }
        }
        current_pos = prev_rune_start(buffer.data[:], current_pos)
    }
    return -1 // No match found
}

