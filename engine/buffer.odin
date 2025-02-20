package engine

import "core:mem"
import vmem "core:mem/virtual"
import "core:unicode/utf8"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

// Buffer stores text as an array of bytes.
// TODO: Refactor this to use a rope?
Buffer :: struct {
	original:    []u8,          // Memory-mapped original file.
	additions:   [dynamic]u8,   // User edits.
	pieces:      [dynamic]Piece, // Sequence of text pieces.
	line_count:  int,           // Cached line count.
	cursor:      Cursor,
	dirty:       bool,          // If the buffer has been modified.
	version:     u64
}

Cursor :: struct {
	pos:   int,          // Position in bytes (relative to the entire buffer).
	line:  int,          // Current line number 
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
buffer_init :: proc(allocator := context.allocator) -> Buffer {
	return Buffer {
		pieces = make([dynamic]Piece, 0, 16, allocator),
		additions = make([dynamic]u8, 0, 1024, allocator),
		cursor = Cursor {
			pos = 0,
			line = 0,
			style = .BLOCK,
			color = rl.GRAY,
			blink = false
		},
	}
}

buffer_load_file :: proc(b: ^Buffer, filename: string, allocator := context.allocator) -> bool {
	data, err := vmem.map_file_from_path(filename, {.Read})
	if err == .None do return false

	b.original = data

	// Initial piece covering entire file.
	append(&b.pieces, Piece {
		source = .ORIGINAL,
		start = 0,
		length = len(data),
		newlines = count_newlines(data)
	})

	b.line_count = b.pieces[0].newlines + 1
	return true
}

//
// Editing
// 

buffer_insert_text :: proc(b: ^Buffer, text: string) {
	text_bytes := transmute([]u8)text
	old_len := len(b.additions)
	append(&b.additions, ..text_bytes)

	// New piece for addition.
	new_piece := Piece {
		source = .ADD,
		start = old_len,
		length = len(text_bytes),
		newlines = count_newlines(text_bytes),
	}

	// Simple append for now.
	// TODO: Proper splitting.
	append(&b.pieces, new_piece)

	b.line_count += new_piece.newlines
	b.version += 1
	b.dirty = true
}

buffer_insert_char :: proc(b: ^Buffer, char: rune) {
	if !is_char_supported(char) do return

	// Encode rune into UTF-8.
	encoded, n_bytes := utf8.encode_rune(char)

	// Append to additions buffer.
	old_len := len(b.additions)
	append(&b.additions, ..encoded[:n_bytes])

	// Create new piece.
	append(&b.pieces, Piece {
		source = .ADD,
		start = old_len,
		length = n_bytes,
		newlines = 0 // TODO: Count newlines.
	})

	b.cursor.pos += n_bytes
	b.version += 1
	b.dirty = true
}

buffer_delete_char :: proc(b: ^Buffer) {
	if b.cursor.pos <= 0 do return

	// Temporarily naive implementation
	// TODO: Piece splitting.
	if len(b.pieces) > 0 {
		last := &b.pieces[len(b.pieces) - 1]
		if last.length > 0 {
			last.length -= 1
			b.cursor.pos -= 1
			b.version += 1
			b.dirty = true
		}
	}
}

//
// Movement
// 

buffer_move_cursor :: proc(b: ^Buffer, movement: Cursor_Movement) {
	// REFACTOR: This is a naive implementation.
	switch movement {
	case .LEFT: b.cursor.pos = max(0, b.cursor.pos - 1)
	case .RIGHT: b.cursor.pos += 1
	case .UP:  b.cursor.line = max(0, b.cursor.line - 1)
	case .DOWN: b.cursor.line += 1
	}

	// REFACTOR: Temporary line tracking.
	b.cursor.line = count_lines_before_pos(b, b.cursor.pos)
}

//
// Drawing
// 

buffer_draw :: proc(b: ^Buffer, position: rl.Vector2, font: Font, allocator := context.allocator) {
	line_height := f32(font.size) + font.spacing
	y_offset : f32 = 0
	current_line := 0

	for &piece in b.pieces {
		text := get_piece_text(b, &piece)
		lines, err := strings.split(string(text), "\n", allocator)
		assert(err == nil, "Error trying to allocate to split a string at a piece")

		for line in lines {
			// Viewport culling to drawing (10 lines around the cursor).
			if current_line >= b.cursor.line - 10 && current_line <= b.cursor.line + 10 {
				rl.DrawTextEx(font.ray_font, cstring(raw_data(line)), {position.x, position.y + y_offset}, f32(font.size), font.spacing, font.color)
			}

			y_offset += line_height
			current_line += 1
		}
	}

	buffer_draw_cursor(b, position, font)
}

buffer_draw_cursor :: proc(b: ^Buffer, position: rl.Vector2, font: Font) {
	cursor_pos := position

	// Vertical position.
	line_height := f32(font.size) + font.spacing
	cursor_pos.y += f32(b.cursor.line) * line_height

	// Get text before cursor.
	temp := get_text_before_cursor(b)
	defer delete(temp)

	// Horizontal position.
	text_width := rl.MeasureTextEx(font.ray_font, cstring(raw_data(temp)), f32(font.size), font.spacing).x
	cursor_pos.x += text_width

	if b.cursor.blink && (int(rl.GetTime() * 2) % 2 == 0) do return

	font_size := f32(font.size)
	switch b.cursor.style {
	case .BAR:
		rl.DrawLineV(cursor_pos, {cursor_pos.x, cursor_pos.y + font_size}, b.cursor.color)
	case .BLOCK:
		char_width := rl.MeasureTextEx(font.ray_font, "@", font_size, font.spacing).x
		rl.DrawRectangleV(
			cursor_pos,
			{char_width, font_size},
			{b.cursor.color.r, b.cursor.color.g, b.cursor.color.b, 128},
		)
	case .UNDERSCORE:
		char_width := rl.MeasureTextEx(font.ray_font, "M", font_size, font.spacing).x
		rl.DrawLineV(
			{cursor_pos.x, cursor_pos.y + font_size},
			{cursor_pos.x + char_width, cursor_pos.y + font_size},
			b.cursor.color,
		)
	}
}
