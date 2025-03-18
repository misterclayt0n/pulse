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
	context.allocator = allocator

	// Get filename from cli.
	filename := ""
	if len(os.args) > 1 do filename = os.args[1]
	fmt.println(filename)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(rl.GetScreenWidth(), rl.GetScreenHeight(), "Pulse")
	rl.SetWindowMonitor(0)

	// NOTE: Destroy the arena first.
	defer vmem.arena_destroy(&arena)
	defer rl.CloseWindow()

	pulse := eg.pulse_init("fonts/GeistMono-VariableFont_wght.ttf", allocator)
	assert(&pulse != nil, "Invalid pulse pointer")

	if filename != "" {
		if ok := eg.buffer_load_file(pulse.current_window, filename, allocator); !ok {
			// TODO: Handle this error a bit better.
			fmt.eprintln("Failed to load file:", filename)
		}
	}

	rl.SetExitKey(.KEY_NULL) // So that ESC works fine.

	for !rl.WindowShouldClose() && !pulse.should_close {
		rl.BeginDrawing()
		defer rl.EndDrawing()
		eg.pulse_update(&pulse, allocator)
		eg.pulse_draw(&pulse, allocator)
	}
}
