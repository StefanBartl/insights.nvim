# Features

| Module | What it does |
|--------|-------------|
| **symbols** | Ripgrep symbol index (11 languages) + Tree-sitter Lua scanner for functions, tables, and string literals; telescope / fzf-lua / scratch picker |
| **metrics** | Lua file statistics: lines, comments, annotations, word counts, ratios per file and folder |
| **tree** | Async project file tree (write to file / count / copy to clipboard) |
| **fileinfo** | Floating window with `fs.stat` metadata for the current buffer |
| **cache** | CWD-keyed JSON cache for the symbol index (TTL-based, mtime-aware) |
| **compress** | Compress a project directory — configurable engine: `tar` (.tar.gz), `zip`, or PowerShell (.zip) |
| **imports** | Count and list import/require statements across Lua, Python, JS/TS, Go, Rust, and C/C++ — Tree-sitter-accurate for Lua (regex/text scan for the rest), per-module counts, every occurrence with imported name/field and `path:line`, with prefix/group/language filters, a reverse ("who imports X") view, an unused-import heuristic, and an optional telescope/fzf picker |
| **conflicts** | Populate the quickfix list with files holding unresolved merge conflicts |
| **unimported** | Warn on component tags (`<Foo />`) used but never imported — astro / jsx / tsx / vue / svelte |
| **devserver** | Notice dev servers started in a Neovim terminal and offer to kill them on exit |

Unlike the others, these last three can also run **automatically** — see
[Automatic triggers](automatic-triggers.md).

See [Installation](installation.md) for requirements and setup.
