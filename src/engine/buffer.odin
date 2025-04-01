package engine

import "base:intrinsics"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:simd"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

// Buffer stores text as an array of bytes.
Buffer :: struct {
	data:           [dynamic]u8, // Dynamic array of bytes that contains text.
	line_starts:    [dynamic]int, // Indexes of the beginning of each line in the array byte.
	dirty:          bool, // If the buffer has been modified.
	is_cli:         bool,
	max_line_width: f32, // Maximum width of any line in the buffer.
	width_dirty:    bool, // Indicates if max_line_width needs recalculation.
}

// This struct holds parameters used during buffer drawing.
Draw_Context :: struct {
	position:      rl.Vector2,
	screen_width:  i32,
	screen_height: i32,
	first_line:    int,
	last_line:     int,
	line_height:   int,
}

Word_Type :: enum {
	WORD, // Regular word (alphanumeric + underscore, separated by punctuation/whitespace).
	BIG_WORD, // Big word (anything not whitespace is part of the word).
}

Char_Class :: enum {
	WHITESPACE,
	WORD,
	PUNCTUATION,
}

Selection_Range :: struct {
	start: int,
	end:   int,
}

// 
// Struct management
// 

// Creates a new buffer with a given initial capacity.
buffer_init :: proc(allocator := context.allocator, initial_cap := 1024) -> Buffer {
	return Buffer {
		data           = make([dynamic]u8, 0, initial_cap, allocator),
		line_starts    = make([dynamic]int, 1, 64, allocator),
		dirty          = false,
		max_line_width = 0,
		width_dirty    = true, // Initially true to calculate width on first use
	}
}

// NOTE: This is a bit useless if we're using an arena.
buffer_free :: proc(buffer: ^Buffer) {
	delete(buffer.data)
	delete(buffer.line_starts)
}

buffer_load_file :: proc(
	window: ^Window,
	filename: string,
	allocator := context.allocator,
) -> bool {
	data, ok := os.read_entire_file(filename, allocator)
	if !ok do return false

	// Replace buffer contents.
	clear(&window.buffer.data)
	append(&window.buffer.data, ..data)

	window.cursor.pos = 0
	window.buffer.dirty = false
	buffer_rebuild_line_starts(window) // Full rebuild since entire buffer is replaced.

	return true
}

//
// Editing
//

buffer_insert_text :: proc(window: ^Window, text: string) {
	using window
	assert(len(text) != 0, "The length of the text should not be 0")
	text_bytes := transmute([]u8)text
	n_bytes := len(text_bytes)

	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors)

	for cursor_ptr in cursors {
		offset := cursor_ptr.pos
		assert(offset >= 0, "Cursor offset must be greater or equal to 0")
		assert(
			!(offset > len(buffer.data)),
			"Cursor cannot be bigger than the length of the buffer",
		)


		// Make space for new text.
		resize(&buffer.data, len(buffer.data) + len(text_bytes))

		// Move existing text to make room.
		if (len(buffer.data) - len(text_bytes)) > offset {
			copy(buffer.data[offset + len(text_bytes):], buffer.data[offset:])
		}


		// Insert new text.
		copy(buffer.data[offset:], text_bytes)
		cursor_ptr.pos += n_bytes
		adjust_cursors(cursors, cursor_ptr, offset, true, n_bytes)

		buffer_mark_dirty(buffer)

		buffer_update_line_starts(window, offset)

		assert(len(buffer.data) >= 0, "Buffer length corrupted")
		assert(cursor.pos <= len(buffer.data), "Cursor position out of bounds")
	}

	update_cursor_lines_and_cols(buffer, cursors)
	update_cursors_from_temp_slice(window, cursors)
}

buffer_insert_char :: proc(window: ^Window, char: rune) {
	using window
	assert(utf8.valid_rune(char), "Invalid UTF-8 rune inserted")
	if !is_char_supported(char) do return
	old_len := len(buffer.data)

	// Get sorted cursors (right to left to avoid shifting issues)
	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors, context.temp_allocator)

	// Process each cursor from right to left
	for cursor_ptr in cursors {
		offset := cursor_ptr.pos
		assert(offset >= 0, "Cursor offset must be greater or equal to 0")
		assert(offset <= len(buffer.data), "Cursor cannot be bigger than the length of the buffer")

		// Encode rune into UTF-8
		encoded, n_bytes := utf8.encode_rune(char)

		// Make space for new character
		resize(&buffer.data, len(buffer.data) + n_bytes)
		if offset < len(buffer.data) - n_bytes {
			copy(buffer.data[offset + n_bytes:], buffer.data[offset:])
		}

		// Insert new character
		copy(buffer.data[offset:], encoded[0:n_bytes])

		// Update this cursor’s position
		cursor_ptr.pos += n_bytes

		// Adjust other cursors to the right of this one
		adjust_cursors(cursors, cursor_ptr, offset, true, n_bytes)

		buffer_mark_dirty(buffer)
		buffer_update_line_starts(window, offset)
	}

	update_cursor_lines_and_cols(buffer, cursors) // Update line and col for all cursors.
	update_cursors_from_temp_slice(window, cursors) // Sync the updated cursors back to window
}

buffer_insert_tab :: proc(window: ^Window, allocator := context.allocator) {
	if window.use_tabs do buffer_insert_char(window, '\t')
	else {
		indent_str := strings.repeat(" ", window.tab_width, allocator)
		buffer_insert_text(window, indent_str)
	}
}

buffer_insert_newline :: proc(window: ^Window, allocator := context.allocator) {
	buffer_insert_char(window, '\n')
	buffer_update_indentation(window, allocator)
}

buffer_insert_closing_delimiter :: proc(
	window: ^Window,
	delimiter: rune,
	allocator := context.allocator,
) {
	using window
	assert(utf8.rune_size(delimiter) == 1, "Delimiter must be a single-byte character")

	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors)

	for cursor_ptr in cursors {
		// Insert the closing delimiter at the cursor's position.
		offset := cursor_ptr.pos
		delimiter_byte := byte(delimiter)
		resize(&buffer.data, len(buffer.data) + 1)
		if offset < len(buffer.data) - 1 {
			copy(buffer.data[offset + 1:], buffer.data[offset:])
		}
		buffer.data[offset] = delimiter_byte
		cursor_ptr.pos += 1
		adjust_cursors(cursors, cursor_ptr, offset, true, 1) // Adjust other cursors to the right.
		buffer_mark_dirty(buffer)
		buffer_update_line_starts(window, offset)

		// Find the matching opening delimiter.
		matching_open := get_matching_open_delimiter(delimiter)
		if matching_open == 0 do continue // No matching open delimiter, skip indentation.

		open_pos := find_matching_open_delimiter(
			buffer,
			cursor_ptr.pos - 1,
			matching_open,
			delimiter,
		)
		if open_pos == -1 do continue // Matching delimiter not found, skip.

		// Calculate base indentation from the opening delimiter's line.
		open_line := get_line_from_pos(buffer, open_pos)
		open_line_start := buffer.line_starts[open_line]
		indent_end := open_line_start
		for indent_end < len(buffer.data) && buffer.data[indent_end] == ' ' {
			indent_end += 1
		}
		base_indent := indent_end - open_line_start

		// Get the current line’s indentation.
		current_line := cursor_ptr.line
		current_line_start := buffer.line_starts[current_line]
		current_indent_end := current_line_start
		for current_indent_end < len(buffer.data) && buffer.data[current_indent_end] == ' ' {
			current_indent_end += 1
		}
		current_indent := current_indent_end - current_line_start

		// Adjust indentation if necessary.
		desired_indent := base_indent
		if current_indent != desired_indent {
			// Remove existing indentation.
			if current_indent > 0 {
				copy(buffer.data[current_line_start:], buffer.data[current_indent_end:])
				resize(&buffer.data, len(buffer.data) - current_indent)
				cursor_ptr.pos -= current_indent
				adjust_cursors(cursors, cursor_ptr, current_line_start, false, current_indent)
			}

			// Insert new indentation.
			if desired_indent > 0 {
				indent_str := strings.repeat(" ", desired_indent, allocator)
				defer delete(indent_str, allocator)
				text_bytes := transmute([]u8)indent_str
				resize(&buffer.data, len(buffer.data) + desired_indent)
				copy(
					buffer.data[current_line_start + desired_indent:],
					buffer.data[current_line_start:],
				)
				copy(buffer.data[current_line_start:], text_bytes)
				cursor_ptr.pos += desired_indent
				adjust_cursors(cursors, cursor_ptr, current_line_start, true, desired_indent)
			}

			// Update buffer state after indentation adjustment.
			buffer_mark_dirty(buffer)
			buffer_update_line_starts(window, current_line_start)
		}
	}

	// Update all cursors' line and column fields after all modifications.
	update_cursor_lines_and_cols(buffer, cursors)
	update_cursors_from_temp_slice(window, cursors)
}

