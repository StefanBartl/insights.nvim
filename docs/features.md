# Features

| Module | What it does |
|--------|-------------|
| **symbols** | Ripgrep symbol index (11 languages) + Tree-sitter Lua scanner for functions, tables, and string literals; telescope / fzf-lua / scratch picker |
| **metrics** | Lua file statistics: lines, comments, annotations, word counts, ratios per file and folder |
| **tree** | Async project file tree (write to file / count / copy to clipboard) |
| **fileinfo** | Floating window with `fs.stat` metadata for the current buffer |
| **cache** | CWD-keyed JSON cache for the symbol index (TTL-based, mtime-aware) |
| **compress** | Compress a project directory — configurable engine: `tar` (.tar.gz), `zip`, or PowerShell (.zip) |
| **imports** | Count and list `require()` calls across Lua files — Tree-sitter-accurate (ignores `require` in comments/strings), per-module counts, every occurrence with imported name/field and `path:line`, with prefix/group filters |
| **conflicts** | Populate the quickfix list with files holding unresolved merge conflicts |
| **unimported** | Warn on component tags (`<Foo />`) used but never imported — astro / jsx / tsx / vue / svelte |
| **devserver** | Notice dev servers started in a Neovim terminal and offer to kill them on exit |

Unlike the others, these last three can also run **automatically** — see
[Automatic triggers](automatic-triggers.md).

See [Installation](installation.md) for requirements and setup.
