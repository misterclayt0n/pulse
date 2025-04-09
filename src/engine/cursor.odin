package engine

import rl "vendor:raylib"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

Cursor :: struct {
	pos:           int, // Position in the array of bytes.
	sel:           int,
	line:          int, // Current line number.
	col:           int, // Current column (character, not byte index) in the line.
	preferred_col: int, // Preferred column maintained across vertical movements.
	style:         Cursor_Style,
	color:         rl.Color,
	blink:         bool,
}

Cursor_Style :: enum {
	BAR,
	BLOCK,
	UNDERSCORE,
}

Cursor_Movement :: enum {
	LEFT,
	RIGHT,
	UP,
	DOWN,
	LINE_START,
	LINE_END,
	WORD_LEFT,
	WORD_RIGHT,
	WORD_END,
	FIRST_NON_BLANK,
	FILE_BEGINNING,
	FILE_END,
	BIG_WORD_RIGHT,
	BIG_WORD_END,
	BIG_WORD_LEFT,
	// TODO: A lot more
}

Cursor_Placement :: enum {
	START, // Place cursor at the start column (for I, C, D, X).
    END,   // Place cursor *after* the end column (for A).
    START_AFTER_DELETE, // Special case for C maybe? TODO.
}

cursor_draw :: proc(window: ^Window, font: Font, ctx: Draw_Context) {
	using window
	cursor_pos := ctx.position

	// Adjust vertical position based on line number.
	cursor_pos.y += f32(cursor.line) * (f32(font.size) + font.spacing)

	assert(cursor.pos >= 0, "Cursor position must be greater or equal to 0")
	assert(len(buffer.data) >= 0, "Buffer size has to be greater or equal to 0")

	line_start := buffer.line_starts[cursor.line]
	cursor_pos_clamped := min(cursor.pos, len(buffer.data)) // NOTE: Make sure we cannot slice beyond the buffer size.
	assert(
		line_start <= cursor_pos_clamped,
		"Line start index must be less or equal to clamped cursor position",
	)
	assert(
		line_start >= 0 && line_start <= len(buffer.data),
		"line_start out of range in buffer_draw_cursor",
	)

	if cursor.pos > line_start {
		line_text := buffer.data[line_start:cursor_pos_clamped]
		assert(len(line_text) >= 0, "Line text cannot be negative")
		temp_text := make([dynamic]u8, len(line_text) + 1)
		defer delete(temp_text)
		copy(temp_text[:], line_text)
		temp_text[len(line_text)] = 0
		cursor_pos.x += rl.MeasureTextEx(font.ray_font, cstring(&temp_text[0]), f32(font.size), font.spacing).x + 2 // NOTE: Add 2 for alignment.
	} else {
		// NOTE: For the first character, no text width to measure, so we can just use ctx.position as is.
	}

	if cursor.blink && (int(rl.GetTime() * 2) % 2 == 0) do return

	font_size := f32(font.size)

	switch cursor.style {
	case .BAR:
		if window.is_focus do rl.DrawLineV(cursor_pos, {cursor_pos.x, cursor_pos.y + font_size}, cursor.color)
	case .BLOCK:
		char_width := rl.MeasureTextEx(font.ray_font, "@", font_size, font.spacing).x
		if window.is_focus {
			rl.DrawRectangleV(
				cursor_pos,
				{char_width, font_size},
				{cursor.color.r, cursor.color.g, cursor.color.b, 128},
			)
		} else {
			// Draw outline-only block for unfocused windows.
			rl.DrawRectangleLinesEx(
				rl.Rectangle{cursor_pos.x, cursor_pos.y, char_width, font_size},
				1,
				{CURSOR_COLOR.r, CURSOR_COLOR.g, CURSOR_COLOR.b, 80}, // Slightly transparent.
			)
		}
	case .UNDERSCORE:
		char_width := rl.MeasureTextEx(font.ray_font, "M", font_size, font.spacing).x
		if window.is_focus {
			rl.DrawLineV(
				{cursor_pos.x, cursor_pos.y + font_size},
				{cursor_pos.x + char_width, cursor_pos.y + font_size},
				cursor.color,
			)
		}
	}

    for &extra_cursor in window.additional_cursors {
        cursor_pos = ctx.position
        cursor_pos.y += f32(extra_cursor.line) * (f32(font.size) + font.spacing)
        line_start = window.buffer.line_starts[extra_cursor.line]
        cursor_pos_clamped = min(extra_cursor.pos, len(window.buffer.data))
        if extra_cursor.pos > line_start {
            line_text := window.buffer.data[line_start:cursor_pos_clamped]
            temp_text := make([dynamic]u8, len(line_text) + 1)
            defer delete(temp_text)
            copy(temp_text[:], line_text)
            temp_text[len(line_text)] = 0
            cursor_pos.x += rl.MeasureTextEx(font.ray_font, cstring(&temp_text[0]), f32(font.size), font.spacing).x + 2
        }
        if !extra_cursor.blink || (int(rl.GetTime() * 2) % 2 != 0) {
            font_size := f32(font.size)
            switch extra_cursor.style {
            case .BAR:
                if window.is_focus do rl.DrawLineV(cursor_pos, {cursor_pos.x, cursor_pos.y + font_size}, extra_cursor.color)
            case .BLOCK:
                char_width := rl.MeasureTextEx(font.ray_font, "@", font_size, font.spacing).x
                if window.is_focus {
                    rl.DrawRectangleV(cursor_pos, {char_width, font_size}, {extra_cursor.color.r, extra_cursor.color.g, extra_cursor.color.b, 128})
                } else {
                    rl.DrawRectangleLinesEx(rl.Rectangle{cursor_pos.x, cursor_pos.y, char_width, font_size}, 1, {CURSOR_COLOR.r, CURSOR_COLOR.g, CURSOR_COLOR.b, 80})
                }
            case .UNDERSCORE:
                char_width := rl.MeasureTextEx(font.ray_font, "M", font_size, font.spacing).x
                if window.is_focus {
                    rl.DrawLineV({cursor_pos.x, cursor_pos.y + font_size}, {cursor_pos.x + char_width, cursor_pos.y + font_size}, extra_cursor.color)
                }
            }
        }
    }
}

