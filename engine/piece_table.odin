package engine

Piece_Source :: enum {
	ORIGINAL,
	ADD,
}

Piece :: struct {
	source:   Piece_Source, 
	start:    int,          // Start position in source buffer.
	length:   int,          // Length of this piece.
	newlines: int           // Number of newlines in this piece.
}

count_newlines :: proc(data: []u8) -> int {
	count := 0
	for b in data {
		if b == '\n' do count += 1
	}
	return count
}

count_lines_before_pos :: proc(b: ^Buffer, pos: int) -> int {
	count   := 0
	current := 0 

	for piece in b.pieces {
		end := current + piece.length			
		if pos < end do return count + count_newlines_in_piece(piece, pos - current)

		count += piece.newlines
		current = end
	}

	return count
}

count_newlines_in_piece :: proc(piece: Piece, max_pos: int) -> int {
	// TODO
	return 0
}

get_piece_text :: proc(b: ^Buffer, p: ^Piece) -> []u8 {
	if p.source == .ORIGINAL {
		return b.original[p.start:][:p.length]
	}
	return b.additions[p.start:][:p.length]
}
 
find_piece_at_position :: proc(b: ^Buffer, abs_pos: int) -> (piece_idx: int, piece_pos: int) {
	current := 0
	for p, i in b.pieces {
		if current <= abs_pos && abs_pos < current + p.length {
			return i, abs_pos - current
		}

		current += p.length
	}

	return -1, 0
}

get_text_before_cursor :: proc(b: ^Buffer) -> []u8 {
	total_len := 0
	for &piece in b.pieces {
		total_len += piece.length
		if total_len > b.cursor.pos {
			last_piece_text := get_piece_text(b, &piece)
			return last_piece_text[:b.cursor.pos - (total_len - piece.length)]
		}
	}

	return []u8{}
}

