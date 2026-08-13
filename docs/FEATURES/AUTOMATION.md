# Automatic checks

Everything else in insights.nvim only acts when you run an `:Insights`
subcommand. These three also run on their own, each switched off with its
own `enable` key — see [`../automatic-triggers.md`](../automatic-triggers.md)
for the full config knobs (event overrides, patterns, prompts).

## Merge conflict detection

Populates the quickfix list with files holding unresolved git merge
conflicts. Silent when the repo is clean or not a git repo.

- **Module:** `conflicts/init.lua`
- **Usercmds:** `:Insights conflicts`
- **Autocmds:** `VimEnter` (configurable via `conflicts.events`)
- **Config:** `opts.conflicts.enable` (default `true`),
  `opts.conflicts.diff_filter` (default `"U"`), `opts.conflicts.open_qf`
  (default `true`), `opts.conflicts.notify` (default `true`)

## Unimported component check

Warns on component tags (`<Foo />`) used but never imported, for
astro/jsx/tsx/vue/svelte files.

- **Module:** `unimported/init.lua`
- **Usercmds:** `:Insights unimported`
- **Autocmds:** `BufWritePost` (configurable via `unimported.events`)
- **Config:** `opts.unimported.enable` (default `true`),
  `opts.unimported.filetypes` (astro, javascriptreact, typescriptreact,
  vue, svelte), `opts.unimported.ignore` (component names to never report)

## Dev-server tracking

Notices dev servers started in a Neovim terminal (matching
`devserver.patterns` — `npm run dev`, `astro dev`, `vite`, …) and offers to
kill them on exit. Only terminals this Neovim instance started are
tracked: the kill targets that terminal's recorded PID (`taskkill /T` on
Windows, `kill -TERM -<pid>` elsewhere), never a name-based sweep across
the whole machine. Detection relies on the terminal's title being set via
OSC 0/2 (most dev servers do this); starting the server as the terminal's
own command (`:terminal npm run dev`) always works, a command typed into
an already-open shell only if it sets the title.

- **Module:** `devserver/init.lua`
- **Usercmds:** `:Insights devserver [list|kill]`
- **Autocmds:** `TermOpen`, `TermRequest` (detection), `VimLeavePre` (kill)
- **Config:** `opts.devserver.enable` (default `true`),
  `opts.devserver.prompt` (default `true`), `opts.devserver.kill_on_exit`
  (default `true`, used when `prompt = false`), `opts.devserver.patterns`
