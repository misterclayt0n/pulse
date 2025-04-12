package engine

import "core:strings"
import rl "vendor:raylib"

//
// Helpers
// 

collect_selection_ranges :: proc(window: ^Window, allocator := context.allocator) -> [dynamic]Selection_Range {
    return get_selection_ranges(window, allocator)
}

collect_visual_line_ranges :: proc(
	window: ^Window,
	allocator := context.allocator,
) -> [dynamic][2]int {
	using window
	if mode == .VISUAL_LINE {
		raw_ranges := get_visual_line_ranges(window, allocator)
		defer delete(raw_ranges)
		return merge_line_ranges(raw_ranges, allocator)
	}
	return make([dynamic][2]int, 0, 0, allocator)
}

collect_match_ranges :: proc(
	p: ^Pulse,
	window: ^Window,
	allocator := context.allocator,
) -> [dynamic][2]int {
	match_ranges := make([dynamic][2]int, 0, 10, allocator)
	if len(window.temp_match_ranges) > 0 {
		if p.keymap.vim_state.last_command == "select" {
			start := p.keymap.vim_state.pattern_selection_start
			for range in window.temp_match_ranges {
				abs_start := start + range[0]
				abs_end := start + range[1]
				append(&match_ranges, [2]int{abs_start, abs_end})
			}
		} else {
			for range in window.temp_match_ranges {
				append(&match_ranges, range)
			}
		}
	}
	return match_ranges
}

// 
// Buffer Drawing.
// 

draw_match_highlights :: proc(
	window: ^Window,
	match_ranges: [dynamic][2]int,
	line: int,
	line_start, line_end: int,
	ctx: Draw_Context,
	font: Font,
	allocator := context.allocator,
) {
	if len(match_ranges) == 0 do return

	x_start := ctx.position.x
	y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)
	for match_range in match_ranges {
		match_start := match_range[0]
		match_end := match_range[1]
		if match_start < line_end && match_end > line_start {
			start_pos := max(match_start, line_start)
			end_pos := min(match_end, line_end)

			text_before := window.buffer.data[line_start:start_pos]
			before_str := strings.clone_to_cstring(string(text_before), allocator)
			defer delete(before_str, allocator)
			x_offset := rl.MeasureTextEx(font.ray_font, before_str, f32(font.size), font.spacing).x

			text_match := window.buffer.data[start_pos:end_pos]
			match_str := strings.clone_to_cstring(string(text_match), allocator)
			defer delete(match_str, allocator)
			match_width :=
				rl.MeasureTextEx(font.ray_font, match_str, f32(font.size), font.spacing).x

			if start_pos == end_pos && start_pos >= line_start && start_pos < line_end {
				match_width = font.char_width
			}

			rl.DrawRectangleV(
				{x_start + x_offset, y_pos},
				{match_width, f32(ctx.line_height)},
				SELECTION_COLOR,
			)
		}
	}
}

draw_temporary_search_highlight :: proc(
    window: ^Window,
    line: int,
    line_start, line_end: int,
    ctx: Draw_Context,
    font: Font,
    allocator := context.allocator,
) {
    if !window.highlight_searched || len(window.searched_text) == 0 do return

    x_start := ctx.position.x
    y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)
    match_start := window.cursor.pos
    match_end := match_start + len(window.searched_text)

    if match_start < line_end && match_end > line_start {
        start_pos := max(match_start, line_start)
        end_pos := min(match_end, line_end)

        text_before := window.buffer.data[line_start:start_pos]
        before_str := strings.clone_to_cstring(string(text_before), allocator)
        defer delete(before_str, allocator)
        x_offset := rl.MeasureTextEx(font.ray_font, before_str, f32(font.size), font.spacing).x

        text_match := window.buffer.data[start_pos:end_pos]
        match_str := strings.clone_to_cstring(string(text_match), allocator)
        defer delete(match_str, allocator)
        match_width := rl.MeasureTextEx(font.ray_font, match_str, f32(font.size), font.spacing).x

        if start_pos == end_pos && start_pos >= line_start && start_pos < line_end {
            match_width = font.char_width
        }

        opacity := 1.0 - (window.highlight_timer / window.highlight_duration)
        if opacity > 0 {
            highlight_color := rl.Fade(TEMP_HIGHLIGHT_COLOR, opacity)
            rl.DrawRectangleV(
                {x_start + x_offset, y_pos},
                {match_width, f32(ctx.line_height)},
                highlight_color,
            )
        }
    }
}