cursor_move :: proc(cursor: ^Cursor, buffer: ^Buffer, movement: Cursor_Movement) {
    current_line_start := buffer.line_starts[cursor.line]
    current_line_end := len(buffer.data)
    if cursor.line < len(buffer.line_starts) - 1 {
        current_line_end = buffer.line_starts[cursor.line + 1] - 1
    }
    horizontal: bool

    #partial switch movement {

	//
	// Horizontal movement
	//

    case .LEFT:
        if cursor.pos > current_line_start {
            cursor.pos = prev_rune_start(buffer.data[:], cursor.pos)
        }
        horizontal = true
    case .RIGHT:
		// Only move right if we're not already at the last character.
		if cursor.pos < current_line_end {
			// Special handling for CLI buffers.
			if buffer.is_cli {
				n_bytes := next_rune_length(buffer.data[:], cursor.pos)
				cursor.pos += n_bytes
			} else {
				// Don't allow moving from last character to end-of-line position.
				if cursor.pos + 1 == current_line_end {
					// We're at the last character already, don't move.
				} else {
					n_bytes := next_rune_length(buffer.data[:], cursor.pos)
					cursor.pos += n_bytes
				}
			}
		}
		horizontal = true

	case .LINE_START:
		cursor.pos = buffer.line_starts[cursor.line]
		horizontal = true

	case .FIRST_NON_BLANK:
		current_line_start := buffer.line_starts[cursor.line]
		current_line_end := len(buffer.data)
		if cursor.line < len(buffer.line_starts) - 1 {
			current_line_end = buffer.line_starts[cursor.line + 1] - 1
		}

		pos := current_line_start
		// Skip whitespace characters.
		for pos < current_line_end && is_whitespace_byte(buffer.data[pos]) {
			pos += 1
		}

		// If all whitespace or empty line, start at start.
		if pos == current_line_end do pos = current_line_start
		cursor.pos = pos
		horizontal = true
	case .LINE_END:
		current_line := cursor.line
		current_line_start := buffer.line_starts[current_line]

		// Handle CLI buffers differently.
		if buffer.is_cli {
			cursor.pos = len(buffer.data)
			horizontal = true
			break
		}

		if cursor.line < len(buffer.line_starts) - 1 {
			line_end := buffer.line_starts[cursor.line + 1] // Position after newline.
			if line_end > current_line_start + 1 do cursor.pos = prev_rune_start(buffer.data[:], line_end - 1)
			else do cursor.pos = current_line_start
		} else {
			// Last line has characters.
			if len(buffer.data) > current_line_start do cursor.pos = prev_rune_start(buffer.data[:], len(buffer.data))
			// Last line is empty.
			else do cursor.pos = current_line_start
		}

		horizontal = true

	case .WORD_LEFT:
		new_pos, found := buffer_find_previous_word_start(buffer, cursor.pos, .WORD)
		if found {
			cursor.pos = new_pos
		} else if cursor.pos > 0 {
			cursor.pos = 0
		}

		horizontal = true

	case .WORD_RIGHT:
		new_pos, found := buffer_find_next_word_start(buffer, cursor.pos, .WORD)
		if found {
			cursor.pos = new_pos
		} else if cursor.pos < len(buffer.data) {
			cursor.pos = len(buffer.data)
		}

		horizontal = true

	case .WORD_END:
		new_pos, found := buffer_find_next_word_end(buffer, cursor.pos, .WORD)
		if found {
			cursor.pos = new_pos
		} else if cursor.pos < len(buffer.data) {
			cursor.pos = len(buffer.data) - 1
		}
		horizontal = true

	case .BIG_WORD_RIGHT:
		new_pos, found := buffer_find_next_word_start(buffer, cursor.pos, .BIG_WORD)
		if found {
			cursor.pos = new_pos
		} else if cursor.pos < len(buffer.data) {
			cursor.pos = len(buffer.data) // Move to end if no next word.
		}
		horizontal = true

	case .BIG_WORD_END:
		new_pos, found := buffer_find_next_word_end(buffer, cursor.pos, .BIG_WORD)
		if found {
			cursor.pos = new_pos
		} else if cursor.pos < len(buffer.data) {
			cursor.pos = len(buffer.data) - 1 // Move to last char if no next word end.
		}
		horizontal = true

	case .BIG_WORD_LEFT:
		new_pos, found := buffer_find_previous_word_start(buffer, cursor.pos, .BIG_WORD)
		if found {
			cursor.pos = new_pos
		} else if cursor.pos > 0 {
			cursor.pos = 0 // Move to start if no previous word.
		}
		horizontal = true

	//
	// Vertical movement
	//

	case .UP:
		if cursor.line > 0 {
			// Get target col (preserved from the current position).
			target_col := cursor.preferred_col != -1 ? cursor.preferred_col : cursor.col
			assert(target_col >= 0, "Target column cannot be negative")

			new_line := cursor.line - 1 // Move to prev line.

			// Calculate new position.
			new_line_length := buffer_line_length(buffer, new_line)
			new_col := min(target_col, new_line_length)

			// Calculate the line end.
			new_line_end := len(buffer.data)
			if new_line < len(buffer.line_starts) - 1 {
				new_line_end = buffer.line_starts[new_line + 1] - 1
			}

			// Calculate the position based on target col.
			new_pos := buffer.line_starts[new_line] + new_col

			if new_pos == new_line_end &&
			   new_col > 0 &&
			   new_line_end > buffer.line_starts[new_line] {
				new_pos = prev_rune_start(buffer.data[:], new_pos)
			}

			cursor.pos = new_pos
		}
	case .DOWN:
		if cursor.line < len(buffer.line_starts) - 1 {
			// Same stuff as before.
			target_col := cursor.preferred_col != -1 ? cursor.preferred_col : cursor.col
			assert(target_col >= 0, "Target column cannot be negative")

			new_line := cursor.line + 1 // Move to next line.

			// Calculate new position.
			new_line_length := buffer_line_length(buffer, new_line)
			new_col := min(target_col, new_line_length)

			// If we're at the last character, do not allow positioning after it unless
			// target_col is 0 (allowing positioning at start of empty lines).
			new_line_end := len(buffer.data)
			if new_line < len(buffer.line_starts) - 1 {
				new_line_end = buffer.line_starts[new_line + 1] - 1
			}

			new_pos := buffer.line_starts[new_line] + new_col

			// Don't allow positioning after the last character.
			if new_pos == new_line_end &&
			   new_col > 0 &&
			   new_line_end > buffer.line_starts[new_line] {
				// Back up one character.
				new_pos = prev_rune_start(buffer.data[:], new_pos)
			}

			cursor.pos = new_pos
		}

	case .FILE_BEGINNING:
		cursor.line = 0
		cursor.pos = buffer.line_starts[0]
		cursor.col = 0

	case .FILE_END:
		last_line := len(buffer.line_starts) - 1
		cursor.line = last_line
		cursor.pos = buffer.line_starts[last_line]
		cursor.col = 0
    }

	// Update line and column after movement.
    cursor.line = 0
    for i := 1; i < len(buffer.line_starts); i += 1 {
        if cursor.pos >= buffer.line_starts[i] {
            cursor.line = i
        } else {
            break
        }
    }

    cursor.col = cursor.pos - buffer.line_starts[cursor.line]

    if horizontal {
        cursor.preferred_col = cursor.col
    }
}

