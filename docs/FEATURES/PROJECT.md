# Project utilities

## File tree

Writes an async-built project file tree to a configured output file, or
counts project files, or copies the tree file's content straight to the
system clipboard.

```vim
:Insights tree         " write project tree to configured output file
:Insights count        " count project files
:Insights clipboard    " copy tree file content to system clipboard
```

- **Module:** `tree/init.lua`
- **Usercmds:** `:Insights tree`, `:Insights count`, `:Insights clipboard`
- **Config:** `opts.tree.enable` (default `true`),
  `opts.tree.exclude_patterns` (default `*/.git/*`, `*/node_modules/*`,
  `*/.cache/*`), `opts.tree.outdir` (default
  `stdpath("state") .. "/insights/tree"`), `opts.tree.outfile_fmt`
  (default `"%s-tree.txt"`)

## Buffer file info

A floating window with `fs.stat` metadata (size, permissions, timestamps)
for the current buffer.

- **Module:** `fileinfo/init.lua`
- **Usercmds:** `:Insights fileinfo`
- **Keymaps:** `<leader>fi` (`fileinfo.keymap`)
- **Config:** `opts.fileinfo.enable` (default `true`)

## Compress project directory

Compresses a project directory into a `compressed/` sub-directory (or
`compress.outdir` if set) alongside a `file-list.txt`, excluding `.git/`
automatically. Engine is configurable or auto-detected per platform.

```vim
:Insights compress                " compress cwd with configured engine
:Insights compress /path/to/dir   " compress a specific directory
:Insights compress . ~/backups    " compress cwd, write to ~/backups/
```

| Engine | Produces | Platform |
|---|---|---|
| `tar` | `.tar.gz` | Unix/macOS |
| `zip` | `.zip` | Unix/macOS |
| `powershell` | `.zip` | Windows |
| `auto` (default) | tar on Unix, powershell on Windows | any |

- **Module:** `compress/init.lua`
- **Usercmds:** `:Insights compress [path] [outdir]`
- **Config:** `opts.compress.enable` (default `true`),
  `opts.compress.engine` (default `"auto"`), `opts.compress.outdir`
  (default `""` — places `compressed/` next to the source directory)

## Buffer-local report ergonomics

Every `insights://…` scratch report buffer (metrics, symbols, imports, …)
shares a small set of buffer-local keymaps for closing and following
`path:line` references without leaving the report.

- **Module:** `ui/scratch.lua`
- **Keymaps:** `q`, `<Esc>` (`ui.close_keys`) close; `gf` (`ui.follow_key`)
  follows `path:line` on the current line
