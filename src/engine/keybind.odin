package engine

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Keymap_Mode :: enum {
	VIM,
}

Keymap :: struct {
	mode:      Keymap_Mode,
	vim_state: Vim_State,
}

keymap_init :: proc(mode: Keymap_Mode, allocator := context.allocator) -> Keymap {
	return Keymap{mode = .VIM, vim_state = vim_state_init(allocator)}
}

keymap_update :: proc(p: ^Pulse, allocator := context.allocator) {
	vim_state_update(p)
}

//
// Vim
//

Vim_Mode :: enum {
	NORMAL,
	INSERT,
	VISUAL,
	COMMAND,
	COMMAND_NORMAL,
}

Vim_State :: struct {
	commands:          [dynamic]u8,
	last_command:      string, // For repeating commands.
	mode:              Vim_Mode,
	command_normal:    bool, // Indicates whether command normal mode is active or not.
	normal_cmd_buffer: [dynamic]u8, // Stores commands like "dd".
}

vim_state_init :: proc(allocator := context.allocator) -> Vim_State {
	return Vim_State {
		commands       = make([dynamic]u8, 0, 1024, allocator),
		// TODO: This should store commands from before, not when I initialize the editor state.
		last_command   = "",
		mode           = .NORMAL,
		command_normal = false,
		normal_cmd_buffer = make([dynamic]u8, 0, 16, allocator) // Should never really pass 16 len.
	}
}

