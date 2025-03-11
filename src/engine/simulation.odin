package engine

Operations :: []string {
	"insert 'a'",
	"move .DOWN",
	"delete_char"
}

buffer_clone :: proc(buffer: ^Buffer, allocator := context.allocator) -> ^Buffer {
	clone := new(Buffer, allocator)
	clone^ = buffer^ // Shallow copy.
	clone.data = make([dynamic]u8, len(buffer.data), allocator)
	copy(clone.data[:], buffer.data[:])
	clone.line_starts = make([dynamic]int, len(buffer.line_starts), allocator)
	copy(clone.line_starts[:], buffer.line_starts[:])
	return clone
}

window_clone :: proc(window: ^Window, allocator := context.allocator) -> ^Window {
	clone := new(Window, allocator)
	clone^ = window^
	clone.buffer = buffer_clone(window.buffer, allocator)
	return clone
}

pulse_clone :: proc(p: ^Pulse, allocator := context.allocator) -> ^Pulse {
	clone := new(Pulse, allocator)
	clone^ = p^
	clone.windows = make([dynamic]Window, len(p.windows), allocator)

	// Deep copy of windows
	for i in 0..<len(p.windows) {
		clone.windows[i] = window_clone(&p.windows[i], allocator)^
	}
	clone.current_window = p.current_window

    // Clone status line.
    clone.status_line.command_window = window_clone(p.status_line.command_window, allocator)

    return clone
}

simulate_operation :: proc(sim_pulse: ^Pulse, operation: string) {
    switch operation {
    case "insert 'a'":
        buffer_insert_char(sim_pulse.current_window, 'a') 
    case "move .DOWN":
        buffer_move_cursor(sim_pulse.current_window, .DOWN) 
    case "delete_char":
        buffer_delete_char(sim_pulse.current_window) 
    case:
        // Log unrecognized operation
    }
}

run_simulation :: proc(sim_pulse: ^Pulse, operations: []string) {
    for op in operations {
        simulate_operation(sim_pulse, op)
        // Optionally check assertions here, e.g., assert(sim_pulse.current_window.buffer.cursor.y >= 0)
    }
}
