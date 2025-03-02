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
- [ ] Visual mode.
- [ ] Visual line mode.
- [ ] Visual block mode (I probably want to develop this the way Zed does it, with multiple cursors).

### Emacs
- [ ] That whole mark thing (which is basically visual mode, so no worries here).

### Editing
- [ ] Multiple cursors (absolute must have, similar to Zed).
- [ ] Macros?
- [ ] Clipboard interaction.
- [ ] Undo/Redo.
- [ ] Search.
- [ ] Substitute (probably like Emacs as well).

### Windows
I'm not so clear as well as how the window management on this editor will look like.
I have considered something simple as Focus, only allowing for one vertical split, since I find that is really the only split I do, but would not hurt (and maybe even be fun) to implement more complex window behavior, I do know however:
- [ ] Resizable windows.
- [ ] Vertical splits.
- [ ] There should only be one status line in the entire editor, but it should update the file name and information depending upon which window it's at.

### UI
Also not so sure about this, but generally speaking:
- [ ] I want to be able to render images.
- [ ] Maybe I'll create something like the scratch or home buffer, similar to Emacs.
- [ ] Buffer management system, also probably copying this from emacs.
- [ ] Some direct copy of oil.nvim or dired from emacs. This thing is just too cool (will act as my file manager).
- [ ] Indentation control.
- [ ] Auto pairs?
- [ ] Mouse control.

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
- [ ] Some sort of simulation to test the functionalities of the editor (similar to how Jonathan Blow does it in his games).

### AI
Interesting...
