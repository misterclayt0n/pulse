package main

import "core:fmt"
import vmem "core:mem/virtual"
import "core:os"
import eg "engine"
import rl "vendor:raylib"

main :: proc() {
	arena: vmem.Arena
	err := vmem.arena_init_growing(&arena)
	assert(err == nil, "Could not init arena")
	allocator := vmem.arena_allocator(&arena)

	// Get filename from cli.
	filename := ""
	if len(os.args) > 1 do filename = os.args[1]
	fmt.println(filename)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1080, 920, "Pulse")
	rl.SetWindowMonitor(0)

	// NOTE: Destroy the arena first.
	defer vmem.arena_destroy(&arena)
	defer rl.CloseWindow()
	
	pulse := eg.pulse_init("fonts/IosevkaNerdFont-Regular.ttf", allocator)

	if filename != "" {
		if ok := eg.buffer_load_file(&pulse.buffer, filename, allocator); !ok {
			// TODO: Handle this error a bit better.
			fmt.eprintln("Failed to load file:", filename) 
		} 
	}

	rl.SetExitKey(.KEY_NULL) // So that ESC works fine.

	for !rl.WindowShouldClose() && !pulse.should_close {
		rl.BeginDrawing()
		defer rl.EndDrawing()
		eg.pulse_update(&pulse)
		eg.pulse_draw(&pulse, allocator)
	}
}