// Adds a cursor at a specific position if not already present
add_cursor_at_pos :: proc(window: ^Window, pos: int, allocator := context.allocator) -> bool {
	// Check main cursor and additional cursors.
    if window.cursor.pos == pos do return false
    for &c in window.additional_cursors {
        if c.pos == pos do return false
    }

    line := get_line_from_pos(window.buffer, pos)
    col := pos - window.buffer.line_starts[line]
    new_cursor := Cursor {
        pos           = pos,
        sel           = pos, // No selection initially.
        line          = line,
        col           = col,
        preferred_col = col,
        style         = .BLOCK,
        color         = {CURSOR_COLOR.r, CURSOR_COLOR.g, CURSOR_COLOR.b, 180}, // NOTE: Slightly transparent.
        blink         = false,
    }
    append(&window.additional_cursors, new_cursor)
    return true
}

// Handles Alt+D logic for multi-cursor word selection.
add_multi_cursor_word :: proc(p: ^Pulse, allocator := context.allocator) {
    window := p.current_window

    if !window.multi_cursor_active {
    	// First press: determine what to select based on mode.
        start, end: int
        pattern: string
        success: bool
        original_mode := window.mode

        if original_mode == .NORMAL {
        	change_mode(p, .VISUAL)
            start, end, pattern, success = select_word_under_cursor(window, allocator)
            if !success {
                status_line_log(&p.status_line, "No word under cursor")
                return
            }
        } else if original_mode == .VISUAL {
            // In VISUAL mode, use the current selection.
            start = min(window.cursor.sel, window.cursor.pos)
            end = max(window.cursor.sel , window.cursor.pos) // End is the last character.
            if start == end {
                status_line_log(&p.status_line, "No valid selection")
                return
            }
            pattern_bytes := window.buffer.data[start:end + 1] // Include cursor position.
            pattern = strings.clone_from_bytes(pattern_bytes, allocator)

            // Keep the current selection active.
            window.cursor.sel = start
            window.cursor.pos = end // Position at end of selection (last char).
            window.cursor.line = get_line_from_pos(window.buffer, window.cursor.pos)
            window.cursor.col = window.cursor.pos - window.buffer.line_starts[window.cursor.line]
            success = true
        } else {
            status_line_log(&p.status_line, "Multi-cursor not supported in this mode")
            return
        }

        if success {
            window.multi_cursor_word = pattern
            window.multi_cursor_active = true

            // In visual mode, immediately select the next occurence.
            if original_mode == .VISUAL {
            	last_pos := window.cursor.pos
            	for &c in window.additional_cursors {
            		last_pos = max(last_pos, c.pos)
            	}
            	next_pos, found := find_next_word_occurrence(window.buffer, window.multi_cursor_word, last_pos + 1)
            	if found {
            		if add_cursor_at_pos(window, next_pos, allocator) {
            			last_cursor := &window.additional_cursors[len(window.additional_cursors) - 1]
                        last_cursor.sel = next_pos
                        last_cursor.pos = next_pos + len(window.multi_cursor_word) - 1
                        last_cursor.line = get_line_from_pos(window.buffer, last_cursor.pos)
                        last_cursor.col = last_cursor.pos - window.buffer.line_starts[last_cursor.line]
                        window.last_added_cursor_pos = last_cursor.pos
            		} else {
            			status_line_log(&p.status_line, "No more occurrences of '%s'", window.multi_cursor_word)
            		}
            	}
            }

            window.last_added_cursor_pos = window.cursor.pos
        }
    } else {
        // Subsequent presses: find next occurrence.
        last_pos := window.cursor.pos
        for &c in window.additional_cursors {
            last_pos = max(last_pos, c.pos)
        }
        next_pos, found := find_next_word_occurrence(window.buffer, window.multi_cursor_word, last_pos + 1)
        if found {
            // Add cursor at the start of the next occurrence.
            if add_cursor_at_pos(window, next_pos, allocator) {
                // Set selection for the new cursor.
                last_cursor := &window.additional_cursors[len(window.additional_cursors) - 1]
                last_cursor.sel = next_pos
                last_cursor.pos = next_pos + len(window.multi_cursor_word) - 1
                last_cursor.line = get_line_from_pos(window.buffer, last_cursor.pos)
                last_cursor.col = last_cursor.pos - window.buffer.line_starts[last_cursor.line]
                window.last_added_cursor_pos = last_cursor.pos
            }
        } else {
            // No more occurrences; could wrap around or stop.
            status_line_log(&p.status_line, "No more occurrences of '%s'", window.multi_cursor_word)
        }
    }
}

