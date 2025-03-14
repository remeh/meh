# meh

meh is remeh's personal code editor.

Developed in Zig.

Uses SDL2 for accelerated rendering and SDL2_ttf to load TTF files.

Executes `ripgrep` to search through files, `fd` to find files and
`git` for file changes display.

Use `zig 0.14.0` to compile.

## Demo Video

[Link to YouTube](https://www.youtube.com/watch?v=ewE9DWePxZ4)

## Features

* Modal vim-ish editor. Not vim-compliant: remeh-compliant.
* HiDPI support, smooth font rendering. SDL2 accelerated rendering.
* UTF8.
* LSP support: go to definition, references, completion, info/doc.
* Ripgrep & Fd integration.
* File status (added, modified)
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

