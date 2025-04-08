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
	VISUAL_BLOCK,
	COMMAND,
	COMMAND_NORMAL,
}

Vim_State :: struct {
	commands:                [dynamic]u8,
	last_command:            string, // For repeating commands.
	command_normal:          bool, // Indicates whether command normal mode is active or not.
	normal_cmd_buffer:       [dynamic]u8, // Stores commands like "dd".
	pattern_selection_start: int, // Start of the selection for pattern search
	pattern_selection_end:   int, // End of the selection for pattern search
}

vim_state_init :: proc(allocator := context.allocator) -> Vim_State {
	return Vim_State {
		commands                = make([dynamic]u8, 0, 1024, allocator),
		// TODO: This should store commands from before, not when I initialize the editor state.
		last_command            = "",
		command_normal          = false,
		normal_cmd_buffer       = make([dynamic]u8, 0, 16, allocator), // Should never really pass 16 len.
		pattern_selection_start = 0,
		pattern_selection_end   = 0,
	}
}

// REFACTOR? This code is ugly but sometimes ugly code is the one who works.
vim_state_update :: proc(p: ^Pulse, allocator := context.allocator) {
	assert(p.keymap.mode == .VIM, "Keybind mode must be set to vim in order to update it")

	#partial switch p.current_window.mode {
	case .NORMAL:
		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)

		// Default movements between all modes.
		// Only execute "normal" commands if command buffer is empty.
		// These are the single key motions basically.
		if len(p.keymap.vim_state.normal_cmd_buffer) == 0 {
			if press_and_repeat(.LEFT) do move_cursors(p.current_window, .LEFT)
			if press_and_repeat(.RIGHT) do move_cursors(p.current_window, .RIGHT)
			if press_and_repeat(.UP) do move_cursors(p.current_window, .UP)
			if press_and_repeat(.DOWN) do move_cursors(p.current_window, .DOWN)
			if press_and_repeat(.DELETE) do buffer_delete_forward_char(p.current_window)
			if press_and_repeat(.HOME) do move_cursors(p.current_window, .LINE_START)
			if press_and_repeat(.END) do move_cursors(p.current_window, .LINE_END)

			// HJKL.
			if press_and_repeat(.H) {
				if ctrl_pressed do window_focus_left(p)
				else do move_cursors(p.current_window, .LEFT)
			}

			if press_and_repeat(.J) {
				if ctrl_pressed do window_focus_bottom(p)
				else if shift_pressed do buffer_join_lines(p.current_window)
				else do move_cursors(p.current_window, .DOWN)
			}

			if press_and_repeat(.K) {
				if ctrl_pressed do window_focus_top(p)
				else do move_cursors(p.current_window, .UP)
			}

			if press_and_repeat(.L) {
				if ctrl_pressed do window_focus_right(p)
				else do move_cursors(p.current_window, .RIGHT)
			}

			// Mode changing.
			// REFACTOR: These focus bindings kind of suck in my opinion.
			if press_and_repeat(.I) {
				if shift_pressed {
					move_cursors(p.current_window, .FIRST_NON_BLANK)
					change_mode(p, .INSERT)
				} else do change_mode(p, .INSERT)
			}

			if press_and_repeat(.A) {
				if shift_pressed {
					move_cursors(p.current_window, .LINE_END)
					append_right_motion(p)
				} else do append_right_motion(p)
			}

			if press_and_repeat(.V) {
				if shift_pressed {
					p.current_window.cursor.sel = p.current_window.cursor.pos
					change_mode(p, .VISUAL_LINE)
				} else if ctrl_pressed {
					change_mode(p, .VISUAL_BLOCK)
				} else {
					p.current_window.cursor.sel = p.current_window.cursor.pos
					change_mode(p, .VISUAL)
				}
			}

			if press_and_repeat(.ZERO) {
				move_cursors(p.current_window, .LINE_START)
			}

			if press_and_repeat(.B) {
				if shift_pressed do move_cursors(p.current_window, .BIG_WORD_LEFT)
				else do move_cursors(p.current_window, .WORD_LEFT)
			}

			if press_and_repeat(.W) {
				if shift_pressed do move_cursors(p.current_window, .BIG_WORD_RIGHT)
				else if ctrl_pressed do window_remove_split(p)
				else do move_cursors(p.current_window, .WORD_RIGHT)
			}

			if press_and_repeat(.E) {
				if shift_pressed do move_cursors(p.current_window, .BIG_WORD_END)
				else do move_cursors(p.current_window, .WORD_END)
			}

			if press_and_repeat(.X) do buffer_delete_forward_char(p.current_window)
			if press_and_repeat(.S) {
				buffer_delete_forward_char(p.current_window)
				change_mode(p, .INSERT)
			}

			if press_and_repeat(.D) {
				if shift_pressed do buffer_delete_to_line_end(p.current_window)
				else if alt_pressed do add_multi_cursor_word(p, allocator)
			}

			if press_and_repeat(.C) {
				if shift_pressed {
					buffer_delete_to_line_end(p.current_window)
					change_mode(p, .INSERT)
				}
			}

			if press_and_repeat(.MINUS) {
				if shift_pressed do move_cursors(p.current_window, .FIRST_NON_BLANK)
			}

			if press_and_repeat(.SEMICOLON) {
				if shift_pressed do change_mode(p, .COMMAND)
			}

			if press_and_repeat(.FOUR) {
				if shift_pressed do move_cursors(p.current_window, .LINE_END)
			}

			if press_and_repeat(.G) {
				if shift_pressed do move_cursors(p.current_window, .FILE_END)
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
			p.current_window.multi_cursor_word = ""
			p.current_window.multi_cursor_active = false
			p.current_window.last_added_cursor_pos = -1
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
		alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)

		// Exit to Normal Mode.
		if press_and_repeat(.ESCAPE) do change_mode(p, .NORMAL)

		// Only execute "normal" commands if command buffer is empty.
		if len(p.keymap.vim_state.normal_cmd_buffer) == 0 {
			if press_and_repeat(.LEFT) || press_and_repeat(.H) do move_cursors(p.current_window, .LEFT)
			if press_and_repeat(.RIGHT) || press_and_repeat(.L) do move_cursors(p.current_window, .RIGHT)
			if press_and_repeat(.UP) || press_and_repeat(.K) do move_cursors(p.current_window, .UP)
			if press_and_repeat(.DOWN) || press_and_repeat(.J) do move_cursors(p.current_window, .DOWN)
			if press_and_repeat(.HOME) do move_cursors(p.current_window, .LINE_START)
			if press_and_repeat(.END) do move_cursors(p.current_window, .LINE_END)
			if press_and_repeat(.B) do move_cursors(p.current_window, .WORD_LEFT)
			if press_and_repeat(.W) do move_cursors(p.current_window, .WORD_RIGHT)
			if press_and_repeat(.E) do move_cursors(p.current_window, .WORD_END)
			if press_and_repeat(.ZERO) do move_cursors(p.current_window, .LINE_START)
			if press_and_repeat(.FOUR) && shift_pressed do move_cursors(p.current_window, .LINE_END)
			if press_and_repeat(.MINUS) && shift_pressed do move_cursors(p.current_window, .FIRST_NON_BLANK)
			if press_and_repeat(.G) && shift_pressed do move_cursors(p.current_window, .FILE_END)
		}

		// Selection operations.
		if press_and_repeat(.D) {
			if alt_pressed do add_multi_cursor_word(p, allocator)
			else do delete_visual(p, .NORMAL)
		}
		if press_and_repeat(.X) do delete_visual(p, .NORMAL)

		if press_and_repeat(.C) do delete_visual(p, .INSERT)
		if press_and_repeat(.S) {
			append(&p.keymap.vim_state.normal_cmd_buffer, "select")
	        cmd_str := strings.clone_from_bytes(p.keymap.vim_state.normal_cmd_buffer[:], context.temp_allocator)
	        defer delete(cmd_str)
	        if is_command(p.current_window, cmd_str) {
	            execute_normal_command(p, cmd_str)
	            clear(&p.keymap.vim_state.normal_cmd_buffer)
	        }
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
		if press_and_repeat(.ESCAPE) do change_mode(p, .NORMAL)

		// Movement here is similar to VISUAL but line-wise.
		if press_and_repeat(.UP) || press_and_repeat(.K) {
			move_cursors(p.current_window, .UP)
			move_cursors(p.current_window, .LINE_START) // Snap to line start.
		}
		if press_and_repeat(.DOWN) || press_and_repeat(.J) {
			move_cursors(p.current_window, .DOWN)
			move_cursors(p.current_window, .LINE_END) // Snap to line end.
		}
		if press_and_repeat(.HOME) || press_and_repeat(.ZERO) do move_cursors(p.current_window, .LINE_START)
		if press_and_repeat(.END) || (press_and_repeat(.FOUR) && shift_pressed) do move_cursors(p.current_window, .LINE_END)
		if press_and_repeat(.B) do move_cursors(p.current_window, .WORD_LEFT)
		if press_and_repeat(.W) do move_cursors(p.current_window, .WORD_RIGHT)
		if press_and_repeat(.E) do move_cursors(p.current_window, .WORD_END)
		if press_and_repeat(.MINUS) && shift_pressed {
			move_cursors(p.current_window, .FIRST_NON_BLANK)
		}
		if press_and_repeat(.G) && shift_pressed do move_cursors(p.current_window, .FILE_END)

		if press_and_repeat(.D) do delete_visual_line(p, .NORMAL)
		if press_and_repeat(.C) do delete_visual_line(p, .INSERT)
		
		if press_and_repeat(.S) {
			append(&p.keymap.vim_state.normal_cmd_buffer, "select")
	        cmd_str := strings.clone_from_bytes(p.keymap.vim_state.normal_cmd_buffer[:], context.temp_allocator)
	        defer delete(cmd_str)
	        if is_command(p.current_window, cmd_str) {
	            execute_normal_command(p, cmd_str)
	            clear(&p.keymap.vim_state.normal_cmd_buffer)
	        }
		}

	case .VISUAL_BLOCK:
		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

		if press_and_repeat(.ESCAPE) {
			change_mode(p, .NORMAL)
			for rl.GetCharPressed() != 0 {}
		}

		if press_and_repeat(.LEFT) || press_and_repeat(.H) do move_cursors(p.current_window, .LEFT)
		if press_and_repeat(.RIGHT) || press_and_repeat(.L) do move_cursors(p.current_window, .RIGHT)
		if press_and_repeat(.UP) || press_and_repeat(.K) do move_cursors(p.current_window, .UP)
		if press_and_repeat(.DOWN) || press_and_repeat(.J) do move_cursors(p.current_window, .DOWN)
		if press_and_repeat(.HOME) do move_cursors(p.current_window, .LINE_START)
		if press_and_repeat(.END) do move_cursors(p.current_window, .LINE_END)
		if press_and_repeat(.B) do move_cursors(p.current_window, .WORD_LEFT)
		if press_and_repeat(.W) do move_cursors(p.current_window, .WORD_RIGHT)
		if press_and_repeat(.E) do move_cursors(p.current_window, .WORD_END)
		if press_and_repeat(.ZERO) do move_cursors(p.current_window, .LINE_START)
		if press_and_repeat(.FOUR) && shift_pressed do move_cursors(p.current_window, .LINE_END)
		if press_and_repeat(.MINUS) && shift_pressed do move_cursors(p.current_window, .FIRST_NON_BLANK)
		if press_and_repeat(.G) && shift_pressed do move_cursors(p.current_window, .FILE_END)

		if press_and_repeat(.D) || press_and_repeat(.X) {
			buffer_delete_visual_block_selection(p.current_window)
			change_mode(p, .NORMAL)
		}
		if press_and_repeat(.C) {
			buffer_delete_visual_block_selection(p.current_window)
			ok := create_block_cursors(p, .START)
			if ok do change_mode(p, .INSERT)
		}

		// TODO: More cursor movement, just testing the idea for now.

		if press_and_repeat(.I) {
			ok := create_block_cursors(p, .START)
			if ok do change_mode(p, .INSERT)
		}

		if press_and_repeat(.A) {
			ok := create_block_cursors(p, .END)
			if ok {
				using p.current_window
				change_mode(p, .INSERT)
				// Move right after going to insert mode (main cursor)
				cursor.pos = buffer_get_pos_from_col(
					buffer,
					cursor.line,
					visual_block_anchor_col + 1,
				)
				cursor.col = cursor.pos - buffer.line_starts[cursor.line]
				cursor.preferred_col = cursor.col
			}
		}


	case .INSERT:
		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)

		if press_and_repeat(.ESCAPE) do change_mode(p, .NORMAL)

		// Default movements between all modes.
		if press_and_repeat(.LEFT) do move_cursors(p.current_window, .LEFT)
		if press_and_repeat(.RIGHT) do move_cursors(p.current_window, .RIGHT)
		if press_and_repeat(.UP) do move_cursors(p.current_window, .UP)
		if press_and_repeat(.DOWN) do move_cursors(p.current_window, .DOWN)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(p.current_window)
		if press_and_repeat(.HOME) do move_cursors(p.current_window, .LINE_START)
		if press_and_repeat(.END) do move_cursors(p.current_window, .LINE_END)
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
			p.status_line.current_prompt = ""
		}

		// Clear message when first entering command mode
		if !(p.status_line.message_timestamp > 0) do status_line_clear_message(&p.status_line)

		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)

		if rl.IsKeyPressed(.ESCAPE) {
			// Refactor this logic here
			if p.keymap.vim_state.command_normal do change_mode(p, .COMMAND_NORMAL)
			else {
				 get_out_of_command_mode(p) 
				 p.status_line.current_prompt = ""
			}
		}

		// Handle cursor movement.
		if press_and_repeat(.LEFT) do move_cursors(command_window, .LEFT)
		if press_and_repeat(.RIGHT) do move_cursors(command_window, .RIGHT)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(command_window)
		if press_and_repeat(.HOME) do move_cursors(command_window, .LINE_START)
		if press_and_repeat(.END) do move_cursors(command_window, .LINE_END)

		if ctrl_pressed {
			if press_and_repeat(.B) do move_cursors(command_window, .LEFT)
			if press_and_repeat(.F) do move_cursors(command_window, .RIGHT)
			if press_and_repeat(.E) do move_cursors(command_window, .LINE_END)
			if press_and_repeat(.A) do move_cursors(command_window, .LINE_START)
			if press_and_repeat(.K) do buffer_delete_to_line_end(command_window)
		}

		if alt_pressed {
			if press_and_repeat(.F) do move_cursors(command_window, .WORD_RIGHT)
			if press_and_repeat(.B) do move_cursors(command_window, .WORD_LEFT)
		}

		if press_and_repeat(.BACKSPACE) {
			if ctrl_pressed || alt_pressed do buffer_delete_word(command_window)
			else do buffer_delete_char(command_window)
		}

		for key != 0 {
			if is_char_supported(rune(key)) do buffer_insert_char(command_window, rune(key))
			key = rl.GetCharPressed()
		}

		if p.keymap.vim_state.last_command == "select" {
		    cmd := string(p.status_line.command_window.buffer.data[:])
	        start := p.keymap.vim_state.pattern_selection_start
	        end := p.keymap.vim_state.pattern_selection_end
	        if start < end && end <= len(p.current_window.buffer.data) {
	            selected_text := p.current_window.buffer.data[start:end]
	            clear(&p.current_window.temp_match_ranges)
	            if len(cmd) > 0 {
	                p.current_window.temp_match_ranges = find_all_occurrences(selected_text, cmd)
	            }
	        } else {
	            clear(&p.current_window.temp_match_ranges)
	        }
		}
		
	case .COMMAND_NORMAL:
		using p.status_line

		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

		if press_and_repeat(.ESCAPE) {
			get_out_of_command_mode(p)
		}

		// Movement commands for command buffer.
		if press_and_repeat(.H) || press_and_repeat(.LEFT) do move_cursors(command_window, .LEFT)
		if press_and_repeat(.L) || press_and_repeat(.RIGHT) do move_cursors(command_window, .RIGHT)
		if press_and_repeat(.B) do move_cursors(command_window, .WORD_LEFT)
		if press_and_repeat(.W) do move_cursors(command_window, .WORD_RIGHT)
		if press_and_repeat(.E) do move_cursors(command_window, .WORD_END)
		if press_and_repeat(.ZERO) do move_cursors(command_window, .LINE_START)
		if press_and_repeat(.X) do buffer_delete_forward_char(command_window)

		if shift_pressed {
			if press_and_repeat(.I) {
				move_cursors(command_window, .FIRST_NON_BLANK)
				change_mode(p, .COMMAND)
			}

			if press_and_repeat(.A) {
				move_cursors(command_window, .LINE_END)
				append_right_motion(p)
			}

			if press_and_repeat(.FOUR) do move_cursors(command_window, .LINE_END)

			if press_and_repeat(.D) do buffer_delete_to_line_end(command_window)
			if press_and_repeat(.C) {
				buffer_delete_to_line_end(command_window)
				change_mode(p, .COMMAND)
			}

			if press_and_repeat(.MINUS) do move_cursors(command_window, .FIRST_NON_BLANK)
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
			move_cursors(p.current_window, .LEFT)
		}

		mode = .NORMAL
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
			move_cursors(p.status_line.command_window, .LEFT)
		}
	case .VISUAL:
		mode = .VISUAL
		cursor.sel = cursor.pos

		for &c in additional_cursors {
			c.sel = c.pos
		}

	case .VISUAL_LINE:
		current_line := cursor.line
		line_start := buffer.line_starts[current_line]
		line_end := len(buffer.data)
		if current_line < len(buffer.line_starts) - 1 {
			line_end = buffer.line_starts[current_line + 1] - 1 // Exclude the newline.
		}

		cursor.sel = line_start
		cursor.pos = line_end

		for &c in additional_cursors {
			c_line := c.line
			c_line_start := buffer.line_starts[c_line]
			c_line_end := len(buffer.data)
			if c_line < len(buffer.line_starts) - 1 {
				c_line_end = buffer.line_starts[c_line + 1] - 1
			}
			c.sel = c_line_start
			c.pos = c_line_end
		}

		mode = .VISUAL_LINE
	case .VISUAL_BLOCK:
		visual_block_anchor_line = cursor.line
		visual_block_anchor_col =
			cursor.preferred_col if cursor.preferred_col != -1 else cursor.col
		clear(&additional_cursors)
		mode = .VISUAL_BLOCK
	}
}