vim_state_update :: proc(p: ^Pulse, allocator := context.allocator) {
	assert(p.keymap.mode == .VIM, "Keybind mode must be set to vim in order to update it")

	#partial switch p.keymap.vim_state.mode {
	case .NORMAL:
		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)

		// Default movements between all modes.
		if press_and_repeat(.LEFT) || press_and_repeat(.H) do buffer_move_cursor(p.current_window, .LEFT)
		if press_and_repeat(.RIGHT) || press_and_repeat(.L) do buffer_move_cursor(p.current_window, .RIGHT)
		if press_and_repeat(.UP) || press_and_repeat(.K) do buffer_move_cursor(p.current_window, .UP)
		if press_and_repeat(.DOWN) || press_and_repeat(.J) do buffer_move_cursor(p.current_window, .DOWN)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(p.current_window)
		if press_and_repeat(.HOME) do buffer_move_cursor(p.current_window, .LINE_START)
		if press_and_repeat(.END) do buffer_move_cursor(p.current_window, .LINE_END)

		// Mode changing.
		if press_and_repeat(.I) do change_mode(p, .INSERT)
		if press_and_repeat(.A) do append_right_motion(p)

		if press_and_repeat(.ZERO) do buffer_move_cursor(p.current_window, .LINE_START)
		if press_and_repeat(.B) do buffer_move_cursor(p.current_window, .WORD_LEFT)
		if press_and_repeat(.W) do buffer_move_cursor(p.current_window, .WORD_RIGHT)
		if press_and_repeat(.E) do buffer_move_cursor(p.current_window, .WORD_END)
		if press_and_repeat(.X) do buffer_delete_forward_char(p.current_window)
		if press_and_repeat(.S) {
			buffer_delete_forward_char(p.current_window)
			change_mode(p, .INSERT)
		}

		if shift_pressed {
			if press_and_repeat(.I) {
				buffer_move_cursor(p.current_window, .FIRST_NON_BLANK)
				change_mode(p, .INSERT)
			}

			if press_and_repeat(.A) {
				buffer_move_cursor(p.current_window, .LINE_END)
				append_right_motion(p)
			}

			if press_and_repeat(.D) do buffer_delete_to_line_end(p.current_window)
			if press_and_repeat(.C) {
				buffer_delete_to_line_end(p.current_window)
				change_mode(p, .INSERT)
			}
			if press_and_repeat(.MINUS) do buffer_move_cursor(p.current_window, .FIRST_NON_BLANK)

			if press_and_repeat(.SEMICOLON) do change_mode(p, .COMMAND)
			if press_and_repeat(.FOUR) do buffer_move_cursor(p.current_window, .LINE_END)
			if press_and_repeat(.G) do buffer_move_cursor(p.current_window, .FILE_END)
		}

		if ctrl_pressed {
			// REFACTOR: These bindings kind of suck in my opinion.
			if rl.IsKeyPressed(.H) do window_focus_left(p)
			if rl.IsKeyPressed(.L) do window_focus_right(p)
			if rl.IsKeyPressed(.J) do window_focus_bottom(p)
			if rl.IsKeyPressed(.K) do window_focus_top(p)
			if rl.IsKeyPressed(.TAB) do window_switch_focus(p)
			if rl.IsKeyPressed(.W) do window_remove_split(p)
		}

		if press_and_repeat(.O) {
			if shift_pressed do insert_newline(p, true)
			else do insert_newline(p, false)
		}

		if press_and_repeat(.I) {
			if shift_pressed {
				buffer_move_cursor(p.current_window, .FIRST_NON_BLANK)
				change_mode(p, .INSERT)
			} else {
				change_mode(p, .INSERT)
			}
		}

		if press_and_repeat(.F2) {
			using p.keymap.vim_state
			command_normal = !command_normal
		}

		// 
		// Command buffer evaluation.
		//

		key := rl.GetCharPressed()
		for key != 0 {
			append(&p.keymap.vim_state.normal_cmd_buffer, u8(key))
			key = rl.GetCharPressed()
		}

		if len(p.keymap.vim_state.normal_cmd_buffer) > 0 {
			cmd_str := strings.clone_from_bytes(p.keymap.vim_state.normal_cmd_buffer[:], allocator)
			defer delete(cmd_str)

			// Check and execute the command
            if is_complete_command(cmd_str) {
                execute_normal_command(p, cmd_str)
                clear(&p.keymap.vim_state.normal_cmd_buffer)
            } else if !is_prefix_of_command(cmd_str) {
				// NOTE: Here we constantly clear the command buffer array if we cannot find a 
				// valid command sequence, which include any normal command (h, j, k, l, etc). 
			    // Maybe some performance considerations should be made about 
				// this, but for now (06/03/25) I have not seen any visual impacts.
                clear(&p.keymap.vim_state.normal_cmd_buffer)
            }
		}

	case .INSERT:
		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)

		// Default movements between all modes.
		if press_and_repeat(.LEFT) do buffer_move_cursor(p.current_window, .LEFT)
		if press_and_repeat(.RIGHT) do buffer_move_cursor(p.current_window, .RIGHT)
		if press_and_repeat(.UP) do buffer_move_cursor(p.current_window, .UP)
		if press_and_repeat(.DOWN) do buffer_move_cursor(p.current_window, .DOWN)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(p.current_window)
		if press_and_repeat(.HOME) do buffer_move_cursor(p.current_window, .LINE_START)
		if press_and_repeat(.END) do buffer_move_cursor(p.current_window, .LINE_END)

		if press_and_repeat(.ESCAPE) do change_mode(p, .NORMAL)
		if press_and_repeat(.ENTER) do buffer_insert_char(p.current_window, '\n')
		if press_and_repeat(.BACKSPACE) {
			if ctrl_pressed || alt_pressed do buffer_delete_word(p.current_window)
			else do buffer_delete_char(p.current_window)
		}

		key := rl.GetCharPressed()
		for key != 0 {
			buffer_insert_char(p.current_window, rune(key))
			key = rl.GetCharPressed()
		}
	case .COMMAND:
		using p.status_line
		key := rl.GetCharPressed()

		if rl.IsKeyPressed(.ENTER) {
			execute_command(p)
			get_out_of_command_mode(p)
		}

		// Clear message when first entering command mode
		if !(p.status_line.message_timestamp > 0) do status_line_clear_message(&p.status_line)

		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)

		if rl.IsKeyPressed(.ESCAPE) {
			// Refactor this logic here
			if p.keymap.vim_state.command_normal do change_mode(p, .COMMAND_NORMAL)
			else do get_out_of_command_mode(p)
		}

		// Handle cursor movement.
		if press_and_repeat(.LEFT) do buffer_move_cursor(command_window, .LEFT)
		if press_and_repeat(.RIGHT) do buffer_move_cursor(command_window, .RIGHT)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(command_window)
		if press_and_repeat(.HOME) do buffer_move_cursor(command_window, .LINE_START)
		if press_and_repeat(.END) do buffer_move_cursor(command_window, .LINE_END)

		// NOTE: Maybe I should some sort of flag for these emacs bindings inside command mode.
		// Something like emacs_mode: bool, and then I could sort of switch between using the emacs bindings inside
		// command mode or just press esc and go for the normal mode of command mode.
		if ctrl_pressed {
			if press_and_repeat(.B) do buffer_move_cursor(command_window, .LEFT)
			if press_and_repeat(.F) do buffer_move_cursor(command_window, .RIGHT)
			if press_and_repeat(.E) do buffer_move_cursor(command_window, .LINE_END)
			if press_and_repeat(.A) do buffer_move_cursor(command_window, .LINE_START)
			if press_and_repeat(.K) do buffer_delete_to_line_end(command_window)
		}

		if alt_pressed {
			if press_and_repeat(.F) do buffer_move_cursor(command_window, .WORD_RIGHT)
			if press_and_repeat(.B) do buffer_move_cursor(command_window, .WORD_LEFT)
		}

		if press_and_repeat(.BACKSPACE) {
			if ctrl_pressed || alt_pressed do buffer_delete_word(command_window)
			else do buffer_delete_char(command_window)
		}

		for key != 0 {
			if is_char_supported(rune(key)) do buffer_insert_char(command_window, rune(key))
			key = rl.GetCharPressed()
		}
	case .COMMAND_NORMAL:
		using p.status_line

		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

		if press_and_repeat(.ESCAPE) {
			get_out_of_command_mode(p)
		}

		// Movement commands for command buffer.
		if press_and_repeat(.H) || press_and_repeat(.LEFT) do buffer_move_cursor(command_window, .LEFT)
		if press_and_repeat(.L) || press_and_repeat(.RIGHT) do buffer_move_cursor(command_window, .RIGHT)
		if press_and_repeat(.B) do buffer_move_cursor(command_window, .WORD_LEFT)
		if press_and_repeat(.W) do buffer_move_cursor(command_window, .WORD_RIGHT)
		if press_and_repeat(.E) do buffer_move_cursor(command_window, .WORD_END)
		if press_and_repeat(.ZERO) do buffer_move_cursor(command_window, .LINE_START)
		if press_and_repeat(.X) do buffer_delete_forward_char(command_window)

		if shift_pressed {
			if press_and_repeat(.I) {
				buffer_move_cursor(command_window, .FIRST_NON_BLANK)
				change_mode(p, .COMMAND)
			}

			if press_and_repeat(.A) {
				buffer_move_cursor(command_window, .LINE_END)
				append_right_motion(p)
			}

			if press_and_repeat(.FOUR) do buffer_move_cursor(command_window, .LINE_END)

			if press_and_repeat(.D) do buffer_delete_to_line_end(command_window)
			if press_and_repeat(.C) {
				buffer_delete_to_line_end(command_window)
				change_mode(p, .COMMAND)
			}

			if press_and_repeat(.MINUS) do buffer_move_cursor(command_window, .FIRST_NON_BLANK)
		}

		if press_and_repeat(.I) do change_mode(p, .COMMAND)
		if press_and_repeat(.A) {
			window := p.status_line.command_window
			buffer := p.status_line.command_window.buffer

			current_line_end := len(buffer.data)
			if window.cursor.line < len(buffer.line_starts) - 1 {
				current_line_end = buffer.line_starts[window.cursor.line + 1] - 1
			}

			// Only move right if we're not already at the end of the line.
			if window.cursor.pos < current_line_end {
				n_bytes := next_rune_length(buffer.data[:], window.cursor.pos)
				window.cursor.pos += n_bytes
			}

			change_mode(p, .COMMAND)
		}
	}
}