buffer_delete_char :: proc(window: ^Window) {
	using window
	assert(len(buffer.data) >= 0, "Delete called on invalid buffer")

	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors, context.temp_allocator)

	for cursor_ptr in cursors {
		assert(
			cursor_ptr.pos >= 0 && cursor_ptr.pos <= len(buffer.data),
			"Cursor position out of bounds",
		)
		if cursor_ptr.pos <= 0 do continue // Skip if at buffer start.

		// Determine the current line based on position and updated line_starts.
		line := 0
		for i in 1 ..< len(buffer.line_starts) {
			if cursor_ptr.pos < buffer.line_starts[i] {
				line = i - 1
				break
			}
		}
		if cursor_ptr.pos >= buffer.line_starts[len(buffer.line_starts) - 1] {
			line = len(buffer.line_starts) - 1
		}

		assert(line >= 0 && line < len(buffer.line_starts), "Calculated line out of bounds")
		line_start := buffer.line_starts[line]

		bytes_to_delete := 0
		start_index := cursor_ptr.pos

		if cursor_ptr.pos == line_start && line > 0 {
			// Delete the previous newline.
			start_index = cursor_ptr.pos - 1
			assert(buffer.data[start_index] == '\n', "Expected newline before line start")
			bytes_to_delete = 1
		} else if cursor_ptr.pos > line_start {
			// Check if in indentation.
			is_indentation := true
			for pos := line_start; pos < cursor_ptr.pos; pos += 1 {
				if buffer.data[pos] != ' ' && buffer.data[pos] != '\t' {
					is_indentation = false
					break
				}
			}
			if is_indentation && buffer.data[cursor_ptr.pos - 1] == ' ' {
				// Delete up to tab_width spaces.
				spaces := 0
				pos := cursor_ptr.pos - 1
				for pos >= line_start && buffer.data[pos] == ' ' && spaces < window.tab_width {
					spaces += 1
					pos -= 1
				}
				bytes_to_delete = spaces
				start_index = cursor_ptr.pos - spaces
			} else {
				// Delete one rune.
				start_index = prev_rune_start(buffer.data[:], cursor_ptr.pos)
				bytes_to_delete = cursor_ptr.pos - start_index
			}
		}

		if bytes_to_delete > 0 {
			assert(
				start_index <= cursor_ptr.pos,
				"Start index for deletion is after cursor position",
			)
			assert(
				start_index + bytes_to_delete <= len(buffer.data),
				"Deletion range exceeds buffer length",
			)

			// Perform deletion.
			old_len := len(buffer.data)
			copy(buffer.data[start_index:], buffer.data[cursor_ptr.pos:])
			resize(&buffer.data, len(buffer.data) - bytes_to_delete)
			assert(
				len(buffer.data) == old_len - bytes_to_delete,
				"Buffer length mismatch after deletion",
			)

			// Adjust other cursors.
			adjust_cursors(cursors, cursor_ptr, start_index, false, bytes_to_delete)

			// Move current cursor.
			cursor_ptr.pos = start_index

			// Update line structure.
			buffer_update_line_starts(window, start_index)
			buffer_mark_dirty(buffer)
		}
	}

	// Update all cursors' line and col fields.
	update_cursor_lines_and_cols(buffer, cursors)
	update_cursors_from_temp_slice(window, cursors)
}

buffer_delete_forward_char :: proc(window: ^Window) {
	using window
	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors, context.temp_allocator)

	for cursor_ptr in cursors {
		if cursor_ptr.pos >= len(buffer.data) do continue

		n_bytes := next_rune_length(buffer.data[:], cursor_ptr.pos)
		if n_bytes == 0 do continue

		// Delete the rune's bytes by shifting data to the left.
		copy(buffer.data[cursor_ptr.pos:], buffer.data[cursor_ptr.pos + n_bytes:])
		resize(&buffer.data, len(buffer.data) - n_bytes)

		// Adjust positions of other cursors to the right of the deletion point.
		for other_cursor in cursors {
			if other_cursor != cursor_ptr && other_cursor.pos > cursor_ptr.pos {
				other_cursor.pos -= n_bytes
			}
		}

		buffer_mark_dirty(buffer)
		buffer_update_line_starts(window, cursor_ptr.pos)
	}

	update_cursor_lines_and_cols(buffer, cursors)
	update_cursors_from_temp_slice(window, cursors)
}

