package engine

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import rl "vendor:raylib"

// This is mostly a wrapper around a couple of raylib internals, and to make it easy to work with.
Font :: struct {
	ray_font:   rl.Font,
	size:       i32,
	spacing:    f32,
	color:      rl.Color,
	char_width: f32,
}

// Returns a slice of runes for the ASCII range plus some extra runes.
gen_ascii_plus :: proc() -> []rune {
	// Unicode ranges.
	ascii_start: rune = 32 // Start of printable ASCII.
	ascii_end: rune = 126 // End of printable ASCII.
	latin1_start: rune = 0xA0 // Start of Latin-1 Supplement (skip control chars).
	latin1_end: rune = 0xFF // End of Latin-1 Supplement.
	latin_extended_a_start: rune = 0x100 // Start of Latin Extended-A.
	latin_extended_a_end: rune = 0x17F // End of Latin Extended-A.

	// Calculate total number of codepoints.
	total :=
		(ascii_end - ascii_start + 1) +
		(latin1_end - latin1_start + 1) +
		(latin_extended_a_end - latin_extended_a_start + 1) 
	codepoints := make([]rune, total)
	idx: int = 0

	// Append ASCII characters.
	for cp in ascii_start ..< ascii_end + 1 {
		codepoints[idx] = cp
		idx += 1
	}

	// Append Latin-1 Supplement characters
	for cp in latin1_start ..= latin1_end {
		codepoints[idx] = cp
		idx += 1
	}

	// Append Latin Extended-A characters
	for cp in latin_extended_a_start ..= latin_extended_a_end {
		codepoints[idx] = cp
		idx += 1
	}

	return codepoints
}

load_font_with_codepoints :: proc(
	file: string,
	size: i32,
	color: rl.Color,
	allocator := context.allocator,
	spacing: f32 = 2,
) -> Font {
	codepoints := gen_ascii_plus()
	file, err := strings.clone_to_cstring(file, allocator)

	// NOTE: If an allocation error occurs like this, just panic
	assert(err == nil, "Allocation error")
	ray_font := rl.LoadFontEx(file, size, &codepoints[0], i32(len(codepoints)))

	font := Font {
		ray_font   = ray_font,
		size       = size,
		spacing    = spacing,
		color      = color,
		char_width = rl.MeasureTextEx(ray_font, "M", f32(size), spacing).x,
	}

	assert(font.size > 0, "Invalid font size")

	return font
}

// 
// Helpers
// 

is_char_supported :: proc(char: rune) -> bool {
	return !unicode.is_control(char)
}

// Returns the index of the start of the rune that ends at position `pos`.
// Assumes that `pos` is a valid boundary in the UTF-8 buffer.
prev_rune_start :: proc(data: []u8, pos: int) -> int {
	assert(pos >= 0, "Position must be greater or equal than 0")

	i: int = pos - 1
	// Move backwards until a byte that is not a continuation is found (i.e. not 10xxxxxx).
	for ; i > 0; i -= 1 {
		if (data[i] & 0xC0) != 0x80 do break
	}

	return i
}

// Returns the length in bytes of the rune starting at position `pos`.
// Uses the std's UTF-8 decoding.
next_rune_length :: proc(data: []u8, pos: int) -> int {
	assert(len(data) >= pos, "The length of the data should be greater or equal than the position")

	_, n_bytes := utf8.decode_rune(data[pos:])
	return n_bytes
}

is_whitespace_byte :: proc(b: u8) -> bool {
	return b == ' ' || b == '\t' || b == '\n' || b == '\r'
}

// Could not name this thing better kkkkkkkkkkkk
is_whitespace_rune_2 :: proc(r: rune) -> bool {
	return r == ' ' || r == '\t' || r == '\n' || r == '\r'
}

is_whitespace_rune :: proc(r: rune) -> bool {
	return unicode.is_space(r)
}

is_word_character :: proc(r: rune) -> bool {
	return unicode.is_alpha(r) || unicode.is_digit(r) || r == '_'
}

