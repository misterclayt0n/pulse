package main

import "core:fmt"
import "core:mem"
import "core:log"
import vmem "core:mem/virtual"
import eg "engine"
import rl "vendor:raylib"

background_color :: rl.Color{28, 28, 28, 255}
text_color :: rl.Color{235, 219, 178, 255}

main :: proc() {
	arena: vmem.Arena
	err := vmem.arena_init_growing(&arena)
	assert(err == nil, "Could not init arena")
	allocator := vmem.arena_allocator(&arena)
	defer vmem.arena_destroy(&arena)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1080, 920, "Pulse")
	defer rl.CloseWindow()

	font := eg.load_font_with_codepoints("fonts/IosevkaNerdFont-Regular.ttf", 100, allocator)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(background_color)
		rl.DrawTextEx(font, "Hello world çç", {10, 10}, f32(font.baseSize), 2, text_color)
	}
}