buffer_delete_word :: proc(window: ^Window) {
	using window
	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors, context.temp_allocator)

	assert(len(buffer.data) >= 0, "Buffer data length must be non-negative")
	assert(len(cursors) > 0, "At least one cursor must be present")

	// Collect deletion ranges.
	ranges := make([dynamic][2]int, 0, len(cursors), context.temp_allocator)
	defer delete(ranges)

	for cursor_ptr in cursors {
		if cursor_ptr.pos <= 0 do continue

		original_pos := cursor_ptr.pos
		start_pos := original_pos

		// Move to word start.
		start_pos = prev_rune_start(buffer.data[:], start_pos)

		// Skip whitespace backwards.
		for start_pos > 0 && is_whitespace_byte(buffer.data[start_pos]) {
			start_pos = prev_rune_start(buffer.data[:], start_pos)
		}

		// Move through word characters.
		if start_pos > 0 {
			current_rune, _ := utf8.decode_rune(buffer.data[start_pos:])
			is_word := is_word_character(current_rune)

			for start_pos > 0 {
				prev_pos := prev_rune_start(buffer.data[:], start_pos)
				r, _ := utf8.decode_rune(buffer.data[prev_pos:])

				if is_whitespace_byte(buffer.data[prev_pos]) || is_word_character(r) != is_word do break

				start_pos = prev_pos
			}
		}

		// Ensure start_pos is not greater than original_pos.
		if start_pos < original_pos {
			append(&ranges, [2]int{start_pos, original_pos})
			assert(start_pos >= 0 && start_pos < len(buffer.data), "Start position out of bounds")
			assert(original_pos <= len(buffer.data), "Original position exceeds buffer length")
			assert(start_pos < original_pos, "Start position must be less than original position")
		}
	}

	// Sort ranges by start position.
	slice.sort_by(ranges[:], proc(a, b: [2]int) -> bool {return a[0] < b[0]})

	// Merge overlapping ranges.
	merged_ranges := make([dynamic][2]int, 0, len(ranges), context.temp_allocator)
	defer delete(merged_ranges)

	for r in ranges {
		if len(merged_ranges) == 0 {
			append(&merged_ranges, r)
		} else {
			last := &merged_ranges[len(merged_ranges) - 1]
			if r[0] <= last[1] {
				last[1] = max(last[1], r[1])
			} else {
				append(&merged_ranges, r)
			}
		}
	}

	// Perform deletions from the end to avoid index shifting issues.
	for i := len(merged_ranges) - 1; i >= 0; i -= 1 {
		r := merged_ranges[i]
		start := r[0]
		end := r[1]
		delete_size := end - start

		assert(start >= 0 && start < len(buffer.data), "Deletion start out of bounds")
		assert(end <= len(buffer.data), "Deletion end exceeds buffer length")
		assert(delete_size > 0, "Deletion size must be positive")

		// Delete the range.
		copy(buffer.data[start:], buffer.data[end:])
		resize(&buffer.data, len(buffer.data) - delete_size)

		// Adjust cursor positions.
		for cursor_ptr in cursors {
			if cursor_ptr.pos > start {
				cursor_ptr.pos -= delete_size
				if cursor_ptr.pos < start do cursor_ptr.pos = start
				assert(
					cursor_ptr.pos >= 0 && cursor_ptr.pos <= len(buffer.data),
					"Cursor position out of bounds after adjustment",
				)
			}
		}
	}

	// Update buffer state.
	if len(merged_ranges) > 0 {
		earliest_start := merged_ranges[0][0]
		buffer_mark_dirty(buffer)
		buffer_update_line_starts(window, earliest_start)
	}

	// Update cursor lines and columns.
	update_cursor_lines_and_cols(buffer, cursors)
	update_cursors_from_temp_slice(window, cursors)

	for cursor_ptr in cursors {
		assert(
			cursor_ptr.pos >= 0 && cursor_ptr.pos <= len(buffer.data),
			"Final cursor position out of bounds",
		)
		assert(
			cursor_ptr.line >= 0 && cursor_ptr.line < len(buffer.line_starts),
			"Cursor line out of bounds",
		)
	}
}

buffer_delete_line :: proc(window: ^Window) {
	using window
	if len(buffer.line_starts) == 0 do return // Buffer empty, nothing to delete.

	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors, context.temp_allocator)

	// Collect unique lines to delete.
	lines_to_delete := make(map[int]bool, len(cursors), context.temp_allocator)
	defer delete(lines_to_delete)

	for cursor_ptr in cursors {
		current_line := cursor_ptr.line
		if current_line >= len(buffer.line_starts) {
			current_line = len(buffer.line_starts) - 1 // Clamp to valid line.
		}
		assert(
			current_line >= 0 && current_line < len(buffer.line_starts),
			"Cursor line index out of bounds",
		)
		lines_to_delete[current_line] = true
	}

	// Convert to sorted slice of line ranges to delete.
	ranges := make([dynamic][2]int, 0, len(lines_to_delete), context.temp_allocator)
	defer delete(ranges)

	for line in lines_to_delete {
		start_pos := buffer.line_starts[line]
		end_pos := len(buffer.data)
		if line < len(buffer.line_starts) - 1 {
			end_pos = buffer.line_starts[line + 1] // Include newline.
		} else if line > 0 && line == len(buffer.line_starts) - 1 {
			// Last line: include the preceding newline if it exists.
			start_pos = buffer.line_starts[line] - 1
			assert(buffer.data[start_pos] == '\n', "Expected newline before last line")
		}
		append(&ranges, [2]int{start_pos, end_pos})
	}

	// Sort ranges by start position (ascending) to process deletions from end to start later.
	slice.sort_by(ranges[:], proc(a, b: [2]int) -> bool {return a[0] < b[0]})

	// Merge overlapping or adjacent ranges.
	merged_ranges := make([dynamic][2]int, 0, len(ranges), context.temp_allocator)
	defer delete(merged_ranges)

	for r in ranges {
		if len(merged_ranges) == 0 {
			append(&merged_ranges, r)
		} else {
			last := &merged_ranges[len(merged_ranges) - 1]
			if r[0] <= last[1] {
				last[1] = max(last[1], r[1])
			} else {
				append(&merged_ranges, r)
			}
		}
	}

	// Perform deletions from the end to avoid index shifting issues.
	original_buffer_len := len(buffer.data)
	total_deleted := 0
	for i := len(merged_ranges) - 1; i >= 0; i -= 1 {
		r := merged_ranges[i]
		start_pos := r[0]
		end_pos := r[1]

		// Validate deletion range.
		assert(start_pos >= 0 && start_pos <= len(buffer.data), "start_pos out of buffer bounds")
		assert(
			end_pos >= start_pos && end_pos <= len(buffer.data),
			"end_pos invalid relative to start_pos or buffer",
		)

		delete_size := end_pos - start_pos
		copy(buffer.data[start_pos:], buffer.data[end_pos:])
		resize(&buffer.data, len(buffer.data) - delete_size)
		total_deleted += delete_size

		// Adjust cursor positions.
		for cursor_ptr in cursors {
			if cursor_ptr.pos >= end_pos {
				cursor_ptr.pos -= delete_size
			} else if cursor_ptr.pos > start_pos {
				cursor_ptr.pos = start_pos
			}
		}
	}

	// Update buffer state if any deletions occurred.
	if len(merged_ranges) > 0 {
		earliest_start := merged_ranges[0][0]
		buffer_mark_dirty(buffer)
		buffer_update_line_starts(window, earliest_start)

		// Validate buffer length.
		assert(
			len(buffer.data) == original_buffer_len - total_deleted,
			"Buffer length mismatch after deletions",
		)
	}

	// Adjust cursor positions post-deletion.
	for cursor_ptr in cursors {
		if len(buffer.line_starts) == 0 {
			cursor_ptr.line = 0
			cursor_ptr.pos = 0
			cursor_ptr.col = 0
		} else {
			// Find the new line for each cursor based on its adjusted position.
			new_line := 0
			for i in 0 ..< len(buffer.line_starts) {
				if cursor_ptr.pos < buffer.line_starts[i] {
					new_line = max(0, i - 1)
					break
				}
			}
			if cursor_ptr.pos >= buffer.line_starts[len(buffer.line_starts) - 1] {
				new_line = len(buffer.line_starts) - 1
			}
			cursor_ptr.line = new_line
			cursor_ptr.pos = clamp(cursor_ptr.pos, 0, len(buffer.data))
			if cursor_ptr.pos < buffer.line_starts[cursor_ptr.line] {
				cursor_ptr.pos = buffer.line_starts[cursor_ptr.line]
			}
			cursor_ptr.col = cursor_ptr.pos - buffer.line_starts[cursor_ptr.line]
		}

		// Post-deletion cursor assertions.
		assert(
			cursor_ptr.line >= 0 && cursor_ptr.line < len(buffer.line_starts),
			"Cursor line out of bounds",
		)
		assert(
			cursor_ptr.pos >= 0 && cursor_ptr.pos <= len(buffer.data),
			"Cursor position out of buffer bounds",
		)
		assert(
			cursor_ptr.pos >= buffer.line_starts[cursor_ptr.line],
			"Cursor position before line start",
		)
	}

	update_cursor_lines_and_cols(buffer, cursors)
	update_cursors_from_temp_slice(window, cursors)
}

