# Features of interest for filetree.nvim

Features implemented in insights.nvim that are relevant to a
filetree/file-manager plugin (Neotree, NvimTree, Netrw, or `filetree.nvim`
itself). Listed for later re-implementation in `filetree.nvim`,
**cross-platform** and **filetree-manager agnostic** — not to be pulled in
as a dependency on insights.nvim.

| Feature | Origin | Where it fits in a filetree | Notes |
|---|---|---|---|
| Async project file tree → file / clipboard | [tree/init.lua:76](../../lua/insights/tree/init.lua#L76), [:99](../../lua/insights/tree/init.lua#L99), [:116](../../lua/insights/tree/init.lua#L116) | "Export tree" action on the root node | Async via `vim.system`; platform dispatch is PowerShell on Windows, `find`+`sed` on Unix. Exclude patterns are configurable. Could become a Neotree/NvimTree command bound to the root node. |
| Directory compression (`tar`/`zip`/PowerShell `Compress-Archive`) | [compress/init.lua:127](../../lua/insights/compress/init.lua#L127) | "Compress" action on a directory node (context menu) | Engine auto-selects by platform; writes archive + `file-list.txt` into a `compressed/` subdir; `.git/` excluded automatically. Natural fit for a right-click/action-menu entry on folders. |
| Buffer/file info float (`fs.stat` metadata) | [fileinfo/init.lua:86](../../lua/insights/fileinfo/init.lua#L86) | "File info" action on the node under cursor | Currently reads the *current buffer's* path; for a filetree it would read the *node under cursor* instead. Shows size, mtime, permissions, type. |
| File/dir count under a path | [tree/init.lua:99](../../lua/insights/tree/init.lua#L99) | Status line / footer count for the current root or a selected subtree | Respects the same exclude patterns as the tree export. |

## Not relevant to filetree.nvim

- `symbols` (ripgrep/Tree-sitter symbol index) — editor/code-navigation
  feature, not a file-tree concern.
- `metrics` (Lua code statistics) — code-quality feature, not file-tree.
- `imports` (require() analysis) — code-navigation feature, not file-tree.
