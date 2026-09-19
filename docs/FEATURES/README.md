# Features

insights.nvim combines ripgrep-based symbol indexing, Tree-sitter Lua
scanning, code metrics, file-tree utilities, and buffer info into a single
`:Insights` command. See the [project README](../../README.md) for
install/quickstart, or [`docs/architecture.md`](../architecture.md) for
the source-tree layout.

Every question here is one you can answer by reading the source — which is
exactly why nobody does. "Who imports this?", "is this import still used?",
"which numbers in this file are magic?" are cheap to ask and expensive to
answer by hand, and they go unasked until something breaks. `:Insights` is
the one command that asks them:

| Area | Answers |
| --- | --- |
| **Symbols** | A ripgrep/Tree-sitter index of functions, Lua tables and string literals, behind a picker |
| **Imports** | Usage across Lua, Python, JS/TS, Go, Rust and C/C++ — a report, a reverse lookup, unused-import detection, and a rendered dependency graph |
| **Code** | Lua metrics, and smells: magic numbers and behaviour constants that should have been configuration |
| **Project** | The file tree written, counted or copied; per-buffer `fs.stat`; directory compression with the engine auto-detected |
| **Todos** | Annotation comments (`TODO`, `FIX`, `AUDIT`, …, with aliases) across the tree as a picker or quickfix report, and coloured in the buffer with a sign as you read |
| **Automatic** | Git conflicts to the quickfix list on `VimEnter`, used-but-unimported components in the current buffer, dev servers started from Neovim that are still running, and the annotation highlight above |

The symbol index is cached, and the cache is explicit rather than magic:
`:Insights cache build`, `info`, `clear`. That matters for the hover
contribution — a cold index says nothing rather than starting a scan behind
your back, and a module nobody imports produces silence rather than a
misleading zero. The reasoning is [../hover.md](../hover.md).

It reads the source text. What was *actually called* at runtime is a different
question, and a parser cannot answer it — see
[runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim).

- [Code inspection](CODE-INSPECTION.md) — symbols, metrics, imports: the
  three modules that answer "what does this codebase look like".
- [Project utilities](PROJECT.md) — file tree, buffer info, compression,
  the symbol cache.
- [Automatic checks](AUTOMATION.md) — conflicts, unimported components,
  dev-server tracking, annotation highlighting: the four modules that also
  run on their own.
