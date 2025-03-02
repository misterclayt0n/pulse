package engine

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Keymap_Mode :: enum {
	VIM,
	EMACS,
}

Keymap :: struct {
	mode:        Keymap_Mode,
	vim_state:   Vim_State,
	emacs_state: Emacs_State,
}

keymap_init :: proc(mode: Keymap_Mode, allocator := context.allocator) -> Keymap {
	keymap: Keymap

	switch mode {
	case .VIM:
		keymap = {
			mode      = .VIM,
			vim_state = vim_state_init(allocator),
		}
	case .EMACS:
		keymap = {
			mode        = .VIM,
			emacs_state = emacs_state_init(allocator),
		}
	}

	return keymap
}

keymap_update :: proc(p: ^Pulse) {
	switch p.keymap.mode {
	case .VIM:
		vim_state_update(p)
	case .EMACS:
		emacs_state_update(p)
	}
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
	commands:     [dynamic]u8, // Stores commands like "dd".
	last_command: string, // For repeating commands.
	mode:         Vim_Mode,
	parent_mode:  Keymap_Mode,
}

vim_state_init :: proc(allocator := context.allocator) -> Vim_State {
	return Vim_State {
		commands     = make([dynamic]u8, 0, 1024, allocator),
		// TODO: This should store commands from before, not when I initialize the editor state.
		last_command = "",
		mode         = .NORMAL,
	}
}

