const rl = @import("raylib");
const std = @import("std");

pub fn main() !void {
    const screenWidth = 800;
    const screenHeight = 450;

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(screenWidth, screenHeight, "raylib-zig [text] example - multi-font text");
    defer rl.closeWindow();

    var chars: [193]i32 = undefined;
    var index: usize = 0;

    // Add ASCII range (32-126)
    var i: u21 = 32;
    while (i <= 126) : (i += 1) {
        chars[index] = @intCast(i);
        index += 1;
    }

    // Add specific Japanese characters
    chars[index] = 0x3044; // い
    index += 1;
    chars[index] = 0x306F; // は
    index += 1;

    // Add Hiragana block (U+3040-U+309F)
    i = 0x3040;
    while (i <= 0x309F) : (i += 1) {
        chars[index] = @intCast(i);
        index += 1;
    }

    const font = try rl.loadFontEx("fonts/NotoSansJP-VariableFont_wght.ttf", 100, chars[0..index]);
    defer rl.unloadFont(font);

    const background_color = rl.Color.fromInt(0x282828FF);
    const text_color = rl.Color.fromInt(0xEBDBB2FF);
    
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(background_color);

        rl.drawTextEx(font, "hello world \u{306F} \u{3044} こんにちは çç", .{ .x = 10, .y = 10 }, @floatFromInt(font.baseSize), 1, text_color);
    }
}
