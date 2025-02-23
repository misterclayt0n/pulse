// TODO: Undo, redo
// TODO: Viewport optimization.
package engine

import "core:mem"
import "core:os"
import "core:log"
import "core:strings"
import "core:testing"

// Indicates whether a piece comes from the original (immutable) file or the add buffer (where new text is appended).
Piece_Source :: enum {
	ORIGINAL, // Read-only file content.
	ADD,      // Editable buffer for changes.
}

// A node in the tree, represents a contiguous fragment of text
Piece_Node :: struct {
	source:       Piece_Source,
	start:        int,          // Start index in source buffer.
	length:       int,          // Length in bytes.
	lines:        int,          // Number of newlines in this piece.
	left:         ^Piece_Node,  // Pointer to left child in AVL tree.
	right:        ^Piece_Node,  // Pointer to right child in AVL tree.
	height:       int,          // For balancing.
	cumul_length: int,          // Cumulative length of left subtree + this piece.
	cumul_lines:  int           // Cumulative lines in left subtree + this piece.
}

// Overall container for the document
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
piece_table_init :: proc(filename: string = "", allocator := context.allocator) -> ^Piece_Table {
	pt := new(Piece_Table, allocator)
	pt.allocator = allocator
	pt.add_buffer = make([dynamic]u8, 0, 1024, allocator)

	if filename != "" {
		data, ok := os.read_entire_file(filename, allocator)
		assert(ok, "Could not read file")
		pt.original = data

		// Create initial piece for original content.
		lines := count_lines(data)
		pt.root = new_node(.ORIGINAL, 0, len(data), lines, allocator)
	}

	return pt
}

// Inserts text at a given position.
piece_table_insert :: proc(pt: ^Piece_Table, text: string, pos: int) {
	start := len(pt.add_buffer)
    append(&pt.add_buffer, ..transmute([]u8)text)
    lines := count_lines(transmute([]u8)text)
    new_piece := new_node(.ADD, start, len(text), lines, pt.allocator)
    pt.root = insert_node(pt.root, new_piece, pos, pt)
}

// Delete range [start, end).
piece_table_delete :: proc(pt: ^Piece_Table, start, end: int) {
	if start >= end do return // Nothing to delete.
	total_length := pt.root.cumul_length if pt.root != nil else 0
	end := min(end, total_length) // Clamp to document length

	// Delete operation works by splitting at both ends and excluding the middle.
	pt.root = delete_range(pt.root, start, end, pt)
}

// Write out to file.
piece_table_save :: proc(pt: ^Piece_Table, filename: string, allocator := context.allocator) -> bool {
	// ASSERT?
	if pt.root == nil do return false // Handle empty document case.
	
	data := make([dynamic]u8, 0, pt.root.cumul_length, allocator)
	traverse_tree_save(pt.root, pt, &data)
	defer delete(data)
	return os.write_entire_file(filename, data[:])
}

//
// Navigation
//

// Convert absolute position to line/column.
piece_table_pos_to_linecol :: proc(pt: ^Piece_Table, pos: int) -> (line, col: int) {
	// ASSERT?
	if pt.root == nil do return 0, 0 

	current_pos := 0
	current_line := 0
	node := pt.root
	target_pos := clamp(pos, 0, pt.root.cumul_length)

	for node != nil {
		left_length := node.left != nil ? node.left.cumul_length : 0
		left_lines := node.left != nil ? node.left.cumul_lines : 0 

		if target_pos < current_pos + left_length {
			node = node.left
			continue
		}

		current_pos += left_length
		current_line += left_lines

		if target_pos < current_pos + node.length {
			offset := target_pos - current_pos
			newlines := count_newlines_in_range(pt, node, offset)
			last_nl := find_last_newline(pt, node, offset)

			col := offset
			if last_nl != -1 do col = offset - (last_nl + 1)
			return current_line + newlines, col
		}
	}

	return current_line, pt.root.cumul_length - current_pos
}

