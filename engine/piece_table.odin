package engine

import "core:mem"

Piece_Source :: enum {
	ORIGINAL, // Read-only file content.
	ADD,      // Editable buffer for changes.
}

Piece_Node :: struct {
	source:       Piece_Source, 
	start:        int,          // Start index in source buffer.
	length:       int,          // Length in bytes.
	lines:        int,          // Number of newlines in this piece.
	left:         ^Piece_Node,  
	right:        ^Piece_Node,
	height:       int,          // For balancing.
	cumul_length: int,          // Cumulative length of left subtree + this piece.
	cumul_lines:  int           // Cumulative lines in left subtree + this piece.
}

Piece_Table :: struct {
	original:    []u8,           // Memory-mapped original file.
	add_buffer:  [dynamic]u8,    // Append-only additions.
	root:        ^Piece_Node,    // Root of the balanced tree.
	allocator:   mem.Allocator
}

// 
// Core api
// 

// Initializes with optional file loading.
piece_table_init :: proc(filename: string = "", allocator := context.allocator) -> Piece_Table { 
	return Piece_Table { } 
}

// Inserts text at a given position.
piece_table_insert :: proc(pt: ^Piece_Table, text: string, pos: int) { 
	// Split the tree at `pos`.
	// Create a new piece for `text` in the `add_buffer`.
	// Insert the new piece into the tree.
	// Rebalance the tree.
}

// Delete range [start, end).
piece_table_delete :: proc(pt: ^Piece_Table, start, end: int) { 
	// Find the pieces overlapping [start, end).
	// Remove or truncate those pieces.
	// Rebalance the tree.
}

// Write out to file.
piece_table_save :: proc(pt: ^Piece_Table, filename: string) -> bool { return true }

// 
// Navigation
// 

// Convert absolute position to line/column.
piece_table_pos_to_linecol :: proc(pt: ^Piece_Table, pos: int) -> (line, col: int) { return 0, 0 }

// Convert line/column to absolute position.
piece_table_linecol_to_pos :: proc(pt: ^Piece_Table, line, col: int) -> int { return 0 } 

// 
// Text Access
// 

// Get text in range [start, end).
piece_table_get_text :: proc(pt: ^Piece_Table, start, end: int) -> string { 
	// Traverse the tree to find pieces in [start, end).
	// Concatenate the text from those pieces.
	// Return the result.
	return "" 
}

// Get full text of line.
piece_table_get_line :: proc(pt: ^Piece_Table, line: int) -> string { return "" }

// 
// Cursor helpers
// 

// Previous UTF-8 rune position.
piece_table_prev_rune :: proc(pt: ^Piece_Table, pos: int) -> int { return 0 }

// Next UTF-8 rune position.
piece_table_next_rune :: proc(pt: ^Piece_Table, pos: int) -> int { return 0 }

// 
// Rendering
//

// Get text for visible viewport.
piece_table_get_visible :: proc(pt: ^Piece_Table, first_line, max_lines: int) -> (text: string, actual_lines: int) { return "", 0 }

// 
// Helpers
// 

@(private)
// Incremental line tracking.
update_line_cache :: proc(pt: ^Piece_Table, from_piece: int) { }

@(private)
// Split a piece at specified position.
split_piece :: proc(pt: ^Piece_Table, piece_idx, split_pos: int) -> (left, right: int) { return 0, 0 }

@(private)
// Merge adjacent pieces if possible.
merge_pieces :: proc(pt: ^Piece_Table, piece_idx: int) -> bool { return true }