// Works just like buffer_delete_line, but without cursor position adjustments
buffer_change_line :: proc(window: ^Window) {
	using window
	if len(buffer.line_starts) == 0 do return // Buffer empty, nothing to change.

	// Get all the active cursors.
	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors, context.temp_allocator)

	// Build a set of unique lines from all cursors.
	unique_lines := make(map[int]bool, len(cursors), context.temp_allocator)
	for cursor_ptr in cursors {
		line := cursor_ptr.line
		if line >= len(buffer.line_starts) do line = len(buffer.line_starts) - 1
		unique_lines[line] = true
	}

	ranges := make([dynamic][2]int, 0, len(unique_lines), context.temp_allocator)
	for line in unique_lines {
		start_pos := buffer.line_starts[line]
		end_pos := len(buffer.data)
		if line < len(buffer.line_starts) - 1 {
			end_pos = buffer.line_starts[line + 1] - 1 // Exclude the newline.
		}
		append(&ranges, [2]int{start_pos, end_pos})
	}

	// Sort the ranges by start position.
	slice.sort_by(ranges[:], proc(a, b: [2]int) -> bool {return a[0] < b[0]})

	// Merge overlapping or adjacent ranges (in case multiple cursors are on the same line).
	merged_ranges := make([dynamic][2]int, 0, len(ranges), context.temp_allocator)
	for r in ranges {
		if len(merged_ranges) == 0 {
			append(&merged_ranges, r)
		} else {
			last := &merged_ranges[len(merged_ranges) - 1]
			if r[0] <= last[1] { 	// overlapping or adjacent
				last[1] = max(last[1], r[1])
			} else {
				append(&merged_ranges, r)
			}
		}
	}

	// Delete the content for each merged range in reverse order.
	for i := len(merged_ranges) - 1; i >= 0; i -= 1 {
		r := merged_ranges[i]
		start_pos := r[0]
		end_pos := r[1]
		assert(start_pos >= 0 && start_pos <= len(buffer.data), "start_pos out of bounds")
		assert(end_pos >= start_pos && end_pos <= len(buffer.data), "end_pos invalid")
		delete_size := end_pos - start_pos

		old_len := len(buffer.data)
		copy(buffer.data[start_pos:], buffer.data[end_pos:])
		resize(&buffer.data, len(buffer.data) - delete_size)
		assert(len(buffer.data) == old_len - delete_size, "Buffer resize mismatch")

		// Adjust positions for all cursors.
		for cursor_ptr in cursors {
			if cursor_ptr.pos >= end_pos {
				cursor_ptr.pos -= delete_size
			} else if cursor_ptr.pos > start_pos {
				cursor_ptr.pos = start_pos
			}
		}
	}

	// Update the buffer state.
	if len(merged_ranges) > 0 {
		earliest_start := merged_ranges[0][0]
		buffer_mark_dirty(buffer)
		buffer_update_line_starts(window, earliest_start)
	}

	// Reset each cursor on a changed line to the beginning (and set its column to 0).
	for cursor_ptr in cursors {
		new_line := get_line_from_pos(buffer, cursor_ptr.pos)
		cursor_ptr.line = new_line
		cursor_ptr.pos = buffer.line_starts[new_line]
		cursor_ptr.col = 0
		assert(cursor_ptr.pos == buffer.line_starts[new_line], "Cursor position mismatch")
		assert(cursor_ptr.col == 0, "Cursor column not reset")
	}

	update_cursor_lines_and_cols(buffer, cursors)
	update_cursors_from_temp_slice(window, cursors)

	buffer_update_indentation(window)
}


buffer_delete_to_line_end :: proc(window: ^Window) {
	using window
	// Get all active cursors.
	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors, context.temp_allocator)

	// Map each line to its deletion range [start, end).
	// For a given line, the deletion range starts at the smallest clamped cursor.pos
	// and ends at the line end (for non-last lines: line_starts[line+1] - 1; otherwise, len(buffer.data)).
	deletion_map := make(map[int][2]int, len(cursors), context.temp_allocator)
	for cursor_ptr in cursors {
		line := cursor_ptr.line
		if line >= len(buffer.line_starts) do line = len(buffer.line_starts) - 1

		start_pos := buffer.line_starts[line]
		end_pos := len(buffer.data)
		if line < len(buffer.line_starts) - 1 {
			end_pos = buffer.line_starts[line + 1] - 1 // Exclude the newline.
		}

		// Clamp the cursor's position to the valid range.
		clamped_pos := clamp(cursor_ptr.pos, start_pos, end_pos)

		// If a deletion range for this line already exists, update its start position to be the minimum.
		existing, ok := deletion_map[line]
		if ok {
			new_start := min(existing[0], clamped_pos)
			deletion_map[line] = [2]int{new_start, end_pos}
		} else {
			deletion_map[line] = [2]int{clamped_pos, end_pos}
		}
	}

	// Convert the deletion_map into a slice of ranges.
	ranges := make([dynamic][2]int, 0, len(deletion_map), context.temp_allocator)
	for _, r in deletion_map {
		// Only add if there is something to delete.
		if r[0] < r[1] {
			append(&ranges, r)
		}
	}
	if len(ranges) == 0 do return

	// Sort ranges by start position (ascending).
	slice.sort_by(ranges[:], proc(a, b: [2]int) -> bool {return a[0] < b[0]})

	// Process each deletion range in reverse order to avoid shifting issues.
	for i := len(ranges) - 1; i >= 0; i -= 1 {
		r := ranges[i]
		start_pos := r[0]
		end_pos := r[1]
		delete_count := end_pos - start_pos

		// Perform deletion: shift the data after end_pos to start_pos.
		old_len := len(buffer.data)
		copy(buffer.data[start_pos:], buffer.data[end_pos:])
		resize(&buffer.data, len(buffer.data) - delete_count)
		assert(len(buffer.data) == old_len - delete_count, "Buffer resize mismatch")

		// Adjust positions of all cursors.
		for cursor_ptr in cursors {
			if cursor_ptr.pos >= end_pos {
				cursor_ptr.pos -= delete_count
			} else if cursor_ptr.pos >= start_pos {
				cursor_ptr.pos = start_pos
			}
		}
	}

	// Update the buffer state from the earliest deletion.
	earliest_start := ranges[0][0]
	buffer_mark_dirty(buffer)
	buffer_update_line_starts(window, earliest_start)

	// Update all cursors' line and column values.
	update_cursor_lines_and_cols(buffer, cursors)
	update_cursors_from_temp_slice(window, cursors)
}

