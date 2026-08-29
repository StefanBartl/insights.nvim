# Commands

## Unified command

```
:Insights <subcommand> [args]
```

Tab-completion works at every level. Built via `lib.nvim.bindings.usercmd.composer`:
the route tree in `lua/insights/bindings/usrcmds.lua` drives dispatch
and `<Tab>` completion from one source, forwarding to the same handler
functions as before (byte-for-byte unchanged dispatch/parsing). Two
user-visible changes from this: an unknown subcommand now reports composer's
own "unknown subcommand" usage block (every registered command, one per
line) instead of the old one-line hint; and `metrics`' flags only complete
once you've typed the leading `--` (previously offered alongside directory
names at every position).

### Symbol index

```vim
:Insights symbols                       " cwd scope, best available picker
:Insights symbols cwd                   " explicit cwd scope
:Insights symbols buffer                " current buffer only
:Insights symbols telescope             " force telescope
:Insights symbols fzf                   " force fzf-lua
:Insights symbols scratch               " scratch buffer (no picker needed)
:Insights symbols cwd telescope         " scope + picker
:Insights symbols rebuild               " force cache rebuild, then open picker

" Lua-specific Tree-sitter scanners (tables and string literals)
:Insights symbols buffer tables         " Lua table definitions in current buffer
:Insights symbols cwd tables            " Lua table definitions across cwd
:Insights symbols buffer strings        " Lua string literals in current buffer
:Insights symbols cwd strings           " Lua string literals across cwd
:Insights symbols buffer functions      " Lua functions (explicit; same as default for Lua)
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
:Insights metrics                        " full report for cwd
:Insights metrics /path/to/dir           " analyze a specific directory
:Insights metrics --ratios --deviations  " emphasize the ratio analysis
:Insights metrics --lua-only --no-top     " Lua only, skip top-N lists
:Insights metrics --misc-only --misc-detailed  " only docs (md/txt/json)
:Insights metrics --numbers-only /path   " raw counts, no percentages
:Insights metrics --current              " analyze the current buffer only
```

Without an argument the current working directory is analyzed. Pass a directory
to analyze it instead (tab-completion suggests directories and flags) — useful
when the editor's cwd differs from the project you want to measure. The report
is also written to `metrics.output_file` (default:
`{state}/insights/metrics.md`) — ending it in `.pdf` instead writes a PDF via
[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) (optional
dependency, needs pandoc + a PDF engine) rather than plain text.

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

### Code smells

```vim
:Insights smells                        " both scans, cwd
:Insights smells /path/to/dir           " analyze a specific directory
:Insights smells --magic-numbers-only   " skip the hardcoded-constants scan
:Insights smells --constants-only       " skip the magic-numbers scan
```

Two scans, distinct from `metrics`'s size/ratio analysis — candidates, not
verdicts, for both:

- **Magic numbers**: a number written straight into a call with no name to
  hold a config key against — `vim.defer_fn(fn, 3000)`, `vim.wait(500)`,
  `timer:start(N, N)`, `timeout = N`, `vim.o.columns * 0.N`,
  `vim.o.lines * 0.N`. A `defer`/`wait`/`timer` value of 50 or under is
  "get off the current tick", not a preference, and is never flagged.
- **Hardcoded constants**: a module-level `local NAME = VALUE` whose name
  describes behaviour (timeout, delay, limit, width, count, …) and whose
  value is either `SCREAMING_CASE` or a plain integer other than `0`/`1`,
  but which never made it into the project's own config surface (any file
  under `config/`/`@types/`, or named `*defaults*`/`config/init.lua`) —
  checked by name, with a leading underscore and a `default_` prefix
  stripped before the lookup.

Promoted from two throwaway Python scripts
(`docs/ROADMAP/tools/magic_numbers.py` / `hardcoded_constants.py` in
nvim-config) that walked every sibling `.nvim` repo at once; this scans one
project — the same `cwd`/directory scope `metrics` already uses.

### File tree

```vim
:Insights tree         " write project tree to configured output file
:Insights count        " count project files
:Insights clipboard    " copy tree file content to system clipboard
```