// Convert line/column to absolute position.
// TODO
piece_table_linecol_to_pos :: proc(pt: ^Piece_Table, line, col: int) -> int {
	if pt.root == nil do return 0
    
    current_line := 0
    current_pos := 0
    node := pt.root
    target_line := clamp(line, 0, pt.root.cumul_lines)
    
    for node != nil {
        left_lines := node.left != nil ? node.left.cumul_lines : 0

        if target_line < current_line + left_lines {
            node = node.left
            continue
        }
        
        current_line += left_lines

        if target_line <= current_line + node.lines {
            line_in_node := target_line - current_line
            data := pt.original if node.source == .ORIGINAL else pt.add_buffer[:]
            start_idx := node.start
            count := 0
            pos := 0
            
            // Find start of target line
            for i in 0..<node.length {
            	if line_in_node > 0 {
            		if data[start_idx + i] == '\n' {
            			count += 1
            			if count == line_in_node {
            				pos = i + 1 // Start after the newline.
            				break
            			}
            		}
            	} else {
            		pos = 0
            		break
            	}
            }
            
            // Clamp column to line length
            line_end := node.length
            for i in pos..<node.length {
                if data[start_idx + i] == '\n' {
                    line_end = i
                    break
                }
            }
            clamped_col := clamp(col, 0, line_end - pos)
            
            return current_pos + pos + clamped_col
        }

        current_line += node.lines
        current_pos += node.length
        node = node.right
    }
    
    return pt.root.cumul_length
}


//
// Text Access
//

// Get full text of line.
piece_table_get_line :: proc(pt: ^Piece_Table, line: int) -> string {
    pos := piece_table_linecol_to_pos(pt, line, 0)
    end_pos := piece_table_linecol_to_pos(pt, line + 1, 0)
    return piece_table_get_text(pt, pos, end_pos)
}

// Get text in range [start, end).
piece_table_get_text :: proc(pt: ^Piece_Table, start, end: int) -> string {
    if pt.root == nil do return ""

    builder := strings.builder_make(context.temp_allocator)
    current_pos := 0
    traverse_tree(pt.root, start, end, &current_pos, pt, &builder)
    return strings.to_string(builder)
}


//
// Cursor helpers
//

// Previous UTF-8 rune position.
// TODO
piece_table_prev_rune :: proc(pt: ^Piece_Table, pos: int) -> int { return 0 }

// Next UTF-8 rune position.
// TODO
piece_table_next_rune :: proc(pt: ^Piece_Table, pos: int) -> int { return 0 }

//
// Rendering
//

// Get text for visible viewport.
// TODO
piece_table_get_visible :: proc(pt: ^Piece_Table, first_line, max_lines: int) -> (text: string, actual_lines: int) { return "", 0 }

//
// Private helpers
//

@(private)
count_lines :: proc(data: []u8) -> int {
	count := 0
	for b in data { // This counts actual newlines (n lines = n + 1 line breaks).
		if b == '\n' do count += 1
	}

	return count
}

@(private)
count_newlines_in_range :: proc(pt: ^Piece_Table, node: ^Piece_Node, offset: int) -> int {
	data := pt.original if node.source == .ORIGINAL else pt.add_buffer[:]
	start := node.start
	end := start + min(offset, node.length)
	count := 0

	for i in start..<end {
		if data[i] == '\n' do count += 1
	}

	return count
}

@(private)
find_last_newline :: proc(pt: ^Piece_Table, node: ^Piece_Node, offset: int) -> int {
	data := pt.original if node.source == .ORIGINAL else pt.add_buffer[:]
	start := node.start
	end := start + min(offset, node.length)
	last := -1

	for i in start..<end {
		if data[i] == '\n' do last = i - start
	}

	return last
}

@(private)
// Split a piece at specified position.
split_piece :: proc(pt: ^Piece_Table, node: ^Piece_Node, split_pos: int, allocator: mem.Allocator) -> (left, right: ^Piece_Node) {
	// Get the actual text data
    data: []u8
    switch node.source {
    case .ORIGINAL: data = pt.original
    case .ADD: data = pt.add_buffer[:]
    }
    node_data := data[node.start:][:node.length]

    // Count newlines in left part
    left_lines := 0
    for i in 0..<split_pos {
        if node_data[i] == '\n' do left_lines += 1
    }

    // Create new pieces
    left = new_node(node.source, node.start, split_pos, left_lines, allocator)
    right = new_node(node.source, node.start + split_pos, node.length - split_pos, node.lines - left_lines, allocator)

    return
}

@(private)
count_lines_in_piece :: proc(node: ^Piece_Node) -> int {
    // Implementation depends on how you store text data
    // For testing, just return approximate line count
    return node.lines
}

@(private)
new_node :: proc(source: Piece_Source, start, length, lines: int, allocator := context.allocator) -> ^Piece_Node {
	node := new(Piece_Node, allocator)
	node^ = Piece_Node {
		source = source,
		start = start,
		length = length,
		lines = lines,
		height = 1,
		cumul_length = length,
		cumul_lines = lines
	}

	return node
}