vim_state_update :: proc(p: ^Pulse, allocator := context.allocator) {
	assert(p.keymap.mode == .VIM, "Keybind mode must be set to vim in order to update it")

	shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

	#partial switch p.keymap.vim_state.mode {
	case .NORMAL:
		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

		// Default movements between all modes.
		if press_and_repeat(.LEFT) || press_and_repeat(.H) do buffer_move_cursor(&p.buffer, .LEFT)
		if press_and_repeat(.RIGHT) || press_and_repeat(.L) do buffer_move_cursor(&p.buffer, .RIGHT)
		if press_and_repeat(.UP) || press_and_repeat(.K) do buffer_move_cursor(&p.buffer, .UP)
		if press_and_repeat(.DOWN) || press_and_repeat(.J) do buffer_move_cursor(&p.buffer, .DOWN)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(&p.buffer)
		if press_and_repeat(.HOME) do buffer_move_cursor(&p.buffer, .LINE_START)
		if press_and_repeat(.END) do buffer_move_cursor(&p.buffer, .LINE_END)

		// Mode changing.
		if press_and_repeat(.I) do change_mode(p, .INSERT)
		if press_and_repeat(.A) do append_right_motion(p)

		if press_and_repeat(.ZERO) do buffer_move_cursor(&p.buffer, .LINE_START)
		if press_and_repeat(.B) do buffer_move_cursor(&p.buffer, .WORD_LEFT)
		if press_and_repeat(.W) do buffer_move_cursor(&p.buffer, .WORD_RIGHT)
		if press_and_repeat(.E) do buffer_move_cursor(&p.buffer, .WORD_END)
		if press_and_repeat(.X) do buffer_delete_forward_char(&p.buffer)
		if press_and_repeat(.S) {
			buffer_delete_forward_char(&p.buffer)
			change_mode(p, .INSERT)
		}


		if shift_pressed {
			if press_and_repeat(.I) {
				buffer_move_cursor(&p.buffer, .FIRST_NON_BLANK)
				change_mode(p, .INSERT)
			}

			if press_and_repeat(.A) {
				buffer_move_cursor(&p.buffer, .LINE_END)
				append_right_motion(p)
			}

			if press_and_repeat(.D) do buffer_delete_to_line_end(&p.buffer)
			if press_and_repeat(.C) {
				buffer_delete_to_line_end(&p.buffer)
				change_mode(p, .INSERT)
			}

			if press_and_repeat(.MINUS) do buffer_move_cursor(&p.buffer, .FIRST_NON_BLANK)

			// Enter command mode.
			if press_and_repeat(.SEMICOLON) {
				p.keymap.vim_state.parent_mode = .VIM
				change_mode(p, .COMMAND)
			}

			if press_and_repeat(.FOUR) do buffer_move_cursor(&p.buffer, .LINE_END)
		}

		if press_and_repeat(.O) {
			if shift_pressed {
				// 'O': Insert new line above
				buffer_move_cursor(&p.buffer, .LINE_START)
				buffer_insert_char(&p.buffer, '\n')
				buffer_move_cursor(&p.buffer, .UP)
				change_mode(p, .INSERT)
			} else {
				// 'o': Insert new line below
				buffer_move_cursor(&p.buffer, .LINE_END)
				buffer_insert_char(&p.buffer, '\n')
				change_mode(p, .INSERT)
			}
		}

		if press_and_repeat(.I) {
			if shift_pressed {
				buffer_move_cursor(&p.buffer, .FIRST_NON_BLANK)
				change_mode(p, .INSERT)
			} else {
				change_mode(p, .INSERT)
			}
		}

		if press_and_repeat(.F2) do change_keymap_mode(p, allocator)

	case .INSERT:
		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)

		// Default movements between all modes.
		if press_and_repeat(.LEFT) do buffer_move_cursor(&p.buffer, .LEFT)
		if press_and_repeat(.RIGHT) do buffer_move_cursor(&p.buffer, .RIGHT)
		if press_and_repeat(.UP) do buffer_move_cursor(&p.buffer, .UP)
		if press_and_repeat(.DOWN) do buffer_move_cursor(&p.buffer, .DOWN)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(&p.buffer)
		if press_and_repeat(.HOME) do buffer_move_cursor(&p.buffer, .LINE_START)
		if press_and_repeat(.END) do buffer_move_cursor(&p.buffer, .LINE_END)

		if press_and_repeat(.ESCAPE) do change_mode(p, .NORMAL)
		if press_and_repeat(.ENTER) do buffer_insert_char(&p.buffer, '\n')
		if press_and_repeat(.BACKSPACE) {
			if ctrl_pressed || alt_pressed do buffer_delete_word(&p.buffer)
			else do buffer_delete_char(&p.buffer)
		}

		key := rl.GetCharPressed()
		for key != 0 {
			buffer_insert_char(&p.buffer, rune(key))
			key = rl.GetCharPressed()
		}
	case .COMMAND:
		using p.status_line
		key := rl.GetCharPressed()

		if rl.IsKeyPressed(.ENTER) {
			execute_command(p)
			get_out_of_command_mode(p)
		}

		ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)

		if rl.IsKeyPressed(.ESCAPE) {
			if p.keymap.vim_state.parent_mode == .VIM do change_mode(p, .COMMAND_NORMAL)
			else do get_out_of_command_mode(p)
		}

		// Handle cursor movement.
		if press_and_repeat(.LEFT) do buffer_move_cursor(&command_buf, .LEFT)
		if press_and_repeat(.RIGHT) do buffer_move_cursor(&command_buf, .RIGHT)
		if press_and_repeat(.DELETE) do buffer_delete_forward_char(&command_buf)
		if press_and_repeat(.HOME) do buffer_move_cursor(&command_buf, .LINE_START)
		if press_and_repeat(.END) do buffer_move_cursor(&command_buf, .LINE_END)

		// NOTE: Maybe I should some sort of flag for these emacs bindings inside command mode.
		// Something like emacs_mode: bool, and then I could sort of switch between using the emacs bindings inside
		// command mode or just press esc and go for the normal mode of command mode.
		if ctrl_pressed {
			if press_and_repeat(.B) do buffer_move_cursor(&command_buf, .LEFT)
			if press_and_repeat(.F) do buffer_move_cursor(&command_buf, .RIGHT)
			if press_and_repeat(.E) do buffer_move_cursor(&command_buf, .LINE_END)
			if press_and_repeat(.A) do buffer_move_cursor(&command_buf, .LINE_START)
			if press_and_repeat(.K) do buffer_delete_to_line_end(&command_buf)
		}

		if alt_pressed {
			if press_and_repeat(.F) do buffer_move_cursor(&command_buf, .WORD_RIGHT)
			if press_and_repeat(.B) do buffer_move_cursor(&command_buf, .WORD_LEFT)
		}

		if press_and_repeat(.BACKSPACE) {
			if ctrl_pressed || alt_pressed do buffer_delete_word(&command_buf)
			else do buffer_delete_char(&command_buf)
		}

		for key != 0 {
			if is_char_supported(rune(key)) do buffer_insert_char(&command_buf, rune(key))
			key = rl.GetCharPressed()
		}
	case .COMMAND_NORMAL:
		using p.status_line

		shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

		if press_and_repeat(.ESCAPE) {
			get_out_of_command_mode(p)
		}

		// Movement commands for command buffer.
		if press_and_repeat(.H) || press_and_repeat(.LEFT) do buffer_move_cursor(&command_buf, .LEFT)
		if press_and_repeat(.L) || press_and_repeat(.RIGHT) do buffer_move_cursor(&command_buf, .RIGHT)
		if press_and_repeat(.B) do buffer_move_cursor(&command_buf, .WORD_LEFT)
		if press_and_repeat(.W) do buffer_move_cursor(&command_buf, .WORD_RIGHT)
		if press_and_repeat(.ZERO) do buffer_move_cursor(&command_buf, .LINE_START)
		if press_and_repeat(.X) do buffer_delete_forward_char(&command_buf)

		if shift_pressed {
			if press_and_repeat(.I) {
				buffer_move_cursor(&command_buf, .FIRST_NON_BLANK)
				change_mode(p, .COMMAND)
			}

			if press_and_repeat(.A) {
				buffer_move_cursor(&command_buf, .LINE_END)
				append_right_motion(p)
			}

			if press_and_repeat(.FOUR) do buffer_move_cursor(&command_buf, .LINE_END)

			if press_and_repeat(.D) do buffer_delete_to_line_end(&command_buf)
			if press_and_repeat(.C) {
				buffer_delete_to_line_end(&command_buf)
				change_mode(p, .COMMAND)
			}

			if press_and_repeat(.MINUS) do buffer_move_cursor(&command_buf, .FIRST_NON_BLANK)
		}

		if press_and_repeat(.I) do change_mode(p, .COMMAND)
		if press_and_repeat(.A) {
			buffer := &p.status_line.command_buf

			current_line_end := len(buffer.data)
			if buffer.cursor.line < len(buffer.line_starts) - 1 {
				current_line_end = buffer.line_starts[buffer.cursor.line + 1] - 1
			}

			// Only move right if we're not already at the end of the line.
			if buffer.cursor.pos < current_line_end {
				n_bytes := next_rune_length(buffer.data[:], buffer.cursor.pos)
				buffer.cursor.pos += n_bytes
			}

			change_mode(p, .COMMAND)
		}
	}
}

