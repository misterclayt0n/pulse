package engine

import "core:fmt"
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
			emacs_state = emacs_state_init(allocator)
		}
	}

	return keymap
}

// Switch
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
	CLI,
}

Vim_State :: struct {
	commands:     [dynamic]u8, // Stores commands like "dd".
	last_command: string,      // For repeating commands.
	mode:         Vim_Mode,
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

	#partial switch p.keymap.vim_state.mode {
	case .NORMAL:
		if press_and_repeat(.I) do change_mode(p, .INSERT)
		if press_and_repeat(.LEFT) || press_and_repeat(.H) do buffer_move_cursor(&p.buffer, .LEFT)
		if press_and_repeat(.RIGHT) || press_and_repeat(.L) do buffer_move_cursor(&p.buffer, .RIGHT)
		if press_and_repeat(.UP) || press_and_repeat(.K) do buffer_move_cursor(&p.buffer, .UP)
		if press_and_repeat(.DOWN) || press_and_repeat(.J) do buffer_move_cursor(&p.buffer, .DOWN)
		if press_and_repeat(.F2) do change_keymap_mode(p, allocator)
	case .INSERT:
		if press_and_repeat(.ESCAPE) do change_mode(p, .NORMAL)
		if press_and_repeat(.ENTER) do buffer_insert_char(&p.buffer, '\n')
		if press_and_repeat(.BACKSPACE) do buffer_delete_char(&p.buffer)

		key := rl.GetCharPressed()
		for key != 0 {
			buffer_insert_char(&p.buffer, rune(key))
			key = rl.GetCharPressed()
		}
	}
}

//
// Emacs

Emacs_State :: struct {}

emacs_state_init :: proc(allocator := context.allocator) -> Emacs_State {
	return Emacs_State {}
}

emacs_state_update :: proc(p: ^Pulse, allocator := context.allocator) {
	assert(p.keymap.mode == .EMACS, "Keybind mode must be set to emacs in order to update it")

	ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)

	// Emacs pinky.
	if ctrl_pressed {
		if press_and_repeat(.B) do buffer_move_cursor(&p.buffer, .LEFT)
		if press_and_repeat(.F) do buffer_move_cursor(&p.buffer, .RIGHT)
		if press_and_repeat(.P) do buffer_move_cursor(&p.buffer, .UP)
		if press_and_repeat(.N) do buffer_move_cursor(&p.buffer, .DOWN)
	}

	if press_and_repeat(.LEFT) do buffer_move_cursor(&p.buffer, .LEFT)
	if press_and_repeat(.RIGHT) do buffer_move_cursor(&p.buffer, .RIGHT)
	if press_and_repeat(.UP) do buffer_move_cursor(&p.buffer, .UP)
	if press_and_repeat(.DOWN) do buffer_move_cursor(&p.buffer, .DOWN)
	if press_and_repeat(.ENTER) do buffer_insert_char(&p.buffer, '\n')
	if press_and_repeat(.BACKSPACE) do buffer_delete_char(&p.buffer)

	key := rl.GetCharPressed()
	for key != 0 {
		buffer_insert_char(&p.buffer, rune(key))
		key = rl.GetCharPressed()
	}

	if press_and_repeat(.F2) do change_keymap_mode(p, allocator)
}

//
// Mode switching
//

change_mode :: proc(p: ^Pulse, target_mode: Vim_Mode) {
	#partial switch target_mode {
	case .NORMAL:
		if p.keymap.vim_state.mode == .INSERT {
			p.keymap.vim_state.mode = .NORMAL
			buffer_move_cursor(&p.buffer, .LEFT)
			return
		}
	case .INSERT:
		if p.keymap.vim_state.mode == .NORMAL do p.keymap.vim_state.mode = .INSERT
	}
}

change_keymap_mode :: proc(p: ^Pulse, allocator := context.allocator) {
	switch p.keymap.mode {
	case .VIM:
		p.keymap.mode        = .EMACS
		p.keymap.emacs_state = emacs_state_init(allocator)
	case .EMACS:
		p.keymap.mode      = .VIM
		p.keymap.vim_state = vim_state_init(allocator)
	}
}

//
// Helpers
//

press_and_repeat :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}