@(private)
node_height :: proc(node: ^Piece_Node) -> int {
	// ASSERT?
	return node.height if node != nil else 0
}

@(private)
update_node_metadata :: proc(node: ^Piece_Node) {
	left_height := node_height(node.left)
	right_height := node_height(node.right)
	node.height = 1 + max(left_height, right_height)

	left_length := node.left.cumul_length if node.left != nil else 0
	right_length := node.right.cumul_length if node.right != nil else 0
	node.cumul_length = left_length + node.length + right_length

	left_lines := node.left.cumul_lines if node.left != nil else 0
	right_lines := node.right.cumul_lines if node.right != nil else 0
	node.cumul_lines = left_lines + node.lines + right_lines
}

@(private)
rotate_right :: proc(y: ^Piece_Node) -> ^Piece_Node {
	x := y.left
	t := x.right

	x.right = y
	y.left = t

	update_node_metadata(y)
	update_node_metadata(x)

	return x
}

@(private)
rotate_left :: proc(x: ^Piece_Node) -> ^Piece_Node {
	y := x.right
	t := y.left

	y.left = x
	x.right = t

	update_node_metadata(x)
	update_node_metadata(y)

	return y
}

@(private)
balance_node :: proc(node: ^Piece_Node) -> ^Piece_Node {
	balance_factor := node_height(node.left) - node_height(node.right)

	if balance_factor > 1 {
		if node_height(node.left.left) >= node_height(node.left.right) {
			return rotate_right(node)
		}

		node.left = rotate_left(node.left)
		return rotate_right(node)
	}

	if balance_factor < - 1 {
		if node_height(node.right.right) >= node_height(node.right.left) {
			return rotate_left(node)
		}

		node.right = rotate_right(node.right)
		return rotate_left(node)
	}

	return node
}

@(private)
insert_node :: proc(root: ^Piece_Node, new_node: ^Piece_Node, pos: int, pt: ^Piece_Table) -> ^Piece_Node {
	if root == nil do return new_node

    left_size := root.left.cumul_length if root.left != nil else 0

    if pos <= left_size {
        root.left = insert_node(root.left, new_node, pos, pt)
    } else if pos <= left_size + root.length {
        // Split current node.
        split_pos := pos - left_size
        left_piece, right_piece := split_piece(pt, root, split_pos, pt.allocator)

        // Insert new node after left piece.
        new_root := right_piece
        new_root.left = insert_node(new_root.left, new_node, 0, pt)

        // Rebuild the tree.
        new_root.left = insert_node(new_root.left, left_piece, left_size, pt)
        update_node_metadata(new_root)
        return balance_node(new_root)
    } else {
        root.right = insert_node(root.right, new_node, pos - left_size - root.length, pt)
    }

    update_node_metadata(root)
    return balance_node(root)
}

@(private)
// Actually performs the deletion.
delete_range :: proc(root: ^Piece_Node, start, end: int, pt: ^Piece_Table) -> ^Piece_Node {
	// ASSERT?
	if root == nil do return nil

	// Calculate left subtree size.
	left_size := root.left.cumul_length if root.left != nil else 0
	node_start := left_size
	node_end := node_start + root.length

	new_left := delete_range(root.left, start, end, pt)
	new_right := delete_range(root.right, max(start - node_end, 0), max(end - node_end, 0), pt)

	// Process current node.
	if node_end > start && node_start < end {
		// Split into three parts: before, during and after deletion.
		split_start := max(start - node_start, 0)
		split_end := min(end - node_start, root.length)

		// Create remnants.
        left_remnant, right_remnant: ^Piece_Node = nil, nil
		if split_start > 0 {
			left_remnant, _ = split_piece(pt, root, split_start, pt.allocator)
		}

		if split_end < root.length {
			_, right_remnant = split_piece(pt, root, split_end, pt.allocator)
		}

		// Build new subtree from remnants.
		new_subtree: ^Piece_Node = nil
		if left_remnant != nil {
			new_subtree = insert_node(new_subtree, left_remnant, 0, pt)
		}
		if right_remnant != nil {
			pos := left_remnant != nil ? left_remnant.cumul_length : 0
			new_subtree = insert_node(new_subtree, right_remnant, pos, pt)
		}

		return new_subtree
	}

	root.left = new_left
	root.right = new_right
	update_node_metadata(root)
	return balance_node(root)
}

