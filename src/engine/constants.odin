package engine

import rl "vendor:raylib"

// 
// Colors
// 
BACKGROUND_COLOR :: rl.Color{28, 28, 28, 255}
TEXT_COLOR :: rl.Color{235, 219, 178, 255}
SPLIT_COLOR :: rl.Color{60, 60, 60, 255}
HIGHLIGHT_COLOR :: rl.Color{100, 100, 255, 100}
SELECTION_COLOR :: rl.Color{255, 255, 0, 100}
CURSOR_COLOR :: rl.GRAY
COMMAND_BUFFER_CURSOR_COLOR :: rl.RED
TEMP_HIGHLIGHT_COLOR :: rl.Color{200, 200, 255, 255} // Light blue for temporary highlight

SCROLL_SMOOTHNESS :: 0.2
DEFAULT_FONT_SIZE :: 20
MIN_FONT_SIZE :: 10
MAX_FONT_SIZE :: 100
MESSAGE_DURATION :: 2.0
MARGIN_Y :: 100.0
MARGIN_X :: 50.0
LINE_NUMBER_PADDING :: 5.0
GAP :: 30.0 // Additional gap between line numbers and text.
INDENT_SIZE :: 4
SELECT_COMMAND_STRING :: "Pattern:"
SEARCH_COMMAND_STRING :: "Search:"