// Handles Ctrl+Alt+D logic for multi-cursor word selection, searching backward.
add_multi_cursor_word_backward :: proc(p: ^Pulse, allocator := context.allocator) {
    window := p.current_window

    if !window.multi_cursor_active {
        start, end: int
        pattern: string
        success: bool
        original_mode := window.mode

        if original_mode == .NORMAL {
            change_mode(p, .VISUAL)
            start, end, pattern, success = select_word_under_cursor(window, allocator)
            if !success {
                status_line_log(&p.status_line, "No word under cursor")
                return
            }
        } else if original_mode == .VISUAL {
            start = min(window.cursor.sel, window.cursor.pos)
            end = max(window.cursor.sel, window.cursor.pos)
            if start == end {
                status_line_log(&p.status_line, "No valid selection")
                return
            }
            pattern_bytes := window.buffer.data[start:end + 1]
            pattern = strings.clone_from_bytes(pattern_bytes, allocator)
            window.cursor.sel = start
            window.cursor.pos = end
            window.cursor.line = get_line_from_pos(window.buffer, window.cursor.pos)
            window.cursor.col = window.cursor.pos - window.buffer.line_starts[window.cursor.line]
            success = true
        } else {
            status_line_log(&p.status_line, "Multi-cursor not supported in this mode")
            return
        }

        if success {
            window.multi_cursor_word = pattern
            window.multi_cursor_active = true
            window.last_added_cursor_pos = start 
        }
    } else {
        first_pos := window.cursor.sel 
        for &c in window.additional_cursors {
            first_pos = min(first_pos, c.sel) // Find earliest selection start.
        }

        prev_pos, found := find_previous_word_occurrence(window.buffer, window.multi_cursor_word, first_pos)
        if found {
            // Ensure we’re not re-adding an existing cursor
            if add_cursor_at_pos(window, prev_pos, allocator) {
                last_cursor := &window.additional_cursors[len(window.additional_cursors) - 1]
                last_cursor.sel = prev_pos
                last_cursor.pos = prev_pos + len(window.multi_cursor_word) - 1
                last_cursor.line = get_line_from_pos(window.buffer, last_cursor.pos)
                last_cursor.col = last_cursor.pos - window.buffer.line_starts[last_cursor.line]
                window.last_added_cursor_pos = prev_pos // Track earliest added position.
            } else {
                status_line_log(&p.status_line, "No more occurences of '%s'", window.multi_cursor_word)
            }
        } else {
            status_line_log(&p.status_line, "No previous occurrences of '%s' before %d", window.multi_cursor_word, first_pos)
        }
    }
}

