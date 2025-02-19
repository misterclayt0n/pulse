package engine

import "core:mem"
import "core:unicode/utf8"
import "core:os"
import rl "vendor:raylib"

// Buffer stores text as an array of bytes.
// TODO: Refactor this to use a rope?
Buffer :: struct {
	data:        [dynamic]u8,  // Dynamic array of bytes that contains text.
	line_starts: [dynamic]int, // Indexes of the beginning of each line in the array byte.
	dirty:       bool,         // If the buffer has been modified.
	cursor:      Cursor,
}

Cursor :: struct {
	pos:   int,         // Position in the array of bytes.
	sel:   int,         
	line:  int,         
	col:   int,         
	style: Cursor_Style,
	color: rl.Color,    
	blink: bool,        
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
	// TODO: A lot more
}

// Creates a new buffer with a given initial capacity.
buffer_init :: proc(allocator := context.allocator, initial_cap := 1024) -> Buffer {
	return Buffer {
		data = make([dynamic]u8, 0, initial_cap, allocator),
		line_starts = make([dynamic]int, 1, 64, allocator),
		dirty = false,
		cursor = Cursor {
			pos = 0,
			sel = 0,
			line = 0,
			col = 0,
			style = .BLOCK,
			color = rl.GRAY,
			blink = false
		},
	}
}

// NOTE: This is a bit useless if we're using an arena.
buffer_free :: proc(buffer: ^Buffer) {
	delete(buffer.data)
	delete(buffer.line_starts)
}

buffer_load_file :: proc(buffer: ^Buffer, filename: string, allocator := context.allocator) -> bool {
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

	// Encode rune into UTF-8
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

buffer_move_cursor :: proc(buffer: ^Buffer, movement: Cursor_Movement) {
	current_line_start := buffer.line_starts[buffer.cursor.line]
	current_line_end := len(buffer.data)

	// Calculate line end position.
	if buffer.cursor.line < len(buffer.line_starts) - 1 {
		current_line_end = buffer.line_starts[buffer.cursor.line + 1] - 1
	}
	
	switch movement {
	case .LEFT:
		if buffer.cursor.pos > current_line_start {
			buffer.cursor.pos = prev_rune_start(buffer.data[:], buffer.cursor.pos)
		}
	case .RIGHT:
		if buffer.cursor.pos < current_line_end {
			n_bytes := next_rune_length(buffer.data[:], buffer.cursor.pos)
			buffer.cursor.pos += n_bytes
		}
	case .UP: 
		if buffer.cursor.line > 0 {
			// Get target col (preserved from the current position).
			target_col := buffer.cursor.col
			new_line := buffer.cursor.line - 1 // Move to prev line.

			// Calculate new position.
			new_line_length := buffer_line_length(buffer, new_line)
			new_col := min(target_col, new_line_length)
			buffer.cursor.pos = buffer.line_starts[new_line] + new_col
		}
	case .DOWN:
		if buffer.cursor.line < len(buffer.line_starts) - 1 {
			// Same stuff as before.
			target_col := buffer.cursor.col
			new_line := buffer.cursor.line + 1 // Move to next line.

			new_line_length := buffer_line_length(buffer, new_line)
			new_col := min(target_col, new_line_length)
			buffer.cursor.pos = buffer.line_starts[new_line] + new_col
		}
	}

	buffer_update_line_starts(buffer)
}

//
// Drawing
// 

buffer_draw :: proc(buffer: ^Buffer, position: rl.Vector2, font: Font) {
	// Ensure null termination for text display.
	append(&buffer.data, 0)
	defer resize(&buffer.data, len(buffer.data) - 1)
	// Draw main text.
	rl.DrawTextEx(font.ray_font, cstring(&buffer.data[0]), position, f32(font.size), font.spacing, font.color)

	buffer_draw_cursor(buffer, position, font)
}

buffer_draw_cursor :: proc(buffer: ^Buffer, position: rl.Vector2, font: Font) {
	cursor_pos := position
	
	// Adjust vertical position based on line number.	
	cursor_pos.y += f32(buffer.cursor.line) * (f32(font.size) + font.spacing)
	
	assert(buffer.cursor.pos >= 0, "Cursor position must be greater or equal to 0")
	assert(len(buffer.data) > 0, "Buffer size has to be greater than 0")
	
	line_start := buffer.line_starts[buffer.cursor.line]
	cursor_pos_clamped := min(buffer.cursor.pos, len(buffer.data)) // NOTE: Make sure we cannot slice beyond the buffer size.
	assert(line_start <= cursor_pos_clamped, "Line start index must be less or equal to clamped cursor position")

	line_text := buffer.data[line_start:buffer.cursor.pos]
	assert(len(line_text) >= 0, "Line text cannot be negative")

	temp_text := make([dynamic]u8, len(line_text) + 1)
	defer delete(temp_text)

	copy(temp_text[:], line_text)
	temp_text[len(line_text)] = 0
	cursor_pos.x += rl.MeasureTextEx(font.ray_font, cstring(&temp_text[0]), f32(font.size), font.spacing).x

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

// 
// Helpers
// 

// Returns the length of a specified line.
buffer_line_length :: proc(buffer: ^Buffer, line: int) -> int {
	assert(line < len(buffer.line_starts), "Invalid line index")
	start := buffer.line_starts[line]
	end := len(buffer.data)

	if line < len(buffer.line_starts) - 1{
		end = buffer.line_starts[line + 1]

		// NOTE: Subtract 1 to exclude the newline character.
		// Only considers visible characters.
		return end - start - 1
	}

	return end - start
}