get_out_of_command_mode :: proc(p: ^Pulse) {
	assert(p.current_window.mode == .COMMAND || p.current_window.mode == .COMMAND_NORMAL || p.current_window.mode == .VISUAL)
	if p.keymap.vim_state.last_command == "select" { }
	else do p.current_window.mode = .NORMAL
	clear(&p.status_line.command_window.buffer.data)
	p.status_line.command_window.cursor.pos = 0
    p.keymap.vim_state.last_command = "" // Clear last command buffer.
    clear(&p.keymap.vim_state.normal_cmd_buffer)
    clear(&p.current_window.temp_match_ranges) 
}

append_right_motion :: proc(p: ^Pulse) {
	using p.current_window

	current_line_end := len(buffer.data)
	if cursor.line < len(buffer.line_starts) - 1 {
		current_line_end = buffer.line_starts[cursor.line + 1] - 1
	}

	// Only move right if we're not already at the end of the line.
	if cursor.pos < current_line_end {
		n_bytes := next_rune_length(buffer.data[:], cursor.pos)
		cursor.pos += n_bytes
		for &c in additional_cursors {
			c.pos += n_bytes
		}
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
insert_newline :: proc(p: ^Pulse, above: bool, allocator := context.allocator) {
	window := p.current_window
	cursors := get_sorted_cursors(window, context.temp_allocator)
	defer delete(cursors, context.temp_allocator)

	if above {
		for cursor_ptr in cursors {
			cursor_ptr.pos = window.buffer.line_starts[cursor_ptr.line]
			adjust_cursors(cursors, cursor_ptr, cursor_ptr.pos, false, 0) // No byte adjustment, just sync.

			// Insert newline at this position.
			resize(&window.buffer.data, len(window.buffer.data) + 1)
			if cursor_ptr.pos < len(window.buffer.data) - 1 {
				copy(window.buffer.data[cursor_ptr.pos + 1:], window.buffer.data[cursor_ptr.pos:])
			}
			window.buffer.data[cursor_ptr.pos] = '\n'
			adjust_cursors(cursors, cursor_ptr, cursor_ptr.pos, true, 1) // Shift cursors right by 1.

			// Move cursor up to the newly inserted line
			cursor_ptr.pos = window.buffer.line_starts[cursor_ptr.line] // Already at line start after insert.
			buffer_mark_dirty(window.buffer)
			buffer_update_line_starts(window, cursor_ptr.pos)
		}

		// Update line and column for all cursors after insertions.
		update_cursor_lines_and_cols(window.buffer, cursors)
		update_cursors_from_temp_slice(window, cursors)

		// Apply indentation to the newly inserted lines.
		buffer_update_indentation(window, allocator)
	} else {
		for cursor_ptr in cursors {
			current_line := cursor_ptr.line
			current_line_start := window.buffer.line_starts[current_line]
			current_line_length := buffer_line_length(window.buffer, current_line)

			// Move to the true end of the current line's content (before any existing newline).
			cursor_ptr.pos = current_line_start + current_line_length
			adjust_cursors(cursors, cursor_ptr, cursor_ptr.pos, false, 0) // Sync positions.

			// Insert newline at this position.
			resize(&window.buffer.data, len(window.buffer.data) + 1)
			if cursor_ptr.pos < len(window.buffer.data) - 1 {
				copy(window.buffer.data[cursor_ptr.pos + 1:], window.buffer.data[cursor_ptr.pos:])
			}
			window.buffer.data[cursor_ptr.pos] = '\n'
			cursor_ptr.pos += 1 // Move cursor to start of new line.
			adjust_cursors(cursors, cursor_ptr, cursor_ptr.pos - 1, true, 1) // Shift cursors right by 1.

			buffer_mark_dirty(window.buffer)
			buffer_update_line_starts(window, cursor_ptr.pos - 1)
		}

		update_cursor_lines_and_cols(window.buffer, cursors)
		update_cursors_from_temp_slice(window, cursors)
		buffer_update_indentation(window, allocator)
	}

	change_mode(p, .INSERT)
}

@(private)
delete_visual_line :: proc(p: ^Pulse, mode: Vim_Mode) {
	buffer_delete_visual_line_selection(p.current_window)
	clear(&p.current_window.additional_cursors)
	change_mode(p, mode)
}

delete_visual :: proc(p: ^Pulse, mode: Vim_Mode) {
	buffer_delete_selection(p.current_window)
	change_mode(p, mode)
	clear(&p.keymap.vim_state.normal_cmd_buffer)
	for rl.GetCharPressed() != 0 {}
}
