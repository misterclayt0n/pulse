package engine

import rl "vendor:raylib"
import "core:strings"

Extra_Chars :: []rune{'ç'}

// Returns a slice of runes for the ASCII range plus some extra runes.
gen_ascii_plus :: proc() -> []rune {
	ascii_start : rune = 32
	ascii_end   : rune = 126
	extra       : rune = 'ç' 
	
	// Total numbers of codepoints: ASCII count + 1 + extra character.
	total := (ascii_end - ascii_start + 1) + 1
	codepoints := make([]rune, total)
	idx : int = 0
	
	// Append ASCII characters.
	for cp in ascii_start..<ascii_end + 1 {
		codepoints[idx] = cp
		idx += 1
	}

	// Append the extra codepoints.
	for e in Extra_Chars {
		codepoints[idx] = e
		idx += 1
	}

	return codepoints
}

load_font_with_codepoints :: proc(file: string, size: i32, allocator := context.allocator) -> rl.Font {
	codepoints := gen_ascii_plus()
	file, err := strings.clone_to_cstring(file)

	// NOTE: If an allocation error occurs like this, just panic
	assert(err == nil, "Allocation error")
	
	return rl.LoadFontEx(file, size, &codepoints[0], i32(len(codepoints)))
}