### Buffer file info

```vim
:Insights fileinfo     " toggle fs.stat float for current buffer
```

### Symbol cache

```vim
:Insights cache build  " rebuild symbol cache for current cwd
:Insights cache info   " show cache statistics
:Insights cache clear  " delete cache for current cwd
```

### Compress

```vim
:Insights compress                " compress cwd with configured engine
:Insights compress /path/to/dir   " compress a specific directory
:Insights compress . ~/backups    " compress cwd, write to ~/backups/
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
:Insights imports                  " all import/require calls, all languages
:Insights imports python           " only Python (aliases: py)
:Insights imports js fzf           " only JS/TS, opened in an fzf-lua picker
:Insights imports lib              " only group "lib" (config.imports.groups)
:Insights imports insights         " only modules under prefix "insights"
:Insights imports lib foo.bar      " multiple filters (OR-combined)
:Insights imports reverse insights.config   " every file that imports a module
:Insights imports unused           " bound names never referenced again
:Insights imports graph            " dependency graph as a PNG, shown via images.nvim
```

Scans source files in the cwd for import/require statements across **Lua,
Python, JavaScript/TypeScript, Go, Rust, and C/C++**, and opens a scratch
report (also written to `imports.output_file`) — or, with a trailing
`telescope`/`fzf` token, a picker over the occurrence list instead. The
report has two sections:

```
=== Imports — insights.nvim ===
total import/require calls : 153   unique modules : 61
  Lua       :  153 calls   (backend: treesitter)

--- Count ---
   23  [lua] insights.config
   20  [lua] insights.util.notify
    3  [lua] lib.nvim.fs.json               (extern)
   ...

--- Occurrences ---
lua/insights/metrics/init.lua:5   [lua] insights.util.notify   notify (.create)
lua/insights/metrics/init.lua:7   [lua] insights.config        config
...
```

- **Count**: each module with its occurrence count and language tag, sorted
  descending. Modules with no matching local source file are tagged
  `(extern)` (see the classification table below).
- **Occurrences**: every call as `path:line  [lang]  module  imported-name
  (.field)`. `gf` in the scratch buffer jumps to the `path:line`.

**Filters.** A filter token is either a module prefix (`lib` matches `lib`,
`lib.nvim`, `lib.usrcmds` — but not `mylib`; the same rule applies to `::`
paths for Rust), a named group from `imports.groups`, or a language id/alias
(`lua`, `python`/`py`, `javascript`/`js`/`ts`, `go`, `rust`/`rs`, `c`/`cpp`)
that scopes the report to just that language. Multiple filters of the same
kind are OR-combined; a language token plus a module filter combine with AND.
Tab-completion suggests group names, language ids, and the picker tokens.

**Detection backend.** Lua uses Tree-sitter by default — only genuine
`require("…")` calls in the AST are counted, so the word `require` inside
comments or string literals is ignored — falling back to a ripgrep line scan
when the Lua parser is unavailable (`imports.engine = "auto"|"treesitter"|
"ripgrep"`, Lua-only). The other five languages always use a regex/text scan
of the whole file (no Tree-sitter query implemented for them yet); it still
resolves grouped/multi-line syntax correctly — Go `import ( … )` blocks,
Python `from x import ( … )`, nested Rust `use a::{ … }`. The backend used
per language is shown in the report header.

**External classification** (`imports.classify_external`) is per language:

| Language | Local iff | External example |
|---|---|---|
| Lua | matching `lua/<path>.lua` or `<path>.lua`/`init.lua` under cwd | `vim`, `bit` |
| Python | relative import, or matching `<path>.py`/`__init__.py` | `os`, `typing` |
| JS/TS | relative/absolute specifier (`./x`, `/x`) | `react`, `@scope/pkg` |
| Go | matches (or is a subpackage of) `go.mod`'s `module` path | `fmt`, `github.com/…` |
| Rust | `crate::…` / `self::…` / `super::…` | any external crate |
| C/C++ | `#include "..."` (quotes) | `#include <...>` (angle brackets) |

