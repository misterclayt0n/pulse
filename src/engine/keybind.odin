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
	VISUAL_LINE,
	COMMAND,
	COMMAND_NORMAL,
}

Vim_State :: struct {
	commands:          [dynamic]u8,
	last_command:      string, // For repeating commands.
	command_normal:    bool, // Indicates whether command normal mode is active or not.
	normal_cmd_buffer: [dynamic]u8, // Stores commands like "dd".
}

vim_state_init :: proc(allocator := context.allocator) -> Vim_State {
	return Vim_State {
		commands          = make([dynamic]u8, 0, 1024, allocator),
		// TODO: This should store commands from before, not when I initialize the editor state.
		last_command      = "",
		command_normal    = false,
		normal_cmd_buffer = make([dynamic]u8, 0, 16, allocator), // Should never really pass 16 len.
	}
}

// REFACTOR? This code is ugly but sometimes ugly code is the one who works.
vim_state_update :: proc(p: ^Pulse, allocator := context.allocator) {
	assert(p.keymap.mode == .VIM, "Keybind mode must be set to vim in order to update it")

	#partial switch p.current_window.mode {
	case .NORMAL:
		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)

		// Default movements between all modes.
		// Only execute "normal" commands if command buffer is empty.
		// These are the single key motions basically.
		if len(p.keymap.vim_state.normal_cmd_buffer) == 0 {
			if press_and_repeat(.LEFT) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LEFT)
			if press_and_repeat(.RIGHT) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .RIGHT)
			if press_and_repeat(.UP) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .UP)
			if press_and_repeat(.DOWN) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .DOWN)
			if press_and_repeat(.DELETE) do buffer_delete_forward_char(p.current_window)
			if press_and_repeat(.HOME) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_START)
			if press_and_repeat(.END) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_END)

			// HJKL.
			if press_and_repeat(.H) {
				if ctrl_pressed do window_focus_left(p)
				else do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LEFT)
				window_update_cursors(p.current_window, .LEFT)
			}

			if press_and_repeat(.J) {
				if ctrl_pressed do window_focus_bottom(p)
				else if shift_pressed do buffer_join_lines(p.current_window)
				else do cursor_move(&p.current_window.cursor, p.current_window.buffer, .DOWN)
				window_update_cursors(p.current_window, .DOWN)
			}

			if press_and_repeat(.K) {
				if ctrl_pressed do window_focus_top(p)
				else do cursor_move(&p.current_window.cursor, p.current_window.buffer, .UP)
				window_update_cursors(p.current_window, .UP)
			}

			if press_and_repeat(.L) {
				if ctrl_pressed do window_focus_right(p)
				else do cursor_move(&p.current_window.cursor, p.current_window.buffer, .RIGHT)
				window_update_cursors(p.current_window, .RIGHT)
			}

			// Mode changing.
			// REFACTOR: These focus bindings kind of suck in my opinion.
			if press_and_repeat(.I) {
				if shift_pressed {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .FIRST_NON_BLANK)
					change_mode(p, .INSERT)
				} else do change_mode(p, .INSERT)
			}

			if press_and_repeat(.A) {
				if shift_pressed {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_END)
					append_right_motion(p)
				} else do append_right_motion(p)
			}

			if press_and_repeat(.V) {
				if shift_pressed {
					p.current_window.cursor.sel = p.current_window.cursor.pos
					change_mode(p, .VISUAL_LINE)
				} else {
					p.current_window.cursor.sel = p.current_window.cursor.pos
					change_mode(p, .VISUAL)
				}
			}

			if press_and_repeat(.ZERO) {
				cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_START)
				window_update_cursors(p.current_window, .LINE_START)
			} 

			if press_and_repeat(.B) {
				if shift_pressed {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .BIG_WORD_LEFT)
					window_update_cursors(p.current_window, .BIG_WORD_LEFT)
				} else {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .WORD_LEFT)
					window_update_cursors(p.current_window, .WORD_LEFT)
				} 
			}

			if press_and_repeat(.W) {
				if shift_pressed {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .BIG_WORD_RIGHT)
					window_update_cursors(p.current_window, .BIG_WORD_RIGHT)
				} 
				else if ctrl_pressed do window_remove_split(p)
				else {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .WORD_RIGHT)
					window_update_cursors(p.current_window, .WORD_RIGHT)
				} 
			}

			if press_and_repeat(.E) {
				if shift_pressed {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .BIG_WORD_END)
					window_update_cursors(p.current_window, .BIG_WORD_END)
				} 
				else {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .WORD_END)
					window_update_cursors(p.current_window, .WORD_END)
				} 
			}

			if press_and_repeat(.X) do buffer_delete_forward_char(p.current_window)
			if press_and_repeat(.S) {
				buffer_delete_forward_char(p.current_window)
				change_mode(p, .INSERT)
			}

			if press_and_repeat(.D) {
				if shift_pressed do buffer_delete_to_line_end(p.current_window)
			}

			if press_and_repeat(.C) {
				if shift_pressed {
					buffer_delete_to_line_end(p.current_window)
					change_mode(p, .INSERT)
				}
			}

			if press_and_repeat(.MINUS) {
				if shift_pressed {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .FIRST_NON_BLANK)
					window_update_cursors(p.current_window, .FIRST_NON_BLANK)
				} 
			}

			if press_and_repeat(.SEMICOLON) {
				if shift_pressed {
					change_mode(p, .COMMAND)
				} 
			}

			if press_and_repeat(.FOUR) {
				if shift_pressed {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_END)
					window_update_cursors(p.current_window, .LINE_END)
				} 
			}

			if press_and_repeat(.G) {
				if shift_pressed {
					cursor_move(&p.current_window.cursor, p.current_window.buffer, .FILE_END)
					window_update_cursors(p.current_window, .FILE_END)
				} 
			}

			if press_and_repeat(.TAB) {
				if ctrl_pressed do window_switch_focus(p)
			}

			if press_and_repeat(.O) {
				if shift_pressed do insert_newline(p, true)
				else do insert_newline(p, false)
			}
		}

		if press_and_repeat(.F2) {
			using p.keymap.vim_state
			command_normal = !command_normal
		}

		// ESC clears the command buffer.
		if press_and_repeat(.ESCAPE) {
			p.current_window.cursor.color = CURSOR_COLOR
			clear(&p.keymap.vim_state.normal_cmd_buffer)
			clear(&p.current_window.additional_cursors)
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
			if is_command(p.current_window, cmd_str) {
				execute_normal_command(p, cmd_str)
				p.current_window.cursor.color = CURSOR_COLOR
				clear(&p.keymap.vim_state.normal_cmd_buffer)
			} else if !is_prefix_of_command(cmd_str) {
				// NOTE: Here we constantly clear the command buffer array if we cannot find a
				// valid command sequence, which include any normal command (h, j, k, l, etc).
				// Maybe some performance considerations should be made about
				// this, but for now (06/03/25) I have not seen any visual impacts.
				p.current_window.cursor.color = CURSOR_COLOR
				clear(&p.keymap.vim_state.normal_cmd_buffer)
			}
		}

	case .VISUAL:
		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

		// Exit to Normal Mode.
		if press_and_repeat(.ESCAPE) {
			p.current_window.mode = .NORMAL
			p.current_window.cursor.sel = 0 // Reset selection.
	        for rl.GetCharPressed() != 0 {} // Consume pending keys.
		}

		// Only execute "normal" commands if command buffer is empty.
		if len(p.keymap.vim_state.normal_cmd_buffer) == 0 {
			if press_and_repeat(.LEFT) || press_and_repeat(.H) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LEFT)
			if press_and_repeat(.RIGHT) || press_and_repeat(.L) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .RIGHT)
			if press_and_repeat(.UP) || press_and_repeat(.K) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .UP)
			if press_and_repeat(.DOWN) || press_and_repeat(.J) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .DOWN)
			if press_and_repeat(.HOME) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_START)
			if press_and_repeat(.END) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_END)
			if press_and_repeat(.B) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .WORD_LEFT)
			if press_and_repeat(.W) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .WORD_RIGHT)
			if press_and_repeat(.E) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .WORD_END)
			if press_and_repeat(.ZERO) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_START)
			if press_and_repeat(.FOUR) && shift_pressed do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_END)
			if press_and_repeat(.MINUS) && shift_pressed do cursor_move(&p.current_window.cursor, p.current_window.buffer, .FIRST_NON_BLANK)
			if press_and_repeat(.G) && shift_pressed do cursor_move(&p.current_window.cursor, p.current_window.buffer, .FILE_END)
		}

		// Selection operations.
		if press_and_repeat(.D) || press_and_repeat(.X) {
			buffer_delete_selection(p.current_window)
			change_mode(p, .NORMAL)
			clear(&p.keymap.vim_state.normal_cmd_buffer)
	        for rl.GetCharPressed() != 0 {} // Consume pending keys.
		}

		if press_and_repeat(.C) {
			buffer_delete_selection(p.current_window)
			change_mode(p, .INSERT)
			clear(&p.keymap.vim_state.normal_cmd_buffer)
	        for rl.GetCharPressed() != 0 {} // Consume pending keys.
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
			if is_command(p.current_window, cmd_str) {
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

	case .VISUAL_LINE:
		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

		// Exit to Normal Mode.
		if press_and_repeat(.ESCAPE) {
			p.current_window.mode = .NORMAL
			p.current_window.cursor.sel = 0 // Reset selection.
	        for rl.GetCharPressed() != 0 {} // Consume pending keys.
		}

		// Movement here is similar to VISUAL but line-wise.
		if press_and_repeat(.UP) || press_and_repeat(.K) {
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .UP)
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_START) // Snap to line start.
		}
		if press_and_repeat(.DOWN) || press_and_repeat(.J) {
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .DOWN)
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_END) // Snap to line end.
		}
		if press_and_repeat(.HOME) || press_and_repeat(.ZERO) {
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_START)
		}
		if press_and_repeat(.END) || (press_and_repeat(.FOUR) && shift_pressed) {
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_END)
		}
		if press_and_repeat(.B) {
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .WORD_LEFT)
		}
		if press_and_repeat(.W) {
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .WORD_RIGHT)
		}
		if press_and_repeat(.E) {
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .WORD_END)
		}
		if press_and_repeat(.MINUS) && shift_pressed {
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .FIRST_NON_BLANK)
		}
		if press_and_repeat(.G) && shift_pressed {
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .FILE_END)
		}

		// Operations on selected lines.
		if press_and_repeat(.D) {
			buffer_delete_visual_line_selection(p.current_window)
			change_mode(p, .NORMAL)
		}
		if press_and_repeat(.C) {
			buffer_delete_visual_line_selection(p.current_window)
			change_mode(p, .INSERT)
		}

	case .INSERT:
		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)

		if press_and_repeat(.ESCAPE) do change_mode(p, .NORMAL)

		// Default movements between all modes.
		if press_and_repeat(.LEFT) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LEFT)
		if press_and_repeat(.RIGHT) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .RIGHT)
		if press_and_repeat(.UP) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .UP)
		if press_and_repeat(.DOWN) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .DOWN)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(p.current_window)
		if press_and_repeat(.HOME) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_START)
		if press_and_repeat(.END) do cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_END)
		if press_and_repeat(.TAB) do buffer_insert_tab(p.current_window, allocator)

		if press_and_repeat(.ENTER) do buffer_insert_newline(p.current_window, allocator)
		if press_and_repeat(.BACKSPACE) {
			if ctrl_pressed || alt_pressed do buffer_delete_word(p.current_window)
			else do buffer_delete_char(p.current_window)
		}

		key := rl.GetCharPressed()
		for key != 0 {
			r := rune(key)

			if r == '}' || r == ')' || r == ']' {
				buffer_insert_closing_delimiter(p.current_window, r, allocator)
			} else {
				buffer_insert_char(p.current_window, r)
			}
			key = rl.GetCharPressed()
		}
		clear(&p.keymap.vim_state.normal_cmd_buffer)

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
		if press_and_repeat(.LEFT) do cursor_move(&command_window.cursor, command_window.buffer, .LEFT)
		if press_and_repeat(.RIGHT) do cursor_move(&command_window.cursor, command_window.buffer, .RIGHT)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(command_window)
		if press_and_repeat(.HOME) do cursor_move(&command_window.cursor, command_window.buffer, .LINE_START)
		if press_and_repeat(.END) do cursor_move(&command_window.cursor, command_window.buffer, .LINE_END)

		if ctrl_pressed {
			if press_and_repeat(.B) do cursor_move(&command_window.cursor, command_window.buffer, .LEFT)
			if press_and_repeat(.F) do cursor_move(&command_window.cursor, command_window.buffer, .RIGHT)
			if press_and_repeat(.E) do cursor_move(&command_window.cursor, command_window.buffer, .LINE_END)
			if press_and_repeat(.A) do cursor_move(&command_window.cursor, command_window.buffer, .LINE_START)
			if press_and_repeat(.K) do buffer_delete_to_line_end(command_window)
		}

		if alt_pressed {
			if press_and_repeat(.F) do cursor_move(&command_window.cursor, command_window.buffer, .WORD_RIGHT)
			if press_and_repeat(.B) do cursor_move(&command_window.cursor, command_window.buffer, .WORD_LEFT)
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
		if press_and_repeat(.H) || press_and_repeat(.LEFT) do cursor_move(&command_window.cursor, command_window.buffer, .LEFT)
		if press_and_repeat(.L) || press_and_repeat(.RIGHT) do cursor_move(&command_window.cursor, command_window.buffer, .RIGHT)
		if press_and_repeat(.B) do cursor_move(&command_window.cursor, command_window.buffer, .WORD_LEFT)
		if press_and_repeat(.W) do cursor_move(&command_window.cursor, command_window.buffer, .WORD_RIGHT)
		if press_and_repeat(.E) do cursor_move(&command_window.cursor, command_window.buffer, .WORD_END)
		if press_and_repeat(.ZERO) do cursor_move(&command_window.cursor, command_window.buffer, .LINE_START)
		if press_and_repeat(.X) do buffer_delete_forward_char(command_window)

		if shift_pressed {
			if press_and_repeat(.I) {
				cursor_move(&command_window.cursor, command_window.buffer, .FIRST_NON_BLANK)
				change_mode(p, .COMMAND)
			}

			if press_and_repeat(.A) {
				cursor_move(&command_window.cursor, command_window.buffer, .LINE_END)
				append_right_motion(p)
			}

			if press_and_repeat(.FOUR) do cursor_move(&command_window.cursor, command_window.buffer, .LINE_END)

			if press_and_repeat(.D) do buffer_delete_to_line_end(command_window)
			if press_and_repeat(.C) {
				buffer_delete_to_line_end(command_window)
				change_mode(p, .COMMAND)
			}

			if press_and_repeat(.MINUS) do cursor_move(&command_window.cursor, command_window.buffer, .FIRST_NON_BLANK)
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
	using p.current_window

	#partial switch target_mode {
	case .NORMAL:
		if mode == .INSERT {
			mode = .NORMAL
			cursor_move(&p.current_window.cursor, p.current_window.buffer, .LEFT)
		}

		if mode == .COMMAND || mode == .VISUAL || mode == .VISUAL_LINE {
			mode = .NORMAL
		}
	case .INSERT:
		mode = .INSERT
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
			cursor_move(&p.status_line.command_window.cursor, p.status_line.command_window.buffer, .LEFT)
		}
	case .VISUAL:
		mode = .VISUAL
		// Only set sel = pos if sel hasn't been set (e.g. entering via 'v')
		if cursor.sel == 0 do cursor.sel = cursor.pos
	case .VISUAL_LINE:
		current_line := cursor.line
		line_start := buffer.line_starts[current_line]
		line_end := len(buffer.data)
		if current_line < len(buffer.line_starts) - 1 {
			line_end = buffer.line_starts[current_line + 1] - 1 // Exclude the newline.
		}

		cursor.sel = line_start
		cursor.pos = line_end

		mode = .VISUAL_LINE
	}
}

get_out_of_command_mode :: proc(p: ^Pulse) {
	assert(p.current_window.mode == .COMMAND || p.current_window.mode == .COMMAND_NORMAL)
	p.current_window.mode = .NORMAL
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
		cursor_move(&p.current_window.cursor, p.current_window.buffer, .LINE_START)
		buffer_insert_char(p.current_window, '\n')
		cursor_move(&p.current_window.cursor, p.current_window.buffer, .UP)
		buffer_update_indentation(p.current_window)
		change_mode(p, .INSERT)
	} else {
		current_line := p.current_window.cursor.line
		current_line_start := p.current_window.buffer.line_starts[current_line]
		current_line_length := buffer_line_length(p.current_window.buffer, current_line)

		// Move to true end of current line's content (before any existing newline)
		p.current_window.cursor.pos = current_line_start + current_line_length
		buffer_insert_char(p.current_window, '\n')
		buffer_update_indentation(p.current_window)
		change_mode(p, .INSERT)
	}
}
