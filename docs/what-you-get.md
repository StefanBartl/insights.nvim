# What you get with the defaults

| Command | Does |
| --- | --- |
| `:Insights symbols` | ripgrep/Tree-sitter symbol index and picker: functions, Lua tables, string literals |
| `:Insights metrics` | Lua code metrics report |
| `:Insights smells` | Magic numbers and unconfigured behaviour constants |
| `:Insights imports` | Import/require usage across Lua, Python, JS/TS, Go, Rust, C/C++ |
| `:Insights imports reverse <module>` | Every file that imports a given module |
| `:Insights imports unused` | Bound import names never referenced again in their file |
| `:Insights imports graph` | The dependency graph, rendered as a PNG |
| `:Insights tree` / `count` / `clipboard` | Write, count, or copy the project file tree |
| `:Insights fileinfo` | Toggle an `fs.stat` float for the current buffer |
| `:Insights cache build` / `info` / `clear` | Rebuild, inspect or clear the symbol cache |
| `:Insights compress [path] [outdir]` | Archive a directory — tar, zip or PowerShell, engine auto-detected |
| `:Insights conflicts` | Unresolved git conflicts to the quickfix list; also runs on `VimEnter` |
| `:Insights unimported` | Used-but-unimported components in the current buffer |
| `:Insights devserver list` / `kill` | Dev servers started from Neovim |

Plus one thing with no command at all: who imports the module under the cursor,
in [hover.nvim](https://github.com/StefanBartl/hover.nvim)'s float — out of a
scan that already ran, never starting one.

The full surface, with flags and symbol types, is [commands.md](commands.md).