draw_visual_block_highlights :: proc(
    window: ^Window,
    line: int,
    line_start, line_end: int,
    ctx: Draw_Context,
    font: Font,
    allocator := context.allocator,
) {
    if window.mode != .VISUAL_BLOCK || window.visual_block_anchor_line == -1 do return

    start_line := min(window.visual_block_anchor_line, window.cursor.line)
    end_line := max(window.visual_block_anchor_line, window.cursor.line)
    current_col := window.cursor.preferred_col if window.cursor.preferred_col != -1 else window.cursor.col
    start_c := min(window.visual_block_anchor_col, current_col)
    end_c := max(window.visual_block_anchor_col, current_col)

    if line >= start_line && line <= end_line {
        x_draw_start := ctx.position.x
        y_draw_pos := ctx.position.y + f32(line - ctx.first_line) * f32(ctx.line_height)

        sel_start_pos := buffer_get_pos_from_col(window.buffer, line, start_c)
        sel_end_pos := buffer_get_pos_from_col(window.buffer, line, end_c)
        if sel_start_pos > line_end do sel_start_pos = line_end
        if sel_end_pos > line_end do sel_end_pos = line_end

        x_offset: f32 = 0
        if sel_start_pos > line_start {
            before_text := window.buffer.data[line_start:sel_start_pos]
            before_str := strings.clone_to_cstring(string(before_text), allocator)
            defer delete(before_str, allocator)
            x_offset = rl.MeasureTextEx(font.ray_font, before_str, f32(font.size), font.spacing).x
        }

        sel_width: f32 = 0
        if sel_end_pos > sel_start_pos {
            selected_text := window.buffer.data[sel_start_pos:sel_end_pos]
            selected_str := strings.clone_to_cstring(string(selected_text), allocator)
            defer delete(selected_str, allocator)
            sel_width = rl.MeasureTextEx(font.ray_font, selected_str, f32(font.size), font.spacing).x
        } else {
            sel_width = rl.MeasureTextEx(font.ray_font, " ", f32(font.size), font.spacing).x / 2
        }

        rl.DrawRectangleV(
            {x_draw_start + x_offset, y_draw_pos},
            {sel_width, f32(font.size)},
            HIGHLIGHT_COLOR,
        )
    }
}

draw_selection_highlights :: proc(
	window: ^Window,
    selection_ranges: [dynamic]Selection_Range,
    selection_active: bool,
    line: int,
    line_start, line_end: int,
    ctx: Draw_Context,
    font: Font,
    allocator := context.allocator,
) {
    if !selection_active do return

    x_start := ctx.position.x
    y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)
    for sel_range in selection_ranges {
        sel_start := sel_range.start
        sel_end := sel_range.end
        if sel_start < line_end && sel_end > line_start {
            start_pos := max(sel_start, line_start)
            end_pos := min(sel_end, line_end)

            text_before := window.buffer.data[line_start:start_pos]
            before_str := strings.clone_to_cstring(string(text_before), allocator)
            defer delete(before_str, allocator)
            x_offset := rl.MeasureTextEx(font.ray_font, before_str, f32(font.size), font.spacing).x

            text_selected := window.buffer.data[start_pos:end_pos]
            selected_str := strings.clone_to_cstring(string(text_selected), allocator)
            defer delete(selected_str, allocator)
            sel_width := rl.MeasureTextEx(font.ray_font, selected_str, f32(font.size), font.spacing).x

            if start_pos == end_pos {
                sel_width = font.char_width
            }

            rl.DrawRectangleV(
                {x_start + x_offset, y_pos},
                {sel_width, f32(font.size)},
                HIGHLIGHT_COLOR,
            )
        }
    }
}

draw_visual_line_highlights :: proc(
	font: Font,
    visual_line_ranges: [dynamic][2]int,
    line: int,
    line_width: f32,
    ctx: Draw_Context,
    allocator := context.allocator,
) {
    if len(visual_line_ranges) == 0 do return

    x_start := ctx.position.x
    y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)
    for range in visual_line_ranges {
        if line >= range[0] && line <= range[1] {
            sel_width := line_width
            if line_width == 0 {
                sel_width = rl.MeasureTextEx(font.ray_font, " ", f32(font.size), font.spacing).x
            }
            rl.DrawRectangleV(
                {x_start, y_pos},
                {sel_width, f32(font.size)},
                HIGHLIGHT_COLOR,
            )
            break
        }
    }
}

