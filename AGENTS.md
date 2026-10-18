# meh — Agent Guide

`meh` is a personal code editor written in Zig. It uses SDL2 for rendering and SDL2_ttf
for font loading. External tools: `ripgrep`, `fd`, `git`.

## Build

```
zig build          # build
zig build test --summary all  # run all unit tests
```

If you need to run the binary for testing, make sure to run it in the background.

Requires **Zig 0.18-dev**. Dependencies: `SDL2`, `SDL2_ttf` (system libraries).

## Testing

Unit tests live inline in each source file (Zig's `test` blocks).
`src/tests.zig` imports all modules that contain tests.
To add tests for a module, write `test` blocks inside that `.zig` file and add an import
to `src/tests.zig` if it isn't already there.

Always run `zig build test --summary all` after making changes to verify nothing is broken.

## Code Conventions

- Allocator is passed explicitly; Use `std.testing.allocator` in tests.
- Error handling via Zig's `!` return type and `try`/`catch`. Avoid silent ignores.
- Keep SDL2 rendering code in `draw.zig`; keep editor logic free of SDL types.
- Widgets own their render and input-handling logic. Each widget file is self-contained.
- LSP communication is asynchronous; messages cross thread boundaries through `atomic_queue.zig`.
- No tree-sitter: syntax highlighting is done by hand in `syntax_highlighter.zig`.

## What to Avoid

- Do not add external Zig dependencies (no `build.zig.zon` packages).
- Do not introduce horizontal splits: the editor intentionally supports one vertical split only.
- Do not touch `src/macos/` unless specifically working on macOS packaging.
- Do not use fuzzy search— file navigation is intentionally directory-based.
