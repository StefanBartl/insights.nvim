# Commands

## Unified command

```
:ProjectInsight <subcommand> [args]
```

Tab-completion works at every level.

### Symbol index

```vim
:ProjectInsight symbols                       " cwd scope, best available picker
:ProjectInsight symbols cwd                   " explicit cwd scope
:ProjectInsight symbols buffer                " current buffer only
:ProjectInsight symbols telescope             " force telescope
:ProjectInsight symbols fzf                   " force fzf-lua
:ProjectInsight symbols scratch               " scratch buffer (no picker needed)
:ProjectInsight symbols cwd telescope         " scope + picker
:ProjectInsight symbols rebuild               " force cache rebuild, then open picker

" Lua-specific Tree-sitter scanners (tables and string literals)
:ProjectInsight symbols buffer tables         " Lua table definitions in current buffer
:ProjectInsight symbols cwd tables            " Lua table definitions across cwd
:ProjectInsight symbols buffer strings        " Lua string literals in current buffer
:ProjectInsight symbols cwd strings           " Lua string literals across cwd
:ProjectInsight symbols buffer functions      " Lua functions (explicit; same as default for Lua)
```

The `[type]` argument selects the symbol kind:

| Type | Scanner | What is found |
|------|---------|---------------|
| `functions` | rg + optional TS | function declarations and assignments (default) |
| `tables` | Tree-sitter | table constructor assignments, dot-index paths, table fields |
| `strings` | Tree-sitter | unique string literals (useful for auditing magic strings, require paths, event names) |

`tables` and `strings` require `nvim-treesitter` with the `lua` parser installed.
Arguments can appear in any order.

In the picker:

| Key | Action |
|-----|--------|
| `<Enter>` | Jump to definition |
| `<C-p>` | Toggle preview (telescope) |
| `q` / `<Esc>` | Close (scratch buffer) |
| `gf` | Follow path:line in scratch buffer |

### Code metrics

```vim
:ProjectInsight metrics                        " full report for cwd
:ProjectInsight metrics /path/to/dir           " analyze a specific directory
:ProjectInsight metrics --ratios --deviations  " emphasize the ratio analysis
:ProjectInsight metrics --lua-only --no-top     " Lua only, skip top-N lists
:ProjectInsight metrics --misc-only --misc-detailed  " only docs (md/txt/json)
:ProjectInsight metrics --numbers-only /path   " raw counts, no percentages
:ProjectInsight metrics --current              " analyze the current buffer only
```

Without an argument the current working directory is analyzed. Pass a directory
to analyze it instead (tab-completion suggests directories and flags) — useful
when the editor's cwd differs from the project you want to measure. The report
is also written to `metrics.output_file` (default:
`{state}/project-insight/metrics.md`).

The report contains:

| Section | Content |
|---------|---------|
| **Total / Folder / File tables** | Lines (`L1` code, `L2` comments, `L3` no-annotations, `L4` annotations, `L5` blank) and words (`W1`–`W5`), each as count and/or percentage |
| **Folder ratios** | Comment %, annotation %, doc %, code %, avg lines/file, annotation-to-comment ratio — with deviations from the project's global averages |
| **Top-N lists** | Largest files by lines and by words; folders ranked by annotation ratio |
| **Ratio guidelines** | Heuristic healthy ranges for each ratio |
| **Documentation & config files** | Markdown / TXT / JSON file, line, and word counts (summary + optional per-file detail) |

Behavior is configurable both per-invocation (flags) and globally (`metrics.*`
in `setup()`): analysis scope (`analyze_lua`, `analyze_misc`), which sections
appear (`show_file_tables`, `show_folder_tables`, `show_total_summary`,
`show_ratios`, `show_deviations`, `show_top_lists`, `show_misc_detailed`),
display (`percent_mode` = `both`/`percent`/`numbers`, `reverse_order`, `top_n`,
`col_width`), and `exclude_type_files`.

Flags: `--ratios`/`--no-ratios`, `--deviations`, `--lua-only`, `--misc-only`,
`--no-misc`, `--misc-detailed`, `--no-top`, `--top-files-lines-only`,
`--top-files-words-only`, `--percent-only`, `--numbers-only`, `--reverse`,
`--topn=N`, `--colwidth=N`, `--file=PATH`, `--current`.

### File tree

```vim
:ProjectInsight tree         " write project tree to configured output file
:ProjectInsight count        " count project files
:ProjectInsight clipboard    " copy tree file content to system clipboard
```

### Buffer file info

```vim
:ProjectInsight fileinfo     " toggle fs.stat float for current buffer
```

### Symbol cache

```vim
:ProjectInsight cache build  " rebuild symbol cache for current cwd
:ProjectInsight cache info   " show cache statistics
:ProjectInsight cache clear  " delete cache for current cwd
```

### Compress

```vim
:ProjectInsight compress                " compress cwd with configured engine
:ProjectInsight compress /path/to/dir   " compress a specific directory
:ProjectInsight compress . ~/backups    " compress cwd, write to ~/backups/
```

Creates a `compressed/` sub-directory inside the target path (default) or
inside `compress.outdir` if set, and places the archive + `file-list.txt`
there. `.git/` is excluded automatically.