//
// Mode switching
//

change_mode :: proc(p: ^Pulse, target_mode: Vim_Mode) {
	using p.keymap.vim_state

	#partial switch target_mode {
	case .NORMAL:
		if mode == .INSERT {
			mode = .NORMAL
			buffer_move_cursor(p.current_window, .LEFT)
		}

		if mode == .COMMAND {
			mode = .NORMAL
		}
	case .INSERT:
		if mode == .NORMAL do mode = .INSERT
	case .COMMAND:
		if mode == .NORMAL {
			status_line_clear_message(&p.status_line)
			mode = .COMMAND
			clear(&p.status_line.command_window.buffer.data)
			append(&p.status_line.command_window.buffer.data, ' ') // Add an initial space.
			p.status_line.command_window.cursor.pos = 0
		}

		if mode == .COMMAND_NORMAL do mode = .COMMAND
	case .COMMAND_NORMAL:
		assert(mode == .COMMAND, "We can only enter command normal mode from command insert mode")
		status_line_clear_message(&p.status_line)
		if mode == .COMMAND {
			mode = .COMMAND_NORMAL
			buffer_move_cursor(p.status_line.command_window, .LEFT)
		}

	}
}

get_out_of_command_mode :: proc(p: ^Pulse) {
	assert(p.keymap.vim_state.mode == .COMMAND || p.keymap.vim_state.mode == .COMMAND_NORMAL)
	p.keymap.vim_state.mode = .NORMAL
	clear(&p.status_line.command_window.buffer.data)
	p.status_line.command_window.cursor.pos = 0
}

append_right_motion :: proc(p: ^Pulse) {
	current_line_end := len(p.current_window.buffer.data)
	if p.current_window.cursor.line < len(p.current_window.buffer.line_starts) - 1 {
		current_line_end =
			p.current_window.buffer.line_starts[p.current_window.cursor.line + 1] - 1
	}

	// Only move right if we're not already at the end of the line.
	if p.current_window.cursor.pos < current_line_end {
		n_bytes := next_rune_length(p.current_window.buffer.data[:], p.current_window.cursor.pos)
		p.current_window.cursor.pos += n_bytes
	}

	change_mode(p, .INSERT)
}

//
// Helpers
//

press_and_repeat :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}

@(private)
insert_newline :: proc(p: ^Pulse, above: bool) {
	if above {
		buffer_move_cursor(p.current_window, .LINE_START)
		buffer_insert_char(p.current_window, '\n')
		buffer_move_cursor(p.current_window, .UP)
		change_mode(p, .INSERT)
	} else {
		current_line := p.current_window.cursor.line
		current_line_start := p.current_window.buffer.line_starts[current_line]
		current_line_length := buffer_line_length(p.current_window.buffer, current_line)

		// Move to true end of current line's content (before any existing newline)
		p.current_window.cursor.pos = current_line_start + current_line_length
		buffer_insert_char(p.current_window, '\n')
		change_mode(p, .INSERT)
	}
}