buffer_delete_selection :: proc(window: ^Window) {
    using window

    // Collect all cursors: main cursor and additional cursors
    all_cursors: [dynamic]^Cursor
    defer delete(all_cursors)
    append(&all_cursors, &cursor)
    for i in 0..<len(additional_cursors) {
        append(&all_cursors, &additional_cursors[i])
    }

    // Validate cursor positions
    for c in all_cursors {
        assert(c.sel >= 0 && c.sel <= len(buffer.data), "cursor.sel out of bounds")
        assert(c.pos >= 0 && c.pos <= len(buffer.data), "cursor.pos out of bounds")
    }

    // Collect selection ranges from all cursors
    ranges: [dynamic][2]int
    defer delete(ranges)
    for c in all_cursors {
        if c.sel != c.pos {
            start := min(c.sel, c.pos)
            end := max(c.sel, c.pos) + 1 // Half-open range includes max position
            append(&ranges, [2]int{start, end})
        }
    }

    // If no selections exist, exit early
    if len(ranges) == 0 do return

    // Merge overlapping or adjacent ranges
    slice.sort_by(ranges[:], proc(a, b: [2]int) -> bool { return a[0] < b[0] })
    merged: [dynamic][2]int
    defer delete(merged)
    append(&merged, ranges[0])
    for i in 1..<len(ranges) {
        current := ranges[i]
        last := &merged[len(merged)-1]
        if current[0] <= last[1] {
            last[1] = max(last[1], current[1])
        } else {
            append(&merged, current)
        }
    }

    // Track the earliest deletion point for line starts update
    earliest_start := merged[0][0]

    // Delete merged ranges from end to start to preserve earlier indices
    for i := len(merged)-1; i >= 0; i -= 1 {
        r := merged[i]
        start := r[0]
        end := r[1]
        assert(start <= end, "Selection start must be <= end")
        if end > len(buffer.data) do end = len(buffer.data)

        if end > start {
            delete_count := end - start
            old_len := len(buffer.data)
            copy(buffer.data[start:], buffer.data[end:])
            resize(&buffer.data, len(buffer.data) - delete_count)
            assert(len(buffer.data) == old_len - delete_count, "Buffer resize failed")

            // Adjust all cursor positions based on this deletion
            for c in all_cursors {
                if c.pos > end {
                    c.pos -= delete_count
                } else if c.pos >= start {
                    c.pos = start
                }
            }
        }
    }

    // Update buffer state
    buffer_mark_dirty(buffer)
    buffer_update_line_starts(window, earliest_start)

    // Reset selections for all cursors
    for c in all_cursors {
        c.sel = c.pos
        assert(c.sel == c.pos, "Selection not reset")
    }

    // Clamp cursor positions to buffer bounds
    for c in all_cursors {
        if c.pos > len(buffer.data) {
            c.pos = len(buffer.data)
        }
        assert(c.pos >= 0 && c.pos <= len(buffer.data), "Cursor position out of bounds")
    }

    // Validate line starts
    assert(len(buffer.line_starts) > 0, "Line starts must not be empty")
    assert(buffer.line_starts[0] == 0, "First line start must be 0")
}

buffer_delete_visual_line_selection :: proc(window: ^Window) {
	using window
	if cursor.sel == cursor.pos do return // No selection, nothing to delete.
	start_pos := min(cursor.sel, cursor.pos)
	end_pos := max(cursor.sel, cursor.pos)
	start_line := get_line_from_pos(buffer, start_pos)
	end_line := get_line_from_pos(buffer, end_pos)

	// Adjust to full line boundaries.
	delete_start := buffer.line_starts[start_line]
	delete_end :=
		end_line < len(buffer.line_starts) - 1 ? buffer.line_starts[end_line + 1] : len(buffer.data)

	if delete_end > delete_start {
		copy(buffer.data[delete_start:], buffer.data[delete_end:])
		resize(&buffer.data, len(buffer.data) - (delete_end - delete_start))
		cursor.pos = delete_start
		cursor.sel = cursor.pos
		buffer_mark_dirty(buffer)
		buffer_update_line_starts(window, delete_start)
		buffer_clamp_cursor_to_valid_range(window)
	}
}

buffer_delete_range :: proc(window: ^Window, start, end: int) {
	assert(
		start >= 0 && start <= end && end <= len(window.buffer.data),
		"Invalid range for deletion",
	)

	// Shift the remaining buffer content to remove the range.
	copy(window.buffer.data[start:], window.buffer.data[end:])

	// Resize the buffer to reflect the deletion
	resize(&window.buffer.data, len(window.buffer.data) - (end - start))

	buffer_mark_dirty(window.buffer)

	buffer_update_line_starts(window, start)
}

buffer_join_lines :: proc(window: ^Window) {
	using window

	if cursor.line >= len(buffer.line_starts) - 1 do return // No next line exists, do nothing

	current_line := cursor.line
	next_line := current_line + 1

	current_line_end := buffer.line_starts[next_line] - 1
	if current_line_end >= len(buffer.data) || buffer.data[current_line_end] != '\n' do return // No newline to remove

	// Remove the newline by shifting data
	next_line_start := buffer.line_starts[next_line]
	bytes_to_remove := next_line_start - current_line_end
	copy(buffer.data[current_line_end:], buffer.data[next_line_start:])
	resize(&buffer.data, len(buffer.data) - bytes_to_remove)

	join_pos := current_line_end
	content_start := join_pos
	for content_start < len(buffer.data) &&
	    is_whitespace_byte(buffer.data[content_start]) &&
	    buffer.data[content_start] != '\n' {
		content_start += 1
	}

	// Remove leading whitespace if any exists.
	if content_start > join_pos {
		remove_count := content_start - join_pos
		copy(buffer.data[join_pos:], buffer.data[content_start:])
		resize(&buffer.data, len(buffer.data) - remove_count)
	}

	// Insert a space at the join point.
	resize(&buffer.data, len(buffer.data) + 1)
	copy(buffer.data[join_pos + 1:], buffer.data[join_pos:])
	buffer.data[join_pos] = ' '

	// Update the line_starts array to reflect the new structure.
	buffer_update_line_starts(window, join_pos)
	buffer_mark_dirty(buffer)
}

buffer_rebuild_line_starts :: proc(window: ^Window) {
	using window
	clear(&buffer.line_starts)
	append(&buffer.line_starts, 0) // Start of first line.
	for i := 0; i < len(buffer.data); i += 1 {
		if buffer.data[i] == '\n' {
			append(&buffer.line_starts, i + 1)
		}
	}
}

