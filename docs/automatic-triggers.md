# Automatic triggers

Most of the plugin only acts when you ask it to. These three also run on their
own, and each is switched off with its `enable` key:

| Feature | Fires on | Does |
|---------|----------|------|
| `conflicts` | `VimEnter` | Quickfix-lists unresolved merge conflicts. Silent when the repo is clean or not a git repo. |
| `unimported` | `BufWritePost` | Warns about used-but-unimported components, for `unimported.filetypes` only. Silent when nothing is missing. |
| `devserver` | `TermOpen`, `TermRequest`, `VimLeavePre` | Detects dev servers and kills the ones you approved on exit. |

## How the dev-server tracking works

When a terminal command matches one of `devserver.patterns` (`npm run dev`,
`astro dev`, `vite`, …), a prompt asks once whether that server should be
killed when Neovim exits. Answer yes and its process tree is killed on
`VimLeavePre`; answer no (or press `<Esc>`) and it is left alone. You are asked
once per terminal — the answer sticks for that terminal's lifetime.

**Only terminals this Neovim instance started are tracked.** The kill targets
that terminal's recorded PID — its process tree via `taskkill /T` on Windows,
its process group via `kill -TERM -<pid>` elsewhere. A server you started in
another shell or a tmux pane is never touched, because this plugin only kills
processes it can account for. That is the deliberate trade-off against a
`pkill -f "astro dev"`-style sweep, which would also kill servers that have
nothing to do with this editor session.

A command typed into an already-open shell is only detected if the program sets
the terminal title (most dev servers do, via OSC 0/2). Starting the server as
the terminal's command — `:terminal npm run dev` — always works.

To skip the prompt and always kill matching servers:

```lua
devserver = { prompt = false, kill_on_exit = true }
```
