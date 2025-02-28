package engine

import "core:mem"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

// Buffer stores text as an array of bytes.
// TODO: Refactor this to use a rope?
Buffer :: struct {
	data:        [dynamic]u8, // Dynamic array of bytes that contains text.
	line_starts: [dynamic]int, // Indexes of the beginning of each line in the array byte.
	dirty:       bool, // If the buffer has been modified.
	cursor:      Cursor,
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
	FIRST_NON_BLANK,
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

// Creates a new buffer with a given initial capacity.
buffer_init :: proc(allocator := context.allocator, initial_cap := 1024) -> Buffer {
	return Buffer {
		data = make([dynamic]u8, 0, initial_cap, allocator),
		line_starts = make([dynamic]int, 1, 64, allocator),
		dirty = false,
		cursor = Cursor {
			pos           = 0,
			sel           = 0,
			line          = 0,
			col           = 0,
			preferred_col = -1,
			style         = .BLOCK,
			color         = rl.GRAY,
			blink         = false, // FIX: This shit.
		},
	}
}

// NOTE: This is a bit useless if we're using an arena.
buffer_free :: proc(buffer: ^Buffer) {
	delete(buffer.data)
	delete(buffer.line_starts)
}

buffer_load_file :: proc(
	buffer: ^Buffer,
	filename: string,
	allocator := context.allocator,
) -> bool {
	data, ok := os.read_entire_file(filename, allocator)
	if !ok do return false

	// Replace buffer contents.
	clear(&buffer.data)
	append(&buffer.data, ..data)

	buffer.cursor.pos = 0
	buffer.dirty = false
	buffer_update_line_starts(buffer)

	return true
}

//
// Editing
//

buffer_insert_text :: proc(buffer: ^Buffer, text: string) {
	assert(len(text) != 0, "The length of the text should not be 0")
	offset := buffer.cursor.pos
	assert(offset >= 0, "Cursor offset must be greater or equal to 0")
	assert(!(offset > len(buffer.data)), "Cursor cannot be bigger than the length of the buffer")

	text_bytes := transmute([]u8)text

	// Make space for new text.
	resize(&buffer.data, len(buffer.data) + len(text_bytes))

	// Move existing text to make room.
	if (len(buffer.data) - len(text_bytes)) > offset {
		copy(buffer.data[offset + len(text_bytes):], buffer.data[offset:])
	}

	// Insert new text.
	copy(buffer.data[offset:], text_bytes)
	buffer.cursor.pos += len(text_bytes)
	buffer.dirty = true
	buffer_update_line_starts(buffer)
}

buffer_insert_char :: proc(buffer: ^Buffer, char: rune) {
	if !is_char_supported(char) do return
	offset := buffer.cursor.pos
	assert(offset >= 0, "Cursor offset must be greater or equal to 0")
	assert(!(offset > len(buffer.data)), "Cursor cannot be bigger than the length of the buffer")

	// Encode rune into UTF-8.
	encoded, n_bytes := utf8.encode_rune(char)

	// Make space for new character.
	resize(&buffer.data, len(buffer.data) + n_bytes)

	// Move existing text to make room.
	if offset < len(buffer.data) - n_bytes {
		copy(buffer.data[offset + n_bytes:], buffer.data[offset:])
	}

	// Insert new character.
	copy(buffer.data[offset:], encoded[0:n_bytes])
	buffer.cursor.pos += n_bytes
	buffer.dirty = true
	buffer_update_line_starts(buffer)
}

buffer_delete_char :: proc(buffer: ^Buffer) {
	if buffer.cursor.pos <= 0 do return // NOTE: Stop deleting after the position is 0.

	start_index := prev_rune_start(buffer.data[:], buffer.cursor.pos)
	n_bytes := buffer.cursor.pos - start_index // Number of bytes in the rune.

	// Remove the rune's bytes.
	copy(buffer.data[start_index:], buffer.data[buffer.cursor.pos:])
	resize(&buffer.data, len(buffer.data) - n_bytes)

	buffer.cursor.pos = start_index
	buffer.dirty = true
	buffer_update_line_starts(buffer)
}

buffer_delete_word :: proc(buffer: ^Buffer) {
	if buffer.cursor.pos <= 0 do return

	original_pos := buffer.cursor.pos
	start_pos := original_pos

	// Move to word start.
	buffer.cursor.pos = prev_rune_start(buffer.data[:], buffer.cursor.pos)

	// Skip whitespace backwards.
	for buffer.cursor.pos > 0 && is_whitespace_byte(buffer.data[buffer.cursor.pos]) {
		buffer.cursor.pos = prev_rune_start(buffer.data[:], buffer.cursor.pos)
	}

	// Move through word character.
	if buffer.cursor.pos > 0 {
		current_rune, _ := utf8.decode_rune(buffer.data[buffer.cursor.pos:])
		is_word := is_word_character(current_rune)

		for buffer.cursor.pos > 0 {
			prev_pos := prev_rune_start(buffer.data[:], buffer.cursor.pos)
			r, _ := utf8.decode_rune(buffer.data[prev_pos:])

			if is_whitespace_byte(buffer.data[prev_pos]) || is_word_character(r) != is_word do break

			buffer.cursor.pos = prev_pos
		}
	}

	// Bytes do delete.
	delete_start := buffer.cursor.pos
	delete_size := original_pos - delete_start

	// Actually delete something...
	copy(buffer.data[delete_start:], buffer.data[original_pos:])
	resize(&buffer.data, len(buffer.data) - delete_size)
	buffer.cursor.pos = delete_start
	buffer.dirty = true
	buffer_update_line_starts(buffer)
}

// REFACTOR: This function takes quite a lot of cost
buffer_update_line_starts :: proc(buffer: ^Buffer) {
	// Clear existing line starts and add first line
	clear(&buffer.line_starts)
	append(&buffer.line_starts, 0) // First line always start at 0.

	for i := 0; i < len(buffer.data); i += 1 {
		if buffer.data[i] == '\n' do append(&buffer.line_starts, i + 1)
	}

	// Update cursor line and col.
	buffer.cursor.line = 0
	for i := 1; i < len(buffer.line_starts); i += 1 {
		if buffer.cursor.pos >= buffer.line_starts[i] {
			buffer.cursor.line = i
		}
	}

	buffer.cursor.col = buffer.cursor.pos - buffer.line_starts[buffer.cursor.line]
}

//
// Movement
//

// NOTE: This function will probably stay being this megazord forever, and I don't care.
buffer_move_cursor :: proc(buffer: ^Buffer, movement: Cursor_Movement) {
	current_line_start := buffer.line_starts[buffer.cursor.line]
	current_line_end := len(buffer.data)

	// Calculate line end position.
	if buffer.cursor.line < len(buffer.line_starts) - 1 {
		current_line_end = buffer.line_starts[buffer.cursor.line + 1] - 1
	}

	horizontal: bool

	switch movement {

	// 
	// Horizontal movement
	// 

	case .LEFT:
		if buffer.cursor.pos > current_line_start {
			buffer.cursor.pos = prev_rune_start(buffer.data[:], buffer.cursor.pos)
		}
		horizontal = true
	case .RIGHT:
		// Only move right if we're not already at the last character.
		if buffer.cursor.pos < current_line_end {
			// Don't allow moving from last character to end-of-line position.
			if buffer.cursor.pos + 1 == current_line_end {
				// We're at the last character already, don't move.
			} else {
				n_bytes := next_rune_length(buffer.data[:], buffer.cursor.pos)
				buffer.cursor.pos += n_bytes
			}
		}
		horizontal = true
	case .LINE_START:
		buffer.cursor.pos = buffer.line_starts[buffer.cursor.line]
		horizontal = true

	case .FIRST_NON_BLANK:
		current_line_start := buffer.line_starts[buffer.cursor.line]
		current_line_end := len(buffer.data)
		if buffer.cursor.line < len(buffer.line_starts) - 1 {
			current_line_end = buffer.line_starts[buffer.cursor.line + 1] - 1
		}

		pos := current_line_start
		// Skip whitespace characters.
		for pos < current_line_end && is_whitespace_byte(buffer.data[pos]) {
			pos += 1
		}

		// If all whitespace or empty line, start at start.
		if pos == current_line_end do pos = current_line_start
		buffer.cursor.pos = pos
		horizontal = true
	case .LINE_END:
		current_line := buffer.cursor.line
		current_line_start := buffer.line_starts[current_line]
		current_line_length := buffer_line_length(buffer, current_line)

		// Handle empty lines differently
		if current_line_length == 0 {
			buffer.cursor.pos = current_line_start
		} else {
			if current_line < len(buffer.line_starts) - 1 {
				line_end_pos := buffer.line_starts[current_line + 1] - 1
				// Only adjust if we have a newline character
				if line_end_pos >= 0 && buffer.data[line_end_pos] == '\n' {
					buffer.cursor.pos = line_end_pos - 1
				} else {
					buffer.cursor.pos = line_end_pos
				}
			} else {
				buffer.cursor.pos = len(buffer.data)
			}
		}
		horizontal = true
	case .WORD_LEFT:
		if buffer.cursor.pos <= 0 do break

		// Move to previous rune start
		buffer.cursor.pos = prev_rune_start(buffer.data[:], buffer.cursor.pos)

		// Skip whitespace backwards
		for buffer.cursor.pos > 0 && is_whitespace_byte(buffer.data[buffer.cursor.pos]) {
			buffer.cursor.pos = prev_rune_start(buffer.data[:], buffer.cursor.pos)
		}

		if buffer.cursor.pos <= 0 do break

		// Determine current character type
		current_rune, _ := utf8.decode_rune(buffer.data[buffer.cursor.pos:])
		is_word := is_word_character(current_rune)

		// Move backward through same-type characters
		for buffer.cursor.pos > 0 {
			prev_pos := prev_rune_start(buffer.data[:], buffer.cursor.pos)
			r, _ := utf8.decode_rune(buffer.data[prev_pos:])

			if is_whitespace_byte(buffer.data[prev_pos]) || is_word_character(r) != is_word {
				break
			}
			buffer.cursor.pos = prev_pos
		}

		horizontal = true

	case .WORD_RIGHT:
		if buffer.cursor.pos >= len(buffer.data) do return
		original_pos := buffer.cursor.pos

		// Skip leading whitespace.
		for buffer.cursor.pos < len(buffer.data) && is_whitespace_byte(buffer.data[buffer.cursor.pos]) do buffer.cursor.pos += 1

		if buffer.cursor.pos >= len(buffer.data) do break

		// Determine current character type.
		current_rune, bytes_read := utf8.decode_rune(buffer.data[buffer.cursor.pos:])
		if bytes_read == 0 do break
		is_word := is_word_character(current_rune)

		// Move through same-type characters.
		for buffer.cursor.pos <= len(buffer.data) {
			// See if we've hit a boundary.
			r, n := utf8.decode_rune(buffer.data[buffer.cursor.pos:])
			if n == 0 || is_whitespace_byte(buffer.data[buffer.cursor.pos]) || is_word_character(r) != is_word do break

			buffer.cursor.pos += n
		}

		// Skip trailing whitespace.
		for buffer.cursor.pos < len(buffer.data) &&
		    is_whitespace_byte(buffer.data[buffer.cursor.pos]) {
			buffer.cursor.pos += 1
		}

		// Ensure minimal movement.
		if buffer.cursor.pos == original_pos && buffer.cursor.pos < len(buffer.data) {
			// Move at least one character for single-character words.
			buffer.cursor.pos += 1
		}

		horizontal = true

	// 
	// Vertical movement
	// 

	case .UP:
		if buffer.cursor.line > 0 {
			// Get target col (preserved from the current position).
			target_col :=
				buffer.cursor.preferred_col != -1 ? buffer.cursor.preferred_col : buffer.cursor.col
			assert(target_col >= 0, "Target column cannot be negative")

			new_line := buffer.cursor.line - 1 // Move to prev line.

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

			buffer.cursor.pos = new_pos
		}
	case .DOWN:
		if buffer.cursor.line < len(buffer.line_starts) - 1 {
			// Same stuff as before.
			target_col :=
				buffer.cursor.preferred_col != -1 ? buffer.cursor.preferred_col : buffer.cursor.col
			assert(target_col >= 0, "Target column cannot be negative")

			new_line := buffer.cursor.line + 1 // Move to next line.

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

			buffer.cursor.pos = new_pos
		}
	}

	buffer_update_line_starts(buffer)

	// Update preferred col after horizontal movements.
	if horizontal {
		buffer.cursor.preferred_col = buffer.cursor.col
	}
}

//
// Drawing
//

buffer_draw :: proc(
	buffer: ^Buffer,
	font: Font,
	ctx: Draw_Context,
	allocator := context.allocator,
) {
	buffer_draw_scissor_begin(ctx)
	defer buffer_draw_scissor_end()

	buffer_draw_visible_lines(buffer, font, ctx, allocator)
	buffer_draw_cursor(buffer, font, ctx)
}

buffer_draw_cursor :: proc(buffer: ^Buffer, font: Font, ctx: Draw_Context) {
	cursor_pos := ctx.position

	// Adjust vertical position based on line number.
	cursor_pos.y += f32(buffer.cursor.line) * (f32(font.size) + font.spacing)

	assert(buffer.cursor.pos >= 0, "Cursor position must be greater or equal to 0")
	assert(len(buffer.data) >= 0, "Buffer size has to be greater or equal to 0")

	line_start := buffer.line_starts[buffer.cursor.line]
	cursor_pos_clamped := min(buffer.cursor.pos, len(buffer.data)) // NOTE: Make sure we cannot slice beyond the buffer size.
	assert(
		line_start <= cursor_pos_clamped,
		"Line start index must be less or equal to clamped cursor position",
	)

	line_text := buffer.data[line_start:buffer.cursor.pos]
	assert(len(line_text) >= 0, "Line text cannot be negative")

	temp_text := make([dynamic]u8, len(line_text) + 1)
	defer delete(temp_text)

	copy(temp_text[:], line_text)
	temp_text[len(line_text)] = 0
	cursor_pos.x +=
		rl.MeasureTextEx(font.ray_font, cstring(&temp_text[0]), f32(font.size), font.spacing).x

	if buffer.cursor.blink && (int(rl.GetTime() * 2) % 2 == 0) do return

	font_size := f32(font.size)

	switch buffer.cursor.style {
	case .BAR:
		rl.DrawLineV(cursor_pos, {cursor_pos.x, cursor_pos.y + font_size}, buffer.cursor.color)
	case .BLOCK:
		char_width := rl.MeasureTextEx(font.ray_font, "@", font_size, font.spacing).x
		rl.DrawRectangleV(
			cursor_pos,
			{char_width, font_size},
			{buffer.cursor.color.r, buffer.cursor.color.g, buffer.cursor.color.b, 128},
		)
	case .UNDERSCORE:
		char_width := rl.MeasureTextEx(font.ray_font, "M", font_size, font.spacing).x
		rl.DrawLineV(
			{cursor_pos.x, cursor_pos.y + font_size},
			{cursor_pos.x + char_width, cursor_pos.y + font_size},
			buffer.cursor.color,
		)
	}
}

// Draws only the visible lines.
buffer_draw_visible_lines :: proc(
	buffer: ^Buffer,
	font: Font,
	ctx: Draw_Context,
	allocator := context.allocator,
) {
	for line in ctx.first_line ..= ctx.last_line {
		line_start := buffer.line_starts[line]
		line_end := len(buffer.data)
		if line < len(buffer.line_starts) - 1 {
			// Exclude newline.
			line_end = buffer.line_starts[line + 1] - 1
		}
		// Convert the line slice to a C-string.
		line_text := buffer.data[line_start:line_end]
		line_str := strings.clone_to_cstring(string(line_text), allocator)

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

// Begin and end scissor mode using the draw context.
buffer_draw_scissor_begin :: proc(ctx: Draw_Context) {
	rl.BeginScissorMode(
		i32(ctx.position.x),
		i32(ctx.position.y),
		ctx.screen_width,
		ctx.screen_height,
	)
}

buffer_draw_scissor_end :: proc() {
	rl.EndScissorMode()
}