// Updates the line_starts array starting from the line affected by an edit at edit_pos.
// Recalculates line_starts from edit_pos to the end of the buffer.
buffer_update_line_starts :: proc(window: ^Window, edit_pos: int) {
	using window

	// Clamp the edit position to the current buffer length.
	clamped_edit_pos := min(edit_pos, len(buffer.data))

	// Find the line containing the edit position (using binary search).
	low := 0
	high := len(buffer.line_starts) - 1
	start_line := 0

	for low <= high {
		mid := (low + high) / 2
		if buffer.line_starts[mid] <= clamped_edit_pos {
			start_line = mid
			low = mid + 1
		} else {
			high = mid - 1
		}
	}

	start_pos := buffer.line_starts[start_line]

	// Collect new line starts from start_pos to end of buffer.
	new_line_starts := make([dynamic]int, 0, 64, context.temp_allocator)
	append(&new_line_starts, start_pos)

	// SIMD setup: Process 16 bytes at a time (128-bit SIMD).
	newline := u8('\n')
	newline_array: [16]u8
	for j in 0 ..< 16 do newline_array[j] = newline
	newline_lane := simd.from_array(newline_array)

	// Get raw pointer to buffer data for direct SIMD loading.
	data_ptr := raw_data(buffer.data)

	i := start_pos
	for i + 16 <= len(buffer.data) {
		lane := simd.from_slice(simd.u8x16, buffer.data[i:i + 16])

		// Compare with newline character, getting a mask (0x00 or 0xff per byte).
		mask := simd.lanes_eq(lane, newline_lane)

		// Convert mask to a 128-bit integer for efficient bit processing.
		mask_u128 := transmute(u128)mask

		// Process all newline positions in the mask using bit manipulation.
		for mask_u128 != 0 {
			bit_pos := simd.count_trailing_zeros(mask_u128)
			byte_index := bit_pos / 8
			append_elem(&new_line_starts, i + int(byte_index) + 1)

			// Clear the bits for this byte (8 bits set per matching byte).
			mask_u128 &~= (0xff << (byte_index * 8))
		}

		i += 16
	}

	// Handle remaining bytes that don’t fit into a 16-byte chunk.
	for ; i < len(buffer.data); i += 1 {
		if buffer.data[i] == '\n' {
			append(&new_line_starts, i + 1)
		}
	}

	// Truncate the original line_starts and append new entries.
	if start_line + 1 <= len(buffer.line_starts) {
		resize(&buffer.line_starts, start_line + 1)
	}
	append(&buffer.line_starts, ..new_line_starts[1:])

	// Update cursor line and column.
	cursor.line = 0
	for j in 1 ..< len(buffer.line_starts) {
		if cursor.pos >= buffer.line_starts[j] {
			cursor.line = j
		} else {
			break
		}
	}
	cursor.col = cursor.pos - buffer.line_starts[cursor.line]
}

//
// Drawing
//

buffer_draw :: proc(
	p: ^Pulse,
	window: ^Window,
	font: Font,
	ctx: Draw_Context,
	allocator := context.allocator,
) {
	adjusted_ctx := ctx
	if window.scroll.y == 0 {
		adjusted_ctx.first_line = 0
	}

	buffer_draw_visible_lines(p, window, font, adjusted_ctx, allocator)
	cursor_draw(window, font, ctx)
}

buffer_draw_visible_lines :: proc(
    p: ^Pulse,
    window: ^Window,
    font: Font,
    ctx: Draw_Context,
    allocator := context.allocator,
) {
    using window
    assert(buffer.data != nil, "Buffer data must not be nil")
    assert(len(buffer.line_starts) > 0, "Buffer must have at least one line start")
    assert(ctx.first_line >= 0, "First line must be non-negative")
    assert(ctx.last_line >= ctx.first_line, "Last line must be >= first line")
    assert(ctx.last_line < len(buffer.line_starts), "Last line must be within buffer bounds")

    // Collect all selection ranges for .VISUAL mode
    selection_ranges := get_selection_ranges(window, allocator)
    defer delete(selection_ranges)
    selection_active := mode == .VISUAL && len(selection_ranges) > 0

    // Collect merged line ranges for .VISUAL_LINE mode
    visual_line_ranges: [dynamic][2]int
    if mode == .VISUAL_LINE {
        raw_ranges := get_visual_line_ranges(window, allocator)
        defer delete(raw_ranges)
        visual_line_ranges = merge_line_ranges(raw_ranges, allocator)
        defer delete(visual_line_ranges)
    }

    // Iterate over visible lines
    for line in ctx.first_line ..= ctx.last_line {
        line_start := buffer.line_starts[line]
        line_end := len(buffer.data)
        if line < len(buffer.line_starts) - 1 {
            next_line_start := buffer.line_starts[line + 1]
            if next_line_start > 0 && buffer.data[next_line_start - 1] == '\n' {
                line_end = next_line_start - 1
            } else {
                line_end = next_line_start
            }
        }
        assert(line_start >= 0 && line_start <= len(buffer.data), "Line start out of bounds")
        assert(line_end >= line_start && line_end <= len(buffer.data), "Line end out of bounds")

        line_text := string(buffer.data[line_start:line_end])
        line_str := strings.clone_to_cstring(line_text, allocator)
        defer delete(line_str, allocator)
        line_width := rl.MeasureTextEx(font.ray_font, line_str, f32(font.size), font.spacing).x

        // Highlight selections
        if selection_active {
            x_start := ctx.position.x
            y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)
            for sel_range in selection_ranges {
                sel_start := sel_range.start
                sel_end := sel_range.end
                if sel_start < line_end && sel_end > line_start {
                    start_pos := max(sel_start, line_start)
                    end_pos := min(sel_end, line_end)

                    // Measure text before selection
                    text_before := buffer.data[line_start:start_pos]
                    before_str := strings.clone_to_cstring(string(text_before), allocator)
                    defer delete(before_str, allocator)
                    x_offset := rl.MeasureTextEx(font.ray_font, before_str, f32(font.size), font.spacing).x

                    // Measure selected text width
                    text_selected := buffer.data[start_pos:end_pos]
                    selected_str := strings.clone_to_cstring(string(text_selected), allocator)
                    defer delete(selected_str, allocator)
                    sel_width := rl.MeasureTextEx(font.ray_font, selected_str, f32(font.size), font.spacing).x

                    // Handle empty selection within the line
                    if start_pos == end_pos {
                        sel_width = font.char_width // Minimum width for visibility
                    }

                    // Draw highlight
                    rl.DrawRectangleV(
                        {x_start + x_offset, y_pos},
                        {sel_width, f32(font.size)},
                        HIGHLIGHT_COLOR,
                    )
                }
            }
        } else if mode == .VISUAL_LINE && len(visual_line_ranges) > 0 {
            x_start := ctx.position.x
            y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)
            for range in visual_line_ranges {
                if line >= range[0] && line <= range[1] {
                    sel_width := line_width
                    if line_end == line_start {
                        sel_width = rl.MeasureTextEx(font.ray_font, " ", f32(font.size), font.spacing).x
                    }
                    rl.DrawRectangleV(
                        {x_start, y_pos},
                        {sel_width, f32(font.size)},
                        HIGHLIGHT_COLOR,
                    )
                    break // Move to next line after highlighting
                }
            }
        }

        // Draw the line text
        y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)
        rl.DrawTextEx(
            font.ray_font,
            line_str,
            rl.Vector2{ctx.position.x, y_pos},
            f32(font.size),
            font.spacing,
            font.color,
        )
    }
}

//
// Helpers
//

// Returns the length of a specified line.
buffer_line_length :: proc(buffer: ^Buffer, line: int) -> int {
	assert(line < len(buffer.line_starts), "Invalid line index")
	start := buffer.line_starts[line]
	end := len(buffer.data)

	if line < len(buffer.line_starts) - 1 {
		end = buffer.line_starts[line + 1]

		// NOTE: Subtract 1 to exclude the newline character.
		// Only considers visible characters.
		return end - start - 1
	}

	return end - start
}

