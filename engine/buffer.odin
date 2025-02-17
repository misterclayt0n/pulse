package engine

import "core:mem"
import "core:unicode/utf8"
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
			color = rl.BLACK,
			blink = false
		},
	}
}

// NOTE: This is a bit useless if we're using an arena.
buffer_free :: proc(buffer: ^Buffer) {
	delete(buffer.data)
	delete(buffer.line_starts)
}

//
// Editing
// 

buffer_insert_text :: proc(buffer: ^Buffer, text: string) {
	assert(len(text) != 0, "The length of the text should not be 0")
	offset := buffer.cursor.pos
	// assert(offset != 0, "Cursor offset cannot be negative")
	// assert(!(offset > len(buffer.data)), "Cursor cannot be bigger than the length of the buffer")
	if offset < 0 || offset > len(buffer.data) do return

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
	// buffer_update_line_starts(buffer)
}

buffer_insert_char :: proc(buffer: ^Buffer, char: rune) {
	if !is_char_supported(char) do return
	offset := buffer.cursor.pos
	if offset < 0 || offset > len(buffer.data) do return
	
	// Make space for new character.
	resize(&buffer.data, len(buffer.data) + 1)

	// Move existing text to make room.
	if offset < len(buffer.data) - 1 {
		copy(buffer.data[offset + 1:], buffer.data[offset:])
	}

	// Insert new character.
	buffer.data[offset] = u8(char)
	buffer.cursor.pos += 1
	buffer.dirty = true
	// buffer_update_line_starts(buffer)
}

buffer_delete_char :: proc() {}

//
// Drawing
// 

buffer_draw :: proc(buffer: ^Buffer, position: rl.Vector2, font: Font) {
	assert(len(buffer.data) > 0, "We can only draw text if we have some content in the buffer")

	// Ensure null termination for text display.
	append(&buffer.data, 0)
	defer resize(&buffer.data, len(buffer.data) - 1)
	// Draw main text.
	rl.DrawTextEx(font.ray_font, cstring(&buffer.data[0]), position, f32(font.size), font.spacing, font.color)
}
