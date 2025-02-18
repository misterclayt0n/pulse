// TODO: Make Pulse's global state.
package main

import "core:fmt"
import vmem "core:mem/virtual"
import eg "engine"
import rl "vendor:raylib"

// 
// Globals
// 

background_color :: rl.Color{28, 28, 28, 255}
text_color :: rl.Color{235, 219, 178, 255}

// Main state of the editor,
Pulse :: struct {
	buffer: eg.Buffer, // NOTE: This is probably being removed for a window system.
	font: eg.Font
}

pulse_init :: proc(allocator := context.allocator) -> Pulse {
	buffer := eg.buffer_init(allocator)
	eg.buffer_insert_text(&buffer, "hello world ç")
	font := eg.load_font_with_codepoints("fonts/IosevkaNerdFont-Regular.ttf", 100, text_color, allocator) // Default font
	
	return Pulse {
		buffer = buffer,
		font = font,
	}
}

pulse_update :: proc(p: ^Pulse) {
	key := rl.GetCharPressed()
	for key != 0 {
		eg.buffer_insert_char(&p.buffer, rune(key))

		key = rl.GetCharPressed()
	}

	// Cursor movement.
	if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressedRepeat(.LEFT) do eg.buffer_move_cursor(&p.buffer, .LEFT)
	if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) do eg.buffer_move_cursor(&p.buffer, .RIGHT)
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressedRepeat(.UP) do eg.buffer_move_cursor(&p.buffer, .UP)
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressedRepeat(.DOWN) do eg.buffer_move_cursor(&p.buffer, .DOWN)
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressedRepeat(.ENTER) do eg.buffer_insert_char(&p.buffer, '\n')
	if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) do eg.buffer_delete_char(&p.buffer)
}

pulse_draw :: proc(p: ^Pulse) {
	rl.ClearBackground(background_color)
	eg.buffer_draw(&p.buffer, {10, 10}, p.font)
}

main :: proc() {
	arena: vmem.Arena
	err := vmem.arena_init_growing(&arena)
	assert(err == nil, "Could not init arena")
	allocator := vmem.arena_allocator(&arena)
	defer vmem.arena_destroy(&arena)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1080, 920, "Pulse")
	defer rl.CloseWindow()
	
	pulse := pulse_init(allocator)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		defer rl.EndDrawing()

		pulse_update(&pulse)
		
		pulse_draw(&pulse)
	}
}