The scan runs asynchronously so it never blocks the editor: file discovery
uses `rg --files-with-matches` (falling back to a plain extension glob when
ripgrep is unavailable), then reads + parses matched files in scheduled
chunks. The report opens when the scan completes.

**Go to definition.** Inside the scratch report, two extra keymaps resolve a
Lua import's required module to the file that defines it — *without*
executing `require(...)` — and reveal the definition of the accessed field
(non-Lua entries just notify that this isn't supported yet):

| Key  | Action |
|------|--------|
| `gd` | reveal the definition (jump in the current window, or a float — see `definition.view`) |
| `gp` | always reveal the definition in a floating preview |

On an **Occurrence** line (`module  name (.field)`) the jump lands on the
definition of that field — e.g. on `… insights.util.notify  notify (.create)`,
`gd` opens `notify.lua` at `function M.create(…)`. On a **Count** line it opens
the module file itself. Field location is Tree-sitter-accurate (it understands
`function M.f()`, `M.f = function`, `local f = …`, and table fields), with a
regex fallback when the Lua parser is unavailable. Module resolution searches
project-local `lua/` paths first, then the Neovim loader cache, `package.path`,
and the runtimepath. Configure the view, float border, and keys under
`imports.definition` (set a keymap to `false` to disable it).

#### Reverse view

```vim
:Insights imports reverse insights.config
```

Given a module, lists every file that imports it — the reverse lookup. Same
prefix-matching rule as the main filters. Opens a scratch buffer with
`path:line  [lang]  imported-name` per occurrence.

#### Unused imports

```vim
:Insights imports unused [filter/lang...]
```

Lists bound import names that never appear again in their file — a whole-word
textual count, not a reference analysis. False positives are possible
(re-exports via string, reflection, shadowed names); blank/wildcard bindings
(Go `_`, a bare `*`) are always skipped. Accepts the same language/module
filters as the main report.

#### Picker output

```vim
:Insights imports python telescope
:Insights imports fzf
```

A trailing `telescope`/`fzf` token opens a picker over the (filtered)
occurrence list instead of the scratch buffer — the scratch report's own
`output_file` is still written. Omit it (or pass `scratch`) for the default
scratch-buffer view.

#### Graph view

```vim
:Insights imports graph
:Insights imports python graph
```

A trailing `graph` token renders the same (filtered) import data as a
Graphviz dependency graph instead of a text report — every entry is already
an edge (`filename` imports `module`), just never drawn as one until now.
Nodes: importing files (filled blue) and, only with
`imports.graph.include_external = true` (default off — a real project
imports far more external modules than it has source files, and drawing
them turns the graph into noise instead of showing project structure),
external modules (dashed grey). Rendered to
`imports.graph.outdir`/`<project>-imports.png` via the Graphviz CLI
(`imports.graph.layout`, default `"dot"` — needs Graphviz installed, no
pure-Lua substitute exists for laying out a graph) and shown inline through
[images.nvim](https://github.com/StefanBartl/images.nvim) if installed,
else just reported as a file path to open manually.

Deliberately scoped to the dependency graph only — the only place in
insights.nvim where the data is already graph-shaped (an edge list).
Call-tree and symbol-distribution graphs (the original cross-plugin idea) don't exist as data anywhere else in this plugin;
`symbols` is a flat, uncorrelated list, and building that analysis from
scratch is a separate, much larger feature than rendering data insights.nvim
already collects.

### Conflicts

```vim
:Insights conflicts
```

Asks git for files in the unmerged state (`git diff --diff-filter=U`) and puts
them in the quickfix list, then `:copen`. Runs automatically on `VimEnter` —
see [Automatic triggers](automatic-triggers.md).

### Unimported

```vim
:Insights unimported
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
:Insights devserver list   " tracked servers in this session
:Insights devserver kill   " kill them all now
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
| `table` | Lua table constructor (`:Insights symbols … tables`) |
| `string` | Lua string literal (`:Insights symbols … strings`) |
