package engine

import "base:intrinsics"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:simd"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

// Buffer stores text as an array of bytes.
// TODO: Refactor this to use a rope?
Buffer :: struct {
	data:           [dynamic]u8, // Dynamic array of bytes that contains text.
	line_starts:    [dynamic]int, // Indexes of the beginning of each line in the array byte.
	dirty:          bool, // If the buffer has been modified.
	is_cli:         bool,
	max_line_width: f32, // Maximum width of any line in the buffer.
	width_dirty:    bool, // Indicates if max_line_width needs recalculation.
}

Cursor :: struct {
	pos:           int, // Position in the array of bytes.
	sel:           int,
	line:          int, // Current line number.
	col:           int, // Current column (character index) in the line.
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
	offset := cursor.pos
	assert(offset >= 0, "Cursor offset must be greater or equal to 0")
	assert(!(offset > len(buffer.data)), "Cursor cannot be bigger than the length of the buffer")

	text_bytes := transmute([]u8)text

	assert(len(buffer.data) >= 0, "Buffer length corrupted")
	assert(cursor.pos <= len(buffer.data), "Cursor position out of bounds")

	// Make space for new text.
	resize(&buffer.data, len(buffer.data) + len(text_bytes))

	// Move existing text to make room.
	if (len(buffer.data) - len(text_bytes)) > offset {
		copy(buffer.data[offset + len(text_bytes):], buffer.data[offset:])
	}

	// Insert new text.
	copy(buffer.data[offset:], text_bytes)
	cursor.pos += len(text_bytes)
	buffer_mark_dirty(buffer)

	buffer_update_line_starts(window, offset)
}

buffer_insert_char :: proc(window: ^Window, char: rune) {
	using window
	assert(utf8.valid_rune(char), "Invalid UTF-8 rune inserted")
	if !is_char_supported(char) do return
	old_len := len(buffer.data)

	offset := cursor.pos
	assert(offset >= 0, "Cursor offset must be greater or equal to 0")
	assert(!(offset > len(buffer.data)), "Cursor cannot be bigger than the length of the buffer")

	// Encode rune into UTF-8.
	encoded, n_bytes := utf8.encode_rune(char)

	assert(len(buffer.data) >= 0, "Buffer length corrupted")
	assert(cursor.pos <= len(buffer.data), "Cursor position out of bounds")

	// Make space for new character.
	resize(&buffer.data, len(buffer.data) + n_bytes)

	// Move existing text to make room.
	if offset < len(buffer.data) - n_bytes {
		copy(buffer.data[offset + n_bytes:], buffer.data[offset:])
	}

	// Insert new character.
	copy(buffer.data[offset:], encoded[0:n_bytes])
	cursor.pos += n_bytes
	buffer_mark_dirty(buffer)
	assert(len(buffer.data) >= old_len + n_bytes, "Insertion failed to grow buffer")

	buffer_update_line_starts(window, offset)
}

buffer_delete_char :: proc(window: ^Window) {
	using window
	assert(len(buffer.data) >= 0, "Delete called on invalid buffer")
	old_len := len(buffer.data)

	if cursor.pos <= 0 do return // NOTE: Stop deleting after the position is 0.

	start_index := prev_rune_start(buffer.data[:], cursor.pos)
	n_bytes := cursor.pos - start_index // Number of bytes in the rune.

	// Remove the rune's bytes.
	copy(buffer.data[start_index:], buffer.data[cursor.pos:])
	resize(&buffer.data, len(buffer.data) - n_bytes)

	cursor.pos = start_index
	buffer_mark_dirty(buffer)
	assert(len(buffer.data) == old_len - n_bytes, "Deletion size mismatched")

	buffer_update_line_starts(window, start_index)
}