// This function prevents the cursor from going out of bounds when the 
// underlying buffer changes (e.g. lines were inserted/deleted) and line_starts 
// was recalculated. If cursor.pos or cursor.line becomes invalid, we move them 
// just enough to bring them back in range.
buffer_clamp_cursor_to_valid_range :: proc(w: ^Window) {
	assert(w.buffer != nil, "Window has nil buffer pointer")
	assert(len(w.buffer.line_starts) > 0, "Buffer has no line starts when clamping cursor")
	assert(w.buffer.line_starts[0] == 0, "First line_start must always be 0")

	if w.cursor.line >= len(w.buffer.line_starts) {
		w.cursor.line = len(w.buffer.line_starts) - 1
	}
	if w.cursor.line < 0 { 	// Just in case.
		w.cursor.line = 0
	}

	// The new line_start in the updated buffer.
	line_start := w.buffer.line_starts[w.cursor.line]
	assert(
		line_start <= len(w.buffer.data),
		"line_start is out of range for the current buffer length",
	)

	// If the cursor’s pos is before line_start, clamp it up.
	if w.cursor.pos < line_start {
		w.cursor.pos = line_start
	}

	// Also clamp pos to end of buffer.
	if w.cursor.pos > len(w.buffer.data) {
		w.cursor.pos = len(w.buffer.data)
	}

	assert(w.cursor.pos >= line_start, "cursor.pos still < line_start after clamp")
	assert(w.cursor.pos <= len(w.buffer.data), "cursor.pos still > buffer length after clamp")
}

buffer_mark_dirty :: proc(buffer: ^Buffer) {
	buffer.dirty = true
	buffer.width_dirty = true
}

find_word_boundaries :: proc(buffer: ^Buffer, pos: int) -> (start: int, end: int) {
	assert(buffer != nil, "Invalid buffer")
	if pos < 0 || pos >= len(buffer.data) do return 0, 0

	current_rune, _ := utf8.decode_rune(buffer.data[pos:])
	is_whitespace := is_whitespace_rune(current_rune)

	if is_whitespace {
		// Select contiguous whitespace.
		start = pos
		for start > 0 {
			prev_pos := prev_rune_start(buffer.data[:], start)
			r, _ := utf8.decode_rune(buffer.data[prev_pos:])
			if !is_whitespace_rune(r) do break
			start = prev_pos
		}
		end = pos
		for end < len(buffer.data) {
			r, n := utf8.decode_rune(buffer.data[end:])
			if n == 0 || !is_whitespace_rune(r) do break
			end += n
		}
	} else {
		// Select the word.
		is_word := is_word_character(current_rune)
		start = pos
		for start > 0 {
			prev_pos := prev_rune_start(buffer.data[:], start)
			r, _ := utf8.decode_rune(buffer.data[prev_pos:])
			if is_word_character(r) != is_word do break
			start = prev_pos
		}
		end = pos
		for end < len(buffer.data) {
			r, n := utf8.decode_rune(buffer.data[end:])
			if n == 0 || is_word_character(r) != is_word do break
			end += n
		}
	}

	return start, end
}

// Finds the start of the next word based on word_type
buffer_find_next_word_start :: proc(
	buffer: ^Buffer,
	pos: int,
	word_type: Word_Type,
) -> (
	int,
	bool,
) {
	assert(pos >= 0 && pos <= len(buffer.data), "pos out of range")
	if pos >= len(buffer.data) do return pos, false

	char_index := pos
	total_bytes := len(buffer.data)

	// Get current character and its class.
	c, n := utf8.decode_rune(buffer.data[char_index:])
	assert(n > 0, "Invalid UTF-8 sequence at initial pos")
	if n == 0 do return char_index, false
	current_class := get_char_class(c, word_type)

	// Skip characters of the same class.
	for char_index < total_bytes {
		r, n := utf8.decode_rune(buffer.data[char_index:])
		if n == 0 do break
		class := get_char_class(r, word_type)
		if class != current_class do break
		char_index += n
	}

	// Skip over whitespace.
	for char_index < total_bytes {
		r, n := utf8.decode_rune(buffer.data[char_index:])
		if n == 0 do break
		if get_char_class(r, word_type) != .WHITESPACE do break
		char_index += n
	}

	if char_index >= total_bytes do return total_bytes, false
	return char_index, true
}

// Finds the start of the previous word based on word_type.
buffer_find_previous_word_start :: proc(
	buffer: ^Buffer,
	pos: int,
	word_type: Word_Type,
) -> (
	int,
	bool,
) {
	assert(pos >= 0 && pos <= len(buffer.data), "pos out of range")
	if pos <= 0 do return 0, false

	char_index := pos

	// Move back one rune to examine the previous character.
	char_index = prev_rune_start(buffer.data[:], char_index)
	assert(char_index >= 0, "char_index out of bounds after moving back")

	// Skip trailing whitespace.
	for char_index > 0 {
		r, n := utf8.decode_rune(buffer.data[char_index:])
		if n == 0 do break
		if get_char_class(r, word_type) != .WHITESPACE do break
		char_index = prev_rune_start(buffer.data[:], char_index)
	}

	if char_index == 0 {
		r, _ := utf8.decode_rune(buffer.data[char_index:])
		if get_char_class(r, word_type) == .WHITESPACE do return 0, false
		return 0, true
	}

	// Get the class of the character at the new position.
	r, _ := utf8.decode_rune(buffer.data[char_index:])
	current_class := get_char_class(r, word_type)

	// Move back to the start of this word (stop when class changes or whitespace is hit).
	start_pos := char_index
	for char_index > 0 {
		prev_pos := prev_rune_start(buffer.data[:], char_index)
		r, _ := utf8.decode_rune(buffer.data[prev_pos:])
		next_class := get_char_class(r, word_type)
		if next_class != current_class || next_class == .WHITESPACE {
			break
		}
		start_pos = prev_pos
		char_index = prev_pos
	}

	return start_pos, true
}

// Finds the end of the next word based on word_type.
buffer_find_next_word_end :: proc(buffer: ^Buffer, pos: int, word_type: Word_Type) -> (int, bool) {
	assert(pos >= 0 && pos <= len(buffer.data), "pos out of range")
	if pos >= len(buffer.data) do return pos, false

	char_index := pos
	total_bytes := len(buffer.data)

	// Move forward one character if possible.
	if char_index + 1 < total_bytes {
		char_index += next_rune_length(buffer.data[:], char_index)
		assert(char_index <= total_bytes, "char_index out of bounds after moving forward")
	} else {
		return char_index, false
	}

	// Skip whitespace.
	for char_index < total_bytes {
		r, n := utf8.decode_rune(buffer.data[char_index:])
		if n == 0 do break
		if get_char_class(r, word_type) != .WHITESPACE do break
		char_index += n
	}

	if char_index >= total_bytes do return total_bytes - 1, false

	// Get the class of the current character.
	r, _ := utf8.decode_rune(buffer.data[char_index:])
	current_class := get_char_class(r, word_type)

	last_char_index := char_index

	// Move to the end of the current class sequence.
	for char_index < total_bytes {
		r, n := utf8.decode_rune(buffer.data[char_index:])
		if n == 0 do break
		if get_char_class(r, word_type) != current_class do break
		last_char_index = char_index
		char_index += n
	}

	return last_char_index, true
}

buffer_update_cursor_line_col :: proc(window: ^Window) {
	using window
	pos := window.cursor.pos
	line := 0
	col := 0
	current_pos := 0

	// Lopp through the buffer up to the cursor's position.
	for current_pos < pos && current_pos < len(buffer.data) {
		r, n := utf8.decode_rune(buffer.data[current_pos:])
		if r == '\n' {
			line += 1
			col = 0
		} else do col += 1
		current_pos += n
	}

	window.cursor.line = line
	window.cursor.col = col
}