//
// Emacs
//

// TODO: Add something similar to command mode in here.
Emacs_State :: struct {}

emacs_state_init :: proc(allocator := context.allocator) -> Emacs_State {
	return Emacs_State{}
}

emacs_state_update :: proc(p: ^Pulse, allocator := context.allocator) {
	assert(p.keymap.mode == .EMACS, "Keybind mode must be set to emacs in order to update it")

	ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
	alt_pressed := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)
	shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

	// Default movements between all modes.
	if press_and_repeat(.LEFT) do buffer_move_cursor(&p.buffer, .LEFT)
	if press_and_repeat(.RIGHT) do buffer_move_cursor(&p.buffer, .RIGHT)
	if press_and_repeat(.UP) do buffer_move_cursor(&p.buffer, .UP)
	if press_and_repeat(.DOWN) do buffer_move_cursor(&p.buffer, .DOWN)
	if press_and_repeat(.DELETE) do buffer_delete_forward_char(&p.buffer)
	if press_and_repeat(.HOME) do buffer_move_cursor(&p.buffer, .LINE_START)
	if press_and_repeat(.END) do buffer_move_cursor(&p.buffer, .LINE_END)

	// Emacs pinky.
	if ctrl_pressed {
		if press_and_repeat(.B) do buffer_move_cursor(&p.buffer, .LEFT)
		if press_and_repeat(.F) do buffer_move_cursor(&p.buffer, .RIGHT)
		if press_and_repeat(.P) do buffer_move_cursor(&p.buffer, .UP)
		if press_and_repeat(.N) do buffer_move_cursor(&p.buffer, .DOWN)
		if press_and_repeat(.E) {
			buffer_move_cursor(&p.buffer, .LINE_END)
			current_line_end := len(p.buffer.data)
			if p.buffer.cursor.line < len(p.buffer.line_starts) - 1 {
				current_line_end = p.buffer.line_starts[p.buffer.cursor.line + 1] - 1
			}

			// Only move right if we're not already at the end of the line.
			if p.buffer.cursor.pos < current_line_end {
				n_bytes := next_rune_length(p.buffer.data[:], p.buffer.cursor.pos)
				p.buffer.cursor.pos += n_bytes
			}
		}
		if press_and_repeat(.A) do buffer_move_cursor(&p.buffer, .LINE_START)
		if press_and_repeat(.K) do buffer_delete_to_line_end(&p.buffer)

		if press_and_repeat(.ENTER) {
			if shift_pressed {
				// Ctrl+Shift+Enter - Insert line above.
				original_line := p.buffer.cursor.line
				original_pos := p.buffer.cursor.pos

				// Move to line start and insert newline.
				buffer_move_cursor(&p.buffer, .LINE_START)
				buffer_insert_char(&p.buffer, '\n')

				// Explicitly set cursor to new line's start.
				p.buffer.cursor.line = original_line // New line is created above, so damn same index.
				p.buffer.cursor.pos = p.buffer.line_starts[p.buffer.cursor.line]
			} else {
				buffer_move_cursor(&p.buffer, .LINE_END)
				buffer_insert_char(&p.buffer, '\n')
			}
		}
	}

	// How do people live like this man...
	// Pretty sure I'm one of them... I mean, I'm kinda creating an emacs mode for a reason after all.
	if alt_pressed {
		if press_and_repeat(.F) do buffer_move_cursor(&p.buffer, .WORD_RIGHT)
		if press_and_repeat(.B) do buffer_move_cursor(&p.buffer, .WORD_LEFT)
		if press_and_repeat(.X) {
			// Enter command mode from emacs.
			p.keymap.vim_state.parent_mode = .EMACS
			p.keymap.mode = .VIM // Temporarily switch to vim mode.
			change_mode(p, .COMMAND)
		}
	}

	if press_and_repeat(.LEFT) do buffer_move_cursor(&p.buffer, .LEFT)
	if press_and_repeat(.RIGHT) do buffer_move_cursor(&p.buffer, .RIGHT)
	if press_and_repeat(.UP) do buffer_move_cursor(&p.buffer, .UP)
	if press_and_repeat(.DOWN) do buffer_move_cursor(&p.buffer, .DOWN)
	if press_and_repeat(.ENTER) {
		// Only insert newline if Ctrl isn't pressed
		if !ctrl_pressed {
			buffer_insert_char(&p.buffer, '\n')
		}
	}

	if press_and_repeat(.BACKSPACE) {
		if ctrl_pressed || alt_pressed do buffer_delete_word(&p.buffer)
		else do buffer_delete_char(&p.buffer)
	}

	key := rl.GetCharPressed()
	for key != 0 {
		buffer_insert_char(&p.buffer, rune(key))
		key = rl.GetCharPressed()
	}

	if press_and_repeat(.F2) do change_keymap_mode(p, allocator)
}