| Engine | Produces | Platform |
|---|---|---|
| `tar` | `.tar.gz` | Unix/macOS |
| `zip` | `.zip` | Unix/macOS |
| `powershell` | `.zip` | Windows |
| `auto` (default) | tar on Unix, powershell on Windows | any |

### Imports

```vim
:ProjectInsight imports                  " all require() calls in cwd
:ProjectInsight imports lib              " only group "lib" (config.imports.groups)
:ProjectInsight imports project_insight  " only modules under prefix project_insight
:ProjectInsight imports lib foo.bar      " multiple filters (OR-combined)
```

Scans every Lua file in the cwd for `require(...)` calls and opens a scratch
report (also written to `imports.output_file`). The report has two sections:

```
=== Imports — project-insight.nvim ===
total require() calls : 74   unique modules : 29   backend : treesitter

--- Count ---
   13  project_insight.util.notify
   10  project_insight.config
    1  telescope.actions               (extern)
   ...

--- Occurrences ---
lua/project_insight/metrics/init.lua:5   project_insight.util.notify   notify (.create)
lua/project_insight/metrics/init.lua:7   project_insight.config        config
...
```

- **Count**: each module with its occurrence count, sorted descending. Modules
  with no matching `.lua` file in the project are tagged `(extern)`
  (e.g. `vim`, `telescope.*`).
- **Occurrences**: every call as `path:line  module  imported-name (.field)`.
  `gf` in the scratch buffer jumps to the `path:line`.

**Go to definition.** Inside the report, two extra keymaps resolve a required
module to the file that defines it — *without* executing `require(...)` — and
reveal the definition of the accessed field:

| Key  | Action |
|------|--------|
| `gd` | reveal the definition (jump in the current window, or a float — see `definition.view`) |
| `gp` | always reveal the definition in a floating preview |

On an **Occurrence** line (`module  name (.field)`) the jump lands on the
definition of that field — e.g. on `… project_insight.util.notify  notify (.create)`,
`gd` opens `notify.lua` at `function M.create(…)`. On a **Count** line it opens
the module file itself. Field location is Tree-sitter-accurate (it understands
`function M.f()`, `M.f = function`, `local f = …`, and table fields), with a
regex fallback when the Lua parser is unavailable. Module resolution searches
project-local `lua/` paths first, then the Neovim loader cache, `package.path`,
and the runtimepath. Configure the view, float border, and keys under
`imports.definition` (set a keymap to `false` to disable it).

Filters match by module prefix: `lib` matches `lib`, `lib.nvim`,
`lib.usrcmds` — but not `mylib`. Named groups in `imports.groups` expand to a
list of prefixes. Tab-completion suggests configured group names.

**Detection backend.** By default (`imports.engine = "auto"`) the scan uses
Tree-sitter: only genuine `require("…")` calls in the AST are counted, so the
word `require` inside comments or string literals is ignored. If the Lua
Tree-sitter parser is unavailable it falls back to a ripgrep line scan (which
matches the word `require` anywhere and is therefore less precise). The active
backend is shown in the report header. Set `engine = "treesitter"` or
`"ripgrep"` to force one.

The scan runs asynchronously so it never blocks the editor: the ripgrep backend
runs `rg` as a subprocess (`vim.system`), and the Tree-sitter backend parses
files in scheduled chunks. The report opens when the scan completes.

> Currently Lua-only. Support for other languages' imports is tracked in
> [ROADMAP.md](ROADMAP.md).

### Conflicts

```vim
:ProjectInsight conflicts
```

Asks git for files in the unmerged state (`git diff --diff-filter=U`) and puts
them in the quickfix list, then `:copen`. Runs automatically on `VimEnter` —
see [Automatic triggers](automatic-triggers.md).

### Unimported

```vim
:ProjectInsight unimported
```

Reports component tags used in the current buffer with no matching import or
local definition. A tag starting with an uppercase letter (`<Card />`) is a
component reference; lowercase tags are HTML elements and ignored. A name
counts as bound if it is imported (`import Card …`, `import { Card } …`) or
declared locally (`const` / `let` / `var` / `function` / `class`).

This is a fast textual check, not a type-checker: it never reads other files,
so it cannot know whether the import actually resolves. Names you deliberately
leave unimported (globals, framework injections) go in `unimported.ignore`.

### Devserver

```vim
:ProjectInsight devserver list   " tracked servers in this session
:ProjectInsight devserver kill   " kill them all now
```

See [Automatic triggers](automatic-triggers.md) — this is mostly automatic.

## Symbol types

The symbol index uses the following type labels:

| Label | Meaning |
|-------|---------|
| `local` | `local function foo()` |
| `global` | `function foo()` / top-level `def foo():` |
| `module` | `function M.foo()` / `M.foo = function()` |
| `method` | receiver method (Go, Python class method, …) |
| `anonymous` | `const foo = () =>` / `foo = function()` |
| `exported` | `export function foo()` |
| `unknown` | pattern matched but type not inferred |
| `table` | Lua table constructor (`:ProjectInsight symbols … tables`) |
| `string` | Lua string literal (`:ProjectInsight symbols … strings`) |
