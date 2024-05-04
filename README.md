# meh

meh is remeh's personal code editor.

Developed in Zig.

Uses SDL2 for accelerated rendering and SDL2_ttf to load TTF files.
Executes `ripgrep` to search through files.

Use `zig 0.12.0` to compile.

## Features

* Modal vim-ish editor. Not vim-compliant: remeh-compliant.
* HiDPI support, smooth font rendering. SDL2 accelerated rendering.
* LSP support: go to definition, references, completion, info/doc.
* Ripgrep integration.
* Hard-coded fast syntax highlighter. No tree-sitter integration.
* Highlight a word using the mouse.
* Open files navigating through directories. No fuzzy search.
* Vertical split. One. No horizontal split.
* Undo & redo.

## Documentation

Not available, open an issue.

## Tests

In order to run all the tests:

```
$ zig build test --summary all
```

## LICENSE

MIT License
Copyright (c) 2022 Remy Mathieu