buffer_delete_forward_char :: proc(window: ^Window) {
	using window
	if cursor.pos >= len(buffer.data) do return

	n_bytes := next_rune_length(buffer.data[:], cursor.pos)
	if n_bytes == 0 do return

	// Delete the rune's bytes by shifting data to the left like a real chad.
	copy(buffer.data[cursor.pos:], buffer.data[cursor.pos + n_bytes:])
	resize(&buffer.data, len(buffer.data) - n_bytes)

	buffer_mark_dirty(buffer)
	buffer_update_line_starts(window, cursor.pos)
}

buffer_delete_word :: proc(window: ^Window) {
	using window
	if cursor.pos <= 0 do return

	original_pos := cursor.pos
	start_pos := original_pos

	// Move to word start.
	cursor.pos = prev_rune_start(buffer.data[:], cursor.pos)

	// Skip whitespace backwards.
	for cursor.pos > 0 && is_whitespace_byte(buffer.data[cursor.pos]) {
		cursor.pos = prev_rune_start(buffer.data[:], cursor.pos)
	}

	// Move through word character.
	if cursor.pos > 0 {
		current_rune, _ := utf8.decode_rune(buffer.data[cursor.pos:])
		is_word := is_word_character(current_rune)

		for cursor.pos > 0 {
			prev_pos := prev_rune_start(buffer.data[:], cursor.pos)
			r, _ := utf8.decode_rune(buffer.data[prev_pos:])

			if is_whitespace_byte(buffer.data[prev_pos]) || is_word_character(r) != is_word do break

			cursor.pos = prev_pos
		}
	}

	// Bytes do delete.
	delete_start := cursor.pos
	delete_size := original_pos - delete_start

	// Actually delete something...
	copy(buffer.data[delete_start:], buffer.data[original_pos:])
	resize(&buffer.data, len(buffer.data) - delete_size)
	cursor.pos = delete_start
	buffer_mark_dirty(buffer)
	buffer_update_line_starts(window, delete_start)
}

// FIX: While at last line, should just delete the line and move up.
buffer_delete_line :: proc(window: ^Window) {
	using window
	if len(buffer.line_starts) == 0 do return // // Buffer empty, nothing to delete.

	current_line := cursor.line
	if current_line >= len(buffer.line_starts) {
		current_line = len(buffer.line_starts) - 1 // Clamp to valid line.
	}
	assert(
		current_line >= 0 && current_line < len(buffer.line_starts),
		"Current line index out of bounds",
	)

	start_pos := buffer.line_starts[current_line]
	end_pos := len(buffer.data)
	if current_line < len(buffer.line_starts) - 1 {
		end_pos = buffer.line_starts[current_line + 1] // Include newline.
	} else if current_line > 0 && current_line == len(buffer.line_starts) - 1 {
		// Last line: include the preceding newline if it exists.
		start_pos = buffer.line_starts[current_line] - 1
		assert(buffer.data[start_pos] == '\n', "Expected newline before last line")
	}

	// Assert deletion range validity.
	assert(start_pos >= 0 && start_pos <= len(buffer.data), "start_pos out of buffer bounds")
	assert(
		end_pos >= start_pos && end_pos <= len(buffer.data),
		"end_pos invalid relative to start_pos or buffer",
	)

	old_len := len(buffer.data)
	copy(buffer.data[start_pos:], buffer.data[end_pos:])
	resize(&buffer.data, len(buffer.data) - (end_pos - start_pos))
	buffer_mark_dirty(buffer)
	buffer_update_line_starts(window, start_pos)

	assert(
		len(buffer.data) == old_len - (end_pos - start_pos),
		"Buffer length mismatch after deletion",
	)

	// Adjust cursor position.
	if len(buffer.line_starts) == 0 {
		cursor.line = 0
		cursor.pos = 0
		cursor.col = 0
	} else if current_line < len(buffer.line_starts) {
		cursor.line = current_line
		cursor.pos = buffer.line_starts[current_line]
		cursor.col = 0
	} else {
		cursor.line = len(buffer.line_starts) - 1
		cursor.pos = buffer.line_starts[len(buffer.line_starts) - 1]
		cursor.col = 0
	}

	// Post-deletion cursor assertions.
	assert(cursor.line >= 0 && cursor.line < len(buffer.line_starts), "Cursor line out of bounds")
	assert(
		cursor.pos >= 0 && cursor.pos <= len(buffer.data),
		"Cursor position out of buffer bounds",
	)
	assert(
		cursor.pos == buffer.line_starts[cursor.line],
		"Cursor position does not match line start",
	)
}