//
// Command handling
//

execute_command :: proc(p: ^Pulse) {
	cmd := strings.clone_from_bytes(p.status_line.command_buf.data[:])
	cmd = strings.trim_space(cmd) // Remove leading/trailing whitespace.
	defer delete(cmd)

	// Handle different commands.
	switch cmd {
	case "w":
		// TODO.
		fmt.println("Saving file")
	case "q":
		// TODO: This should probably close the buffer/window, not the entire editor probably.
		p.should_close = true
	case "wq":
		fmt.println("Saving file")
		p.should_close = true
	case:
		fmt.println("Unknown command: %s\n", cmd)
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
			buffer_move_cursor(&p.buffer, .LEFT)
		}

		if mode == .COMMAND {
			mode = .NORMAL
		}
	case .INSERT:
		if mode == .NORMAL do mode = .INSERT
	case .COMMAND:
		if mode == .NORMAL {
			mode = .COMMAND
			clear(&p.status_line.command_buf.data)
			append(&p.status_line.command_buf.data, ' ') // Add an initial space.
			p.status_line.command_buf.cursor.pos = 0
		}

		if mode == .COMMAND_NORMAL do mode = .COMMAND
	case .COMMAND_NORMAL:
		assert(mode == .COMMAND, "We can only enter command normal mode from command insert mode")
		if mode == .COMMAND {
			mode = .COMMAND_NORMAL
			buffer_move_cursor(&p.status_line.command_buf, .LEFT)
		}

	}
}

change_keymap_mode :: proc(p: ^Pulse, allocator := context.allocator) {
	switch p.keymap.mode {
	case .VIM:
		p.keymap.mode = .EMACS
		p.keymap.emacs_state = emacs_state_init(allocator)
	case .EMACS:
		p.keymap.mode = .VIM
		p.keymap.vim_state = vim_state_init(allocator)
	}
}

get_out_of_command_mode :: proc(p: ^Pulse) {
	assert(p.keymap.vim_state.mode == .COMMAND || p.keymap.vim_state.mode == .COMMAND_NORMAL)

	// Restore prev mode.
	parent_mode := p.keymap.vim_state.parent_mode
	p.keymap.mode = parent_mode
	p.keymap.vim_state.mode = .NORMAL

	clear(&p.status_line.command_buf.data)
	p.status_line.command_buf.cursor.pos = 0
}

append_right_motion :: proc(p: ^Pulse) {
	current_line_end := len(p.buffer.data)
	if p.buffer.cursor.line < len(p.buffer.line_starts) - 1 {
		current_line_end = p.buffer.line_starts[p.buffer.cursor.line + 1] - 1
	}

	// Only move right if we're not already at the end of the line.
	if p.buffer.cursor.pos < current_line_end {
		n_bytes := next_rune_length(p.buffer.data[:], p.buffer.cursor.pos)
		p.buffer.cursor.pos += n_bytes
	}

	change_mode(p, .INSERT)
}

//
// Helpers
//

press_and_repeat :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}