buffer_draw_visible_lines :: proc(
    p: ^Pulse,
    window: ^Window,
    font: Font,
    ctx: Draw_Context,
    allocator := context.allocator,
) {
    using window
    assert(buffer.data != nil, "Buffer data must not be nil")
    assert(len(buffer.line_starts) > 0, "Buffer must have at least one line start")
    assert(ctx.first_line >= 0, "First line must be non-negative")
    assert(ctx.last_line >= ctx.first_line, "Last line must be >= first line")
    assert(ctx.last_line < len(buffer.line_starts), "Last line must be within buffer bounds")

    // Collect ranges
    selection_ranges := collect_selection_ranges(window, allocator)
    defer delete(selection_ranges)
    selection_active := mode == .VISUAL && len(selection_ranges) > 0

    visual_line_ranges := collect_visual_line_ranges(window, allocator)
    defer delete(visual_line_ranges)

    match_ranges := collect_match_ranges(p, window, allocator)
    defer delete(match_ranges)

    // Iterate over visible lines
    for line in ctx.first_line ..= ctx.last_line {
        line_start := buffer.line_starts[line]
        line_end := len(buffer.data)
        if line < len(buffer.line_starts) - 1 {
            next_line_start := buffer.line_starts[line + 1]
            if next_line_start > 0 && buffer.data[next_line_start - 1] == '\n' {
                line_end = next_line_start - 1
            } else {
                line_end = next_line_start
            }
        }
        assert(line_start >= 0 && line_start <= len(buffer.data), "Line start out of bounds")
        assert(line_end >= line_start && line_end <= len(buffer.data), "Line end out of bounds")

        // Calculate line text and width
        line_text := string(buffer.data[line_start:line_end])
        line_str := strings.clone_to_cstring(line_text, allocator)
        defer delete(line_str, allocator)
        line_width := rl.MeasureTextEx(font.ray_font, line_str, f32(font.size), font.spacing).x

        // Draw highlights
        draw_match_highlights(window, match_ranges, line, line_start, line_end, ctx, font, allocator)
        draw_temporary_search_highlight(window, line, line_start, line_end, ctx, font, allocator)
        draw_visual_block_highlights(window, line, line_start, line_end, ctx, font, allocator)
        draw_selection_highlights(window, selection_ranges, selection_active, line, line_start, line_end, ctx, font, allocator)
        draw_visual_line_highlights(font, visual_line_ranges, line, line_width, ctx, allocator)

        // Draw the line text
        y_pos := ctx.position.y + f32(line) * f32(ctx.line_height)
        rl.DrawTextEx(
            font.ray_font,
            line_str,
            rl.Vector2{ctx.position.x, y_pos},
            f32(font.size),
            font.spacing,
            font.color,
        )
    }
}

// 
// Cursor drawing.
// 

cursor_draw :: proc(window: ^Window, font: Font, ctx: Draw_Context) {
	using window
	cursor_pos := ctx.position

	// Adjust vertical position based on line number.
	cursor_pos.y += f32(cursor.line) * (f32(font.size) + font.spacing)

	assert(cursor.pos >= 0, "Cursor position must be greater or equal to 0")
	assert(len(buffer.data) >= 0, "Buffer size has to be greater or equal to 0")

	line_start := buffer.line_starts[cursor.line]
	cursor_pos_clamped := min(cursor.pos, len(buffer.data)) // NOTE: Make sure we cannot slice beyond the buffer size.
	assert(
		line_start <= cursor_pos_clamped,
		"Line start index must be less or equal to clamped cursor position",
	)
	assert(
		line_start >= 0 && line_start <= len(buffer.data),
		"line_start out of range in buffer_draw_cursor",
	)

	if cursor.pos > line_start {
		line_text := buffer.data[line_start:cursor_pos_clamped]
		assert(len(line_text) >= 0, "Line text cannot be negative")
		temp_text := make([dynamic]u8, len(line_text) + 1)
		defer delete(temp_text)
		copy(temp_text[:], line_text)
		temp_text[len(line_text)] = 0
		cursor_pos.x += rl.MeasureTextEx(font.ray_font, cstring(&temp_text[0]), f32(font.size), font.spacing).x + 2 // NOTE: Add 2 for alignment.
	} else {
		// NOTE: For the first character, no text width to measure, so we can just use ctx.position as is.
	}

	if cursor.blink && (int(rl.GetTime() * 2) % 2 == 0) do return

	font_size := f32(font.size)

	switch cursor.style {
	case .BAR:
		if window.is_focus do rl.DrawLineV(cursor_pos, {cursor_pos.x, cursor_pos.y + font_size}, cursor.color)
	case .BLOCK:
		char_width := rl.MeasureTextEx(font.ray_font, "@", font_size, font.spacing).x
		if window.is_focus {
			rl.DrawRectangleV(
				cursor_pos,
				{char_width, font_size},
				{cursor.color.r, cursor.color.g, cursor.color.b, 128},
			)
		} else {
			// Draw outline-only block for unfocused windows.
			rl.DrawRectangleLinesEx(
				rl.Rectangle{cursor_pos.x, cursor_pos.y, char_width, font_size},
				1,
				{CURSOR_COLOR.r, CURSOR_COLOR.g, CURSOR_COLOR.b, 80}, // Slightly transparent.
			)
		}
	case .UNDERSCORE:
		char_width := rl.MeasureTextEx(font.ray_font, "M", font_size, font.spacing).x
		if window.is_focus {
			rl.DrawLineV(
				{cursor_pos.x, cursor_pos.y + font_size},
				{cursor_pos.x + char_width, cursor_pos.y + font_size},
				cursor.color,
			)
		}
	}

    for &extra_cursor in window.additional_cursors {
        cursor_pos = ctx.position
        cursor_pos.y += f32(extra_cursor.line) * (f32(font.size) + font.spacing)
        line_start = window.buffer.line_starts[extra_cursor.line]
        cursor_pos_clamped = min(extra_cursor.pos, len(window.buffer.data))
        if extra_cursor.pos > line_start {
            line_text := window.buffer.data[line_start:cursor_pos_clamped]
            temp_text := make([dynamic]u8, len(line_text) + 1)
            defer delete(temp_text)
            copy(temp_text[:], line_text)
            temp_text[len(line_text)] = 0
            cursor_pos.x += rl.MeasureTextEx(font.ray_font, cstring(&temp_text[0]), f32(font.size), font.spacing).x + 2
        }
        if !extra_cursor.blink || (int(rl.GetTime() * 2) % 2 != 0) {
            font_size := f32(font.size)
            switch extra_cursor.style {
            case .BAR:
                if window.is_focus do rl.DrawLineV(cursor_pos, {cursor_pos.x, cursor_pos.y + font_size}, extra_cursor.color)
            case .BLOCK:
                char_width := rl.MeasureTextEx(font.ray_font, "@", font_size, font.spacing).x
                if window.is_focus {
                    rl.DrawRectangleV(cursor_pos, {char_width, font_size}, {extra_cursor.color.r, extra_cursor.color.g, extra_cursor.color.b, 128})
                } else {
                    rl.DrawRectangleLinesEx(rl.Rectangle{cursor_pos.x, cursor_pos.y, char_width, font_size}, 1, {CURSOR_COLOR.r, CURSOR_COLOR.g, CURSOR_COLOR.b, 80})
                }
            case .UNDERSCORE:
                char_width := rl.MeasureTextEx(font.ray_font, "M", font_size, font.spacing).x
                if window.is_focus {
                    rl.DrawLineV({cursor_pos.x, cursor_pos.y + font_size}, {cursor_pos.x + char_width, cursor_pos.y + font_size}, extra_cursor.color)
                }
            }
        }
    }
}