// Finds the previous occurrence of a word before a given position
find_previous_word_occurrence :: proc(buffer: ^Buffer, word: string, start_pos: int) -> (pos: int, found: bool) {
    search_pos := max(0, start_pos - 1) // Start one position before to avoid matching at start_pos
    pattern_bytes := transmute([]u8)word
    pattern_len := len(pattern_bytes)

    for search_pos >= 0 {
        if search_pos + pattern_len <= len(buffer.data) &&
           slice.equal(buffer.data[search_pos:search_pos + pattern_len], pattern_bytes) {
            return search_pos, true
        }
        search_pos -= 1
    }
    return -1, false
}

add_global_cursors :: proc(p: ^Pulse, allocator := context.allocator) {
	window := p.current_window

	start, end, word, success := select_word_under_cursor(window, allocator)
	if !success {
		status_line_log(&p.status_line, "No word under cursor")
		return
	}
	clear(&window.additional_cursors)
	
	change_mode(p, .VISUAL)
	window.cursor.sel = start
	window.cursor.pos = prev_rune_start(window.buffer.data[:], end)
	window.cursor.line = get_line_from_pos(window.buffer, window.cursor.pos)
	window.cursor.col = window.cursor.pos - window.buffer.line_starts[window.cursor.line]

	search_pos := 0
	word_len := len(word)
	last_pos := start // Track the last cursor position for scrolling.

	for {
		next_pos, found := find_next_word_occurrence(window.buffer, word, search_pos)
		if !found do break

		if next_pos == start {
			search_pos = next_pos + 1
			continue
		}

		if add_cursor_at_pos(window, next_pos, allocator) {
			last_cursor := &window.additional_cursors[len(window.additional_cursors) - 1]
            last_cursor.sel = next_pos
            last_cursor.pos = next_pos + word_len - 1
            last_cursor.line = get_line_from_pos(window.buffer, last_cursor.pos)
            last_cursor.col = last_cursor.pos - window.buffer.line_starts[last_cursor.line]
            last_pos = last_cursor.pos // Update last position.
		}

		search_pos = next_pos + 1
	}

	// Set the last added cursor position for scrolling.
    window.last_added_cursor_pos = last_pos

    // Store the word for potential incremental additions (optional).
    window.multi_cursor_word = word
    window.multi_cursor_active = true

    if len(window.additional_cursors) == 0 {
        status_line_log(&p.status_line, "No additional occurrences of '%s'", word)
    } else {
        status_line_log(&p.status_line, "Added %d cursors for '%s'", len(window.additional_cursors) + 1, word)
    }
}

