This file contains just some general high level ideas of things I want to implement with this editor.

# Drawing optimizations
- [ ] Dirty flag system :
    `request_redraw` for explicit changes.
    `dirty_frame` for periodic updates (cursor blink).
    `dirty` flag in `Buffer` for cached line metrics.
- [ ] Window resize handling?
- [ ] Cached line metrics - Pre-calculate line widths and lenghts during edits.
- [ ] Partial redraws - Only recalculate visible lines when scroll position changes.
- [ ] Temporal cache validation - Uses frame timing to manage blink updates

# General stuff
Aside from tasks like that the one above, I don't have that much of a clear vision to what features this editor will have.

I only have so far some general and simple ideas, so I'm just laying them out here.

### Vim
- [x] Visual mode.
- [ ] Visual line mode.
- [ ] Visual block mode (I probably want to develop this the way Zed does it, with multiple cursors).
- [x] Command buffer (execute motions like "gg", "gd", etc)
- [ ] In/out control: 
    - [x] viw
    - [x] vip/vap
    - [x] vi[delimiter]/va[delimiter]
    - [x] ciw
    - [x] cip/cap
    - [x] ci[delimiter]/ca[delimiter]
    - [x] diw
    - [x] dip/dap
    - [x] di[delimiter]/da[delimiter]

### Emacs
Emacs?

### Editing
- [ ] Multiple cursors (absolute must have, similar to Zed).
- [ ] Macros?
- [ ] Clipboard interaction.
- [ ] Undo/Redo.
- [ ] Search.
- [ ] Substitute (probably like Emacs as well).
- [ ] Tab handling - Will probably just treat tabs as spaces or something? Is this the easiest way to deal with them?
- [ ] Drag and drop a file into the editor to open it.

### Windows
01/03/25: I'm not so clear as well as how the window management on this editor will look like. I have considered something simple as Focus, only allowing for one vertical split, since I find that is really the only split I do, but would not hurt (and maybe even be fun) to implement more complex window behavior, I do know however:
06/03/25: Well, so far only one split at a time, because it was starting to be a pain to develop this. If I ever need more than 1 split at a time, I can just implement this feature, but for now, this is all there will be to windows.
- [x] Resizable windows.
- [x] Vertical splits.
- [x] Horizontal splits.
- [x] There should only be one status line in the entire editor, but it should update the file name and information depending upon which window it's at.

### UI
Also not so sure about this, but generally speaking:
- [ ] I want to be able to render images.
- [ ] Maybe I'll create something like the scratch or home buffer, similar to Emacs.
- [ ] Buffer management system, also probably copying this from emacs.
- [ ] Some direct copy of oil.nvim or dired from emacs. This thing is just too cool (will act as my file manager).
- [ ] Indentation control.
- [ ] Auto pairs?
- [ ] Mouse control.
- [ ] Not exactly UI, but hot reload?
- [ ] Zooming fonts.
- [ ] Show empty spaces as dots (similar to how emacs does it).
- [x] Line numbers.
- [x] Some cool lerp scrolling effect (something like the RAD debugger, 4coder, file pilot).

### Configuration
I want some things to be configurable and be saved at `.config/pulse`, and the only reason for that is because I like tweaking my editor quite a lot.
Probably won't be an extensive configuration, just something simple that changes a couple of constants by the command line or config file that alter the state of the editor.
Examples: Enable/disable status line, line numbers. Change colors at runtime. Change global font size.

### Fonts
This is a bit of a pain in my ass, the only font I know that can render basically everything is Noto Sans, but I have to come up with a way to use a given font to render ASCII characters, and Noto Sans to render japanese/chinese/whatever. Or maybe I can just not give much of a fuck...

### Commands
- [ ] General find file command, just like emacs.
- [ ] Some sort of fuzzy finding like telescope.
- [ ] Compile command, also like emacs, but I want to be able to set the context to which the command run, not just run in the current editor directory.
- [ ] I want a command to easily copy entire files to my clipboard.

### LSP
Must have, I have no idea how to build one of them however.

### Auto formatting
Very nice to have, also no idea how to implement it.

### Syntax highlighting
Probably use something like tree-sitter, but how exactly I'm using this from Odin?

### Internal tools
- [x] Some sort of simulation to test the functionalities of the editor (similar to how Jonathan Blow does it in his games) -> Deterministic simulation btw.
    This is probably not the right approach, and possibly a waste of time, since the "simulation" would me just actually using the editor daily and eventually bumping into the assertions.
- [x] Some kind of logging after commands were successful (probably at the right corner of the status bar).
- [ ] More detailed logging at a special buffer.

### AI
Interesting...
