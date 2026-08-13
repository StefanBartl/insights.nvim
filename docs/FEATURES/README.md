# Features

insights.nvim combines ripgrep-based symbol indexing, Tree-sitter Lua
scanning, code metrics, file-tree utilities, and buffer info into a single
`:Insights` command. See the [project README](../../README.md) for
install/quickstart, or [`docs/architecture.md`](../architecture.md) for
the source-tree layout.

- [Code inspection](CODE-INSPECTION.md) — symbols, metrics, imports: the
  three modules that answer "what does this codebase look like".
- [Project utilities](PROJECT.md) — file tree, buffer info, compression,
  the symbol cache.
- [Automatic checks](AUTOMATION.md) — conflicts, unimported components,
  dev-server tracking: the three modules that also run on their own.