// Works just like buffer_delete_line, but without cursor position adjustments
buffer_change_line :: proc(window: ^Window) {
	using window
	current_line := cursor.line
	if len(buffer.line_starts) == 0 do return // // Buffer empty, nothing to delete.

	assert(
		current_line >= 0 && current_line < len(buffer.line_starts),
		"Current line out of bounds",
	)

	start_pos := buffer.line_starts[current_line]
	assert(start_pos >= 0 && start_pos <= len(buffer.data), "start_pos out of bounds")

	end_pos := len(buffer.data)
	if current_line < len(buffer.line_starts) - 1 {
		end_pos = buffer.line_starts[current_line + 1] - 1 // Exclude newline.
	}
	assert(end_pos >= start_pos && end_pos <= len(buffer.data), "end_pos invalid")

	// Delete line content.
	old_len := len(buffer.data)
	copy(buffer.data[start_pos:], buffer.data[end_pos:])
	resize(&buffer.data, len(buffer.data) - (end_pos - start_pos))
	assert(len(buffer.data) == old_len - (end_pos - start_pos), "Buffer resize mismatch")

	buffer_mark_dirty(buffer)
	buffer_update_line_starts(window, start_pos)

	// Verify line_starts integrity.
	assert(len(buffer.line_starts) > 0, "Line starts should not be empty after update")
	assert(buffer.line_starts[0] == 0, "First line start should be 0")

	cursor.pos = buffer.line_starts[current_line]
	cursor.col = 0
	assert(cursor.pos == buffer.line_starts[current_line], "Cursor position mismatch")
	assert(cursor.col == 0, "Cursor column not reset")
}

buffer_delete_to_line_end :: proc(window: ^Window) {
	using window
	current_line := cursor.line
	if current_line >= len(buffer.line_starts) do return

	// Get line boundaries.
	start_pos := buffer.line_starts[current_line]
	end_pos := len(buffer.data) // Default to buffer end for last line.

	// Adjust end_pos for non-last lines (exclude newline).
	if current_line < len(buffer.line_starts) - 1 {
		end_pos = buffer.line_starts[current_line + 1] - 1
	}

	// Clamp cursor position to valid range.
	cursor_pos := clamp(cursor.pos, start_pos, end_pos)

	// Calculate bytes to delete.
	delete_count := end_pos - cursor_pos
	if delete_count <= 0 do return

	// Actually perform the damn deletion.
	copy(buffer.data[cursor_pos:], buffer.data[end_pos:])
	resize(&buffer.data, len(buffer.data) - delete_count)
	cursor.pos = cursor_pos
	buffer_mark_dirty(buffer)
	buffer_update_line_starts(window, cursor_pos)
}