// Updates the indentation of the current line based on the previous line's indentation
// and content, typically called after editing operations that affect line structure.
buffer_update_indentation :: proc(window: ^Window, allocator := context.allocator) {
	using window

	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors)

	for cursor_ptr in cursors {
		if cursor_ptr.line <= 0 do return
		assert(cursor_ptr.line <= len(buffer.line_starts), "Current line must be valid")

		// Get the previous line.
		prev_line := cursor_ptr.line - 1
		assert(
			prev_line >= 0 && prev_line < len(buffer.line_starts),
			"Previous line index must be valid",
		)
		line_start := buffer.line_starts[prev_line]
		line_end :=
			buffer.line_starts[prev_line + 1] - 1 if prev_line + 1 < len(buffer.line_starts) else len(buffer.data)

		// Calculate base indentation from the previous line.
		indent_end := line_start
		for indent_end < line_end && buffer.data[indent_end] == ' ' {
			indent_end += 1
		}
		assert(
			indent_end >= line_start && indent_end <= line_end,
			"Indentation end must be within previous line boundaries",
		)
		base_indent := indent_end - line_start

		// Check if the previous line ends with an opening delimiter.
		extra_indent := 0
		if line_end > line_start {
			last_char := buffer.data[line_end - 1]
			if last_char == '{' || last_char == '(' || last_char == '[' {
				extra_indent = tab_width
			}
		}

		// Calculate total desired indentation.
		total_indent := base_indent + extra_indent
		assert(total_indent >= 0, "Total indentation must be non-negative")

		// Get the current line's start position.
		current_line_start := buffer.line_starts[cursor_ptr.line]
		current_indent_end := current_line_start
		for current_indent_end < len(buffer.data) && buffer.data[current_indent_end] == ' ' {
			current_indent_end += 1
		}
		assert(
			current_indent_end >= current_line_start && current_indent_end <= len(buffer.data),
			"Current indentation end must be within buffer bounds",
		)
		current_indent := current_indent_end - current_line_start

		// Adjust current line's indentation if necessary.
		if current_indent != total_indent {
			delta := 0

			// Remove existing indentation.
			if current_indent > 0 {
				copy(buffer.data[current_line_start:], buffer.data[current_indent_end:])
				old_len := len(buffer.data)
				resize(&buffer.data, len(buffer.data) - current_indent)
				assert(
					len(buffer.data) == old_len - current_indent,
					"Buffer resize after removing indentation failed",
				)
				cursor_ptr.pos -= current_indent
				delta -= current_indent
			}

			// Insert new indentation.
			if total_indent > 0 {
				indent_str := strings.repeat(" ", total_indent, allocator)
				defer delete(indent_str, allocator)
				text_bytes := transmute([]u8)indent_str
				old_len := len(buffer.data)
				resize(&buffer.data, len(buffer.data) + total_indent)
				assert(
					len(buffer.data) == old_len + total_indent,
					"Buffer resize after inserting indentation failed",
				)
				copy(
					buffer.data[current_line_start + total_indent:],
					buffer.data[current_line_start:],
				)
				copy(buffer.data[current_line_start:], text_bytes)
				cursor_ptr.pos += total_indent
				delta += total_indent
			}

			// Adjust other cursors based on net change in buffer size.
			if delta != 0 {
				adjust_cursors(cursors, cursor_ptr, current_line_start, delta > 0, abs(delta))
			}

			buffer_mark_dirty(buffer)
			buffer_update_line_starts(window, current_line_start)
		}

		assert(
			cursor_ptr.pos >= 0 && cursor_ptr.pos <= len(buffer.data),
			"cursor_ptr position must be within buffer bounds after adjustment",
		)
	}
	update_cursor_lines_and_cols(buffer, cursors)
	update_cursors_from_temp_slice(window, cursors)
}

get_char_class :: proc(r: rune, word_type: Word_Type) -> Char_Class {
	switch word_type {
	case .WORD:
		if is_whitespace_rune(r) do return .WHITESPACE
		else if is_word_character(r) do return .WORD
		else do return .PUNCTUATION
	case .BIG_WORD:
		if is_whitespace_rune(r) do return .WHITESPACE
		else do return .WORD // Everything non-whitespace is a word.
	}
	return .WHITESPACE // Default case, should not occur.
}

get_line_from_pos :: proc(buffer: ^Buffer, pos: int) -> int {
	for line in 0 ..< len(buffer.line_starts) {
		if pos < buffer.line_starts[line] {
			return line - 1
		}
	}
	return len(buffer.line_starts) - 1
}

get_selection_ranges :: proc(window: ^Window, allocator := context.allocator) -> [dynamic]Selection_Range {
	ranges := make([dynamic]Selection_Range, 0, len(window.additional_cursors) + 1, allocator)
	if window.mode == .VISUAL {
		if window.cursor.sel != window.cursor.pos {
			start := min(window.cursor.sel, window.cursor.pos)
			end := max(window.cursor.sel, window.cursor.pos) + 1
			append(&ranges, Selection_Range{start, end})
		}

		// Additional cursors.
		for &c in window.additional_cursors {
			if c.sel != c.pos {
				start := min(c.sel, c.pos)
				end := max(c.sel, c.pos) + 1
				append(&ranges, Selection_Range{start, end})
			}
		}
	}

	return ranges
}

// Collects the line ranges selected by all cursors in .VISUAL_LINE mode
get_visual_line_ranges :: proc(window: ^Window, allocator := context.allocator) -> [dynamic][2]int {
    ranges := make([dynamic][2]int, 0, len(window.additional_cursors) + 1, allocator)
    if window.mode == .VISUAL_LINE {
        // Main cursor
        if window.cursor.sel != window.cursor.pos {
            sel_line := get_line_from_pos(window.buffer, window.cursor.sel)
            pos_line := get_line_from_pos(window.buffer, window.cursor.pos)
            min_line := min(sel_line, pos_line)
            max_line := max(sel_line, pos_line)
            append(&ranges, [2]int{min_line, max_line})
        }
        // Additional cursors
        for &c in window.additional_cursors {
            if c.sel != c.pos {
                sel_line := get_line_from_pos(window.buffer, c.sel)
                pos_line := get_line_from_pos(window.buffer, c.pos)
                min_line := min(sel_line, pos_line)
                max_line := max(sel_line, pos_line)
                append(&ranges, [2]int{min_line, max_line})
            }
        }
    }
    return ranges
}

merge_line_ranges :: proc(ranges: [dynamic][2]int, allocator := context.allocator) -> [dynamic][2]int {
    if len(ranges) == 0 do return make([dynamic][2]int, 0, 0, allocator)
    
    sorted_ranges := slice.clone(ranges[:], allocator)
    slice.sort_by(sorted_ranges, proc(a, b: [2]int) -> bool { return a[0] < b[0] })
    merged := make([dynamic][2]int, 0, len(sorted_ranges), allocator)
    current := sorted_ranges[0]
    for i in 1..<len(sorted_ranges) {
        if sorted_ranges[i][0] <= current[1] + 1 { // Overlapping or adjacent.
            current[1] = max(current[1], sorted_ranges[i][1])
        } else {
            append(&merged, current)
            current = sorted_ranges[i]
        }
    }
    append(&merged, current)
    return merged
}