// Move all cursors.
move_cursors :: proc(window: ^Window, movement: Cursor_Movement) {
	cursor_move(&window.cursor, window.buffer, movement)
    for &extra_cursor in window.additional_cursors {
        cursor_move(&extra_cursor, window.buffer, movement)
    }
}

get_sorted_cursors :: proc(window: ^Window, allocator := context.allocator) -> []^Cursor {
	all_cursors := get_all_cursors(window, allocator)
	defer delete(all_cursors, allocator)

	cursors := make([]^Cursor, len(all_cursors), allocator)
	for i := 0; i < len(cursors); i+= 1 {
		cursors[i] = &all_cursors[i]
	}

	slice.sort_by(cursors, proc(a, b: ^Cursor) -> bool { return a.pos > b.pos } )
	return cursors
}

adjust_cursors :: proc(cursors: []^Cursor, primary_cursor: ^Cursor, offset: int, add: bool, n_bytes: int) {
	for other_cursor in cursors {
		if other_cursor != primary_cursor && other_cursor.pos > offset {
			if add do other_cursor.pos += n_bytes
			else do other_cursor.pos -= n_bytes
		}
	}
}

update_cursors_from_temp_slice :: proc(window: ^Window, cursors: []^Cursor) {
    window.cursor = cursors[0]^
    for i := 0; i < len(window.additional_cursors); i += 1 {
        window.additional_cursors[i] = cursors[i + 1]^
    }
}

// Updates the line and column for all cursors based on their pos and the buffer's line_starts.
update_cursor_lines_and_cols :: proc(buffer: ^Buffer, cursors: []^Cursor) {
    for cursor_ptr in cursors {
        assert(cursor_ptr.pos >= 0 && cursor_ptr.pos <= len(buffer.data), "Cursor position out of bounds")

        cursor_ptr.line = 0
        for j in 1 ..< len(buffer.line_starts) {
            if cursor_ptr.pos >= buffer.line_starts[j] do cursor_ptr.line = j
	        else do break
        }

        assert(cursor_ptr.line >= 0 && cursor_ptr.line < len(buffer.line_starts), "Cursor line out of range")
        cursor_ptr.col = cursor_ptr.pos - buffer.line_starts[cursor_ptr.line]
        assert(cursor_ptr.col >= 0, "Cursor column must be non-negative")
    }
}

