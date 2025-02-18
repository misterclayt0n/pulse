package main

import "core:fmt"
import vmem "core:mem/virtual"
import eg "engine"
import rl "vendor:raylib"

main :: proc() {
	arena: vmem.Arena
	err := vmem.arena_init_growing(&arena)
	assert(err == nil, "Could not init arena")
	allocator := vmem.arena_allocator(&arena)
	defer vmem.arena_destroy(&arena)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1080, 920, "Pulse")
	defer rl.CloseWindow()
	
	pulse := eg.pulse_init("fonts/IosevkaNerdFont-Regular.ttf", allocator)

	rl.SetExitKey(.KEY_NULL) // So that ESC works fine.

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		defer rl.EndDrawing()

		eg.pulse_update(&pulse)
		
		eg.pulse_draw(&pulse)
	}
}