@(private)
traverse_tree :: proc(node: ^Piece_Node, start, end: int, current_pos: ^int, pt: ^Piece_Table, builder: ^strings.Builder) {
    if node == nil do return

    // Traverse left first.
    traverse_tree(node.left, start, end, current_pos, pt, builder)

    // Check if this node overlaps with requested range.
    node_start := current_pos^
    node_end := node_start + node.length

    if node_end > start && node_start < end {
        // Calculate overlap.
        overlap_start := max(start - node_start, 0)
        overlap_end := min(end - node_start, node.length)

        // Get the actual text data.
        data: []u8
        switch node.source {
        case .ORIGINAL: data = pt.original
        case .ADD: data = pt.add_buffer[:]
        }

        // Write the overlapping portion.
        strings.write_bytes(builder, data[node.start+overlap_start : node.start+overlap_end])
    }

    current_pos^ += node.length

    // Traverse right.
    traverse_tree(node.right, start, end, current_pos, pt, builder)
}
 
traverse_tree_save :: proc(node: ^Piece_Node, pt: ^Piece_Table, data: ^[dynamic]u8) {
	// ASSERT?
	// data := data
	if node == nil do return
	traverse_tree_save(node.left, pt, data)

	src := pt.original if node.source == .ORIGINAL else pt.add_buffer[:]
	start := node.start
	end := start + node.length
	append_elems(data, ..src[start:end])

	traverse_tree_save(node.right, pt, data)
}


//
// Tests
//

@(test)
piece_table_test :: proc(t: ^testing.T) {
	allocator := context.allocator
    pt := piece_table_init(allocator=allocator)

    // Test 1: Basic insertion.
    piece_table_insert(pt, "Hello", 0)
    text := piece_table_get_text(pt, 0, 5)
    testing.expect_value(t, text, "Hello")

    // Test 2: Append insertion.
    piece_table_insert(pt, " World", 5)
    text = piece_table_get_text(pt, 0, 11)
    testing.expect_value(t, text, "Hello World")

    // Test 3: Middle insertion.
    piece_table_insert(pt, " cruel", 5)
    text = piece_table_get_text(pt, 0, 17)
    testing.expect_value(t, text, "Hello cruel World")

    // Test 4: Verify tree balance.
    testing.expect(t, pt.root.height <= 3, "Tree should be balanced")

    // Test 5: Line counting.
    pt2 := piece_table_init(allocator=allocator)
    piece_table_insert(pt2, "Line1\nLine2\nLine3", 0)
    testing.expect_value(t, pt2.root.cumul_lines, 2)  // 2 newlines.
}

@(test)
delete_test :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    pt := piece_table_init()

    piece_table_insert(pt, "The quick brown fox jumps", 0)
    piece_table_delete(pt, 4, 10)
    
    // Test 1: Verify text.
    text := piece_table_get_text(pt, 0, 19)
    testing.expect_value(t, text, "The brown fox jumps")
    
    // Test 2: Verify tree structure.
    testing.expect(t, pt.root != nil, "Root should exist")
    testing.expect_value(t, pt.root.cumul_length, 19)
    
    // Test 3: Verify balance.
    testing.expect(t, pt.root.height <= 2, "Tree should remain balanced")
}

@(test)
line_tracking_test :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    pt := piece_table_init()
    
    // Setup multiline text.
    piece_table_insert(pt, "Line1\nLine2\nLine3", 0)
    
    // Test position to line/col.
    line, col := piece_table_pos_to_linecol(pt, 0)
    testing.expect_value(t, line, 0)
    testing.expect_value(t, col, 0)
    
    line, col = piece_table_pos_to_linecol(pt, 6)
    testing.expect_value(t, line, 1)
    testing.expect_value(t, col, 0)
    
    line, col = piece_table_pos_to_linecol(pt, 12)
    testing.expect_value(t, line, 2)
    testing.expect_value(t, col, 0)
    
    // Test line/col to position.
    pos := piece_table_linecol_to_pos(pt, 0, 4)
    testing.expect_value(t, pos, 4)  // 'Line1' last character.
    
    pos = piece_table_linecol_to_pos(pt, 1, 10)
    testing.expect_value(t, pos, 11)  // Clamped to end of line2.
    
    // Verify full line text.
    line_text := piece_table_get_line(pt, 1)
    testing.expect_value(t, line_text, "Line2\n")
}

@(test)
save_test :: proc(t: ^testing.T) {
    pt := piece_table_init()
    piece_table_insert(pt, "Test content", 0)
    ok := piece_table_save(pt, "testfile.txt")
    defer os.remove("testfile.txt")
    
    data, _ := os.read_entire_file("testfile.txt")
    testing.expect_value(t, string(data), "Test content")
}