buffer_delete_selection :: proc(window: ^Window) {
	using window
	assert(cursor.sel >= 0 && cursor.sel <= len(buffer.data), "cursor.sel out of bounds")
	assert(cursor.pos >= 0 && cursor.pos <= len(buffer.data), "cursor.pos out of bounds")

	if cursor.sel == cursor.pos do return // No selection, nothing to delete.

	start := min(cursor.sel, cursor.pos)
	end := max(cursor.sel, cursor.pos) + 1 // Include the character at max position.

	assert(start <= end, "Selection start must be <= end")

	if end > start {
		if end > len(buffer.data) do end = len(buffer.data)
		assert(end <= len(buffer.data), "end clamped incorrectly")

		old_len := len(buffer.data)
		copy(buffer.data[start:], buffer.data[end:])
		resize(&buffer.data, len(buffer.data) - (end - start))
		assert(len(buffer.data) == old_len - (end - start), "Buffer resize failed")

		cursor.pos = start
		buffer_mark_dirty(buffer)
		buffer_update_line_starts(window, start)

		assert(cursor.pos >= 0 && cursor.pos <= len(buffer.data), "Cursor position out of bounds")
		assert(len(buffer.line_starts) > 0, "Line starts must not be empty")
		assert(buffer.line_starts[0] == 0, "First line start must be 0")
	}

	cursor.sel = cursor.pos
	assert(cursor.sel == cursor.pos, "Selection not reset")
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

buffer_rebuild_line_starts :: proc(window: ^Window) {
	using window
	clear(&buffer.line_starts)
	append(&buffer.line_starts, 0) // Start of first line.
	for i := 0; i < len(buffer.data); i += 1 {
		if buffer.data[i] == '\n' {
			append(&buffer.line_starts, i + 1)
		}
	}

	// Update cursor line and column.
	cursor.line = 0
	for i := 1; i < len(buffer.line_starts); i += 1 {
		if cursor.pos >= buffer.line_starts[i] {
			cursor.line = i
		} else {
			break
		}
	}
	cursor.col = cursor.pos - buffer.line_starts[cursor.line]
}

//
// Movement
//

// NOTE: This function will probably stay being this megazord forever, and I don't care.
buffer_move_cursor :: proc(window: ^Window, movement: Cursor_Movement) {
	using window
	current_line_start := buffer.line_starts[cursor.line]
	current_line_end := len(buffer.data)

	// Calculate line end position.
	if cursor.line < len(buffer.line_starts) - 1 {
		current_line_end = buffer.line_starts[cursor.line + 1] - 1
	}

	horizontal: bool

	switch movement {

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
		current_line_length := buffer_line_length(buffer, current_line)

		// Handle CLI buffers differently.
		if buffer.is_cli {
			cursor.pos = len(buffer.data)
			horizontal = true
			break
		}

		// Handle empty lines differently.
		if current_line_length == 0 {
			cursor.pos = current_line_start
		} else {
			if current_line < len(buffer.line_starts) - 1 {
				line_end_pos := buffer.line_starts[current_line + 1] - 1
				// Only adjust if we have a newline character.
				if line_end_pos >= 0 && buffer.data[line_end_pos] == '\n' {
					cursor.pos = line_end_pos - 1
				} else {
					cursor.pos = line_end_pos
				}
			} else {
				cursor.pos = len(buffer.data)
			}
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

	// Update preferred col after horizontal movements.
	if horizontal {
		cursor.preferred_col = cursor.col
	}
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
	buffer_draw_cursor(window, font, ctx)
}

buffer_draw_cursor :: proc(window: ^Window, font: Font, ctx: Draw_Context) {
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

	line_text := buffer.data[line_start:cursor_pos_clamped]
	assert(len(line_text) >= 0, "Line text cannot be negative")

	temp_text := make([dynamic]u8, len(line_text) + 1)
	defer delete(temp_text)

	copy(temp_text[:], line_text)
	temp_text[len(line_text)] = 0
	cursor_pos.x +=
		rl.MeasureTextEx(font.ray_font, cstring(&temp_text[0]), f32(font.size), font.spacing).x

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
				{cursor.color.r, cursor.color.g, cursor.color.b, 80}, // Slightly transparent.
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
}

buffer_draw_visible_lines :: proc(
	p: ^Pulse,
	window: ^Window,
	font: Font,
	ctx: Draw_Context,
	allocator := context.allocator,
) {
	using window
	// Assert buffer integrity.
	assert(buffer.data != nil, "Buffer data must not be nil")
	assert(len(buffer.line_starts) > 0, "Buffer must have at least one line start")

	// Assert drawing context.
	assert(ctx.first_line >= 0, "First line must be non-negative")
	assert(ctx.last_line >= ctx.first_line, "Last line must be >= first line")
	assert(ctx.last_line < len(buffer.line_starts), "Last line must be within buffer bounds")

	selection_active := window.mode == .VISUAL && cursor.sel != cursor.pos
	max_val := max(cursor.sel, cursor.pos)
	sel_start := min(cursor.sel, cursor.pos) if selection_active else 0
	sel_end := max_val + (max_val < len(buffer.data) ? 1 : 0) // Only add 1 if max is within buffer.
	sel_end = min(sel_end, len(buffer.data))

	// Validate selection indices when active.
	if selection_active {
		assert(sel_start >= 0 && sel_start <= len(buffer.data), "Selection start out of bounds")
		assert(sel_end <= len(buffer.data), "Selection end out of bounds")
		assert(sel_start <= sel_end, "Selection start must be <= end")
	}

	// Handle non-last lines.
	for line in ctx.first_line ..= ctx.last_line {
		line_start := buffer.line_starts[line]
		line_end := len(buffer.data)

		if line < len(buffer.line_starts) - 1 {
			next_line_start := buffer.line_starts[line + 1]
			if next_line_start > 0 && buffer.data[next_line_start - 1] == '\n' {
				line_end = next_line_start - 1 // Exclude newline from text drawing.
			} else {
				line_end = next_line_start
			}
		}

		// Validate line bounds.
		assert(line_start >= 0 && line_start <= len(buffer.data), "Line start out of bounds")
		assert(line_end >= line_start && line_end <= len(buffer.data), "Line end out of bounds")

		// Calculate line width for text positioning.
		line_text_for_measure := string(buffer.data[line_start:line_end])
		line_str_for_measure := strings.clone_to_cstring(line_text_for_measure, allocator)
		defer delete(line_str_for_measure, allocator)
		line_width :=
			rl.MeasureTextEx(font.ray_font, line_str_for_measure, f32(font.size), font.spacing).x

		// Highlight selection if it overlaps this line.
		if selection_active && sel_start < line_end && sel_end > line_start {
			start_pos := max(sel_start, line_start)
			end_pos := min(sel_end, line_end)

			x_start := ctx.position.x
			y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)

			// Measure text before selection.
			text_before := buffer.data[line_start:start_pos]
			before_str := strings.clone_to_cstring(string(text_before), allocator)
			defer delete(before_str, allocator)
			x_offset := rl.MeasureTextEx(font.ray_font, before_str, f32(font.size), font.spacing).x

			// Measure selected text width.
			text_selected := buffer.data[start_pos:end_pos]
			selected_str := strings.clone_to_cstring(string(text_selected), allocator)
			defer delete(selected_str, allocator)
			sel_width :=
				rl.MeasureTextEx(font.ray_font, selected_str, f32(font.size), font.spacing).x
			highlighted_line := f32(font.size) + (font.spacing * 0.9)

			// Draw highlight for selected text.
			rl.DrawRectangleV(
				{x_start + x_offset, y_pos},
				{sel_width, f32(font.size)}, // Use font.size for consistent height.
				HIGHLIGHT_COLOR,
			)

			// Extend highlight to end of line if selection includes newline.
			is_empty_line := line_end - line_start == 0 // Check if line has no visible characters.
			if line < len(buffer.line_starts) - 1 && sel_end > line_end && is_empty_line {
				space_width := rl.MeasureTextEx(font.ray_font, " ", f32(font.size), font.spacing).x
				rl.DrawRectangleV(
					{x_start + line_width, y_pos},
					{space_width, highlighted_line}, // Match text height.
					HIGHLIGHT_COLOR,
				)
			}
		}

		// Draw the line text.
		y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)
		line_text := buffer.data[line_start:line_end]
		line_str := strings.clone_to_cstring(string(line_text), allocator)
		defer delete(line_str, allocator)

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