// 
// Window drawing.
// 

window_draw :: proc(p: ^Pulse, w: ^Window, allocator := context.allocator) {
	if w.highlight_searched {
		w.highlight_timer += rl.GetFrameTime()
		if w.highlight_timer >= w.highlight_duration do w.highlight_searched = false
	}
	
	screen_width := i32(w.rect.width)
	screen_height := i32(w.rect.height)
	line_height := f32(w.font.size) + w.font.spacing

	// Calculate visible lines based on scroll position.
	first_visible_line := int((w.scroll.y - 10) / line_height)
	last_visible_line := int((w.scroll.y + f32(screen_height) + 10) / line_height)
	first_visible_line = max(0, first_visible_line)
	last_visible_line = min(len(w.buffer.line_starts) - 1, last_visible_line)

	if first_visible_line > last_visible_line {
		first_visible_line = 0
		last_visible_line = max(0, len(w.buffer.line_starts) - 1)
	}

	assert(first_visible_line <= last_visible_line, "Invalid line range")
	assert(
		first_visible_line >= 0 && last_visible_line < len(w.buffer.line_starts),
		"Visible lines out of bounds",
	)

	// Set up camera.
	camera := rl.Camera2D {
		offset   = {w.rect.x, w.rect.y},
		target   = {w.scroll.x, w.scroll.y},
		rotation = 0,
		zoom     = 1,
	}
	assert(camera.offset.x == w.rect.x && camera.offset.y == w.rect.y, "Camera offset mismatch")

	rl.BeginScissorMode(i32(w.rect.x), i32(w.rect.y), i32(w.rect.width), i32(w.rect.height))
	defer rl.EndScissorMode()

	rl.BeginMode2D(camera)
	defer rl.EndMode2D()

	// Draw line numbers and set text_offset.
	window_draw_line_numbers(
		w,
		w.font,
		first_visible_line,
		last_visible_line,
		line_height,
		allocator,
	)
	assert(w.text_offset > 0, "Invalid text offset")

	// Draw text content.
	ctx := Draw_Context {
		position      = {w.text_offset, 10}, // Use text_offset set by window_draw_line_numbers.
		screen_width  = i32(w.rect.width), // Full width, no margin_x subtraction.
		screen_height = i32(w.rect.height),
		first_line    = first_visible_line,
		last_line     = last_visible_line,
		line_height   = int(line_height),
	}

	// Draw the actual buffer.
	buffer_draw(p, w, w.font, ctx, allocator)
}