create_block_cursors :: proc(p: ^Pulse, placement: Cursor_Placement) -> bool {
    using p.current_window

    if visual_block_anchor_line == -1 {
        status_line_log(&p.status_line, "Attempted to create block cursors outside of visual block mode")
        return false
    }

    // Determine block boundaries.
    start_line := min(visual_block_anchor_line, cursor.line)
    end_line   := max(visual_block_anchor_line, cursor.line)

    current_col := cursor.preferred_col if cursor.preferred_col != -1 else cursor.col
    start_c := min(visual_block_anchor_col, current_col)
    end_c   := max(visual_block_anchor_col, current_col)

    target_col: int
    #partial switch placement {
    case .START:
        target_col = start_c
    case .END:
         // Vim 'A' places cursor *after* the block selection on each line.
        target_col = end_c + 1 // Place *after* the end column.
    case .START_AFTER_DELETE:
        // If deletion happened, columns might have shifted.
        // Simplest is still using start_c, user adjusts if needed.
        target_col = start_c
    }

    clear(&additional_cursors)

    for line_idx in start_line ..= end_line {
        if line_idx == cursor.line do continue
        if line_idx >= len(buffer.line_starts) do continue
        line_start_byte := buffer.line_starts[line_idx]
        line_len := buffer_line_content_length(buffer, line_idx)
        new_pos := buffer_get_pos_from_col(buffer, line_idx, target_col)

        new_cursor := Cursor {
            pos           = new_pos,
            sel           = new_pos, // No selection
            line          = line_idx,
            col           = new_pos,
            preferred_col = new_pos,
            style         = cursor.style,
            color         = {CURSOR_COLOR.r, CURSOR_COLOR.g, CURSOR_COLOR.b, 180}, // NOTE: Slightly different color?
            blink         = cursor.blink,
        }
        append(&additional_cursors, new_cursor)
    }

    cursor.col = cursor.pos - buffer.line_starts[cursor.line]
    cursor.preferred_col = cursor.col

    return true
}

// Selects the word under the cursor and returns its boundaries and text.
select_word_under_cursor :: proc(window: ^Window, allocator := context.allocator) -> (start, end: int, word: string, success: bool) {
	start, end = find_word_boundaries(window.buffer, window.cursor.pos)
	if start >= end do return 0, 0, "", false

	word_bytes := window.buffer.data[start:end]
	word = strings.clone_from_bytes(word_bytes, allocator)
	window.cursor.sel = start
    window.cursor.pos = prev_rune_start(window.buffer.data[:], end) // Position at last char of word.
    window.cursor.line = get_line_from_pos(window.buffer, window.cursor.pos)
    window.cursor.col = window.cursor.pos - window.buffer.line_starts[window.cursor.line]
    return start, end, word, true
}


// Finds the next occurrence of a word after a given position
find_next_word_occurrence :: proc(buffer: ^Buffer, word: string, start_pos: int) -> (pos: int, found: bool) {
	search_pos := start_pos
    pattern_bytes := transmute([]u8)word
    pattern_len := len(pattern_bytes)

    for search_pos + pattern_len <= len(buffer.data) {
        if slice.equal(buffer.data[search_pos:search_pos + pattern_len], pattern_bytes) {
            return search_pos, true
        }
        search_pos += 1 // Byte-by-byte search; optimize with Boyer-Moore or similar if needed
    }
    return -1, false
}

//
// Helpers
//

get_all_cursors :: proc(window: ^Window, allocator := context.allocator) -> []Cursor {
	cursors := make([]Cursor, 1 + len(window.additional_cursors), allocator) // 1 + to exclude the main cursor.
	cursors[0] = window.cursor
	for i := 0; i < len(window.additional_cursors); i += 1 {
		cursors[i + 1] = window.additional_cursors[i]
	}

	return cursors
}
