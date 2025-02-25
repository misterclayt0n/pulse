package engine

Vim_Mode :: enum {
	NORMAL,
	INSERT,
	VISUAL,
	CLI,
}

Command_Buffer :: struct {
	commands:     [dynamic]u8, // Stores commands like "dd".
	last_command: string       // For repeating commands.
}

command_buffer_init :: proc(allocator := context.allocator, initial_cap := 1024) -> Command_Buffer {
	return Command_Buffer {
		commands = make([dynamic]u8, 0, 1024, allocator),
		// TODO: This should store commands from before, not when I initialize the editor state.
		last_command = "",
	}
}

change_mode :: proc(buffer: ^Buffer, current_mode: ^Vim_Mode, target_mode: Vim_Mode) {
	#partial switch target_mode {
	case .NORMAL:
		if current_mode^ == .INSERT {
			current_mode^ = .NORMAL
			buffer_move_cursor(buffer, .LEFT)
			return
		}
	case .INSERT:
		if current_mode^ == .NORMAL do current_mode ^ = .INSERT
	}
}

