# Roadmap

Planned and proposed work for insights.nvim. Items are not ordered by
priority.

Nothing currently open. The multi-language import scan (Python, JS/TS, Go,
Rust, C/C++) and the imports backlog (picker output, reverse view, unused-
import detection) shipped — see [commands.md](commands.md#imports) and
[architecture.md](architecture.md).

`:Insights imports graph` also shipped: the dependency data `imports`
already collects, rendered as a Graphviz PNG and shown via images.nvim
(from images.nvim's own `docs/ROADMAP/CROSS-PLUGIN.md` — see
[commands.md](commands.md#graph-view)). Deliberately scoped to that one
graph-shaped dataset; call-tree/symbol-distribution graphs would need new
analysis this plugin doesn't have yet, not just a new view over existing
data.
