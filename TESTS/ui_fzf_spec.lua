-- TESTS/ui_fzf_spec.lua — insights.ui.fzf: the "backend missing" guard, the
-- entries-to-lines shape fzf-lua is handed, and the default action's own
-- path:line parsing.
--
-- fzf-lua itself is not a dependency of this plugin and is not checked out in
-- CI, so `fzf.fzf_exec` is never really called: a stand-in captures the
-- arguments `M.open` builds instead. That is enough to drive the module's
-- only real branching logic for real -- the format string and, especially,
-- the default action's own `sel[1]:match(...)` -- without a live picker.

return function(H)
  local real_fzf_lua = package.loaded["fzf-lua"]
  package.loaded["fzf-lua"] = nil
  package.loaded["insights.ui.fzf"] = nil
  local fzf = require("insights.ui.fzf")

  local ok_body, err_body = pcall(function()
    -- ── backend missing ───────────────────────────────────────────────────
    -- fzf-lua genuinely is not installed in this test runtime (nothing
    -- stubbed it yet), so this exercises the real guard, not a fake one.
    H.ok(pcall(fzf.open, {}, "t"), "with no fzf-lua installed, open() does not error")

    -- ── the entries → lines shape, and the call fzf-lua is handed ─────────
    local captured
    package.loaded["fzf-lua"] = {
      fzf_exec = function(lines, opts)
        captured = { lines = lines, opts = opts }
      end,
    }

    local entries = {
      { filename = "lua/foo.lua", lnum = 3, func_type = "local", name = "alpha" },
    }
    fzf.open(entries, "My Symbols")
    H.eq(captured.lines[1], "lua/foo.lua:3  [local] alpha", "path:line [type] name, one per entry")
    H.contains(captured.opts.prompt, "My Symbols", "the title reaches the prompt")
    H.eq(captured.opts.previewer, "builtin", "the builtin previewer is used")
    H.eq(captured.opts.winopts.preview.default, "builtin", "and named again in winopts")
    H.ok(captured.opts.actions["default"], "a default action is wired")

    fzf.open({}, nil)
    H.contains(captured.opts.prompt, "Project Symbols", "a nil title falls back to the default")

    -- ── the default action's path:line parsing ────────────────────────────
    local dir, cleanup = H.fixture("ui-fzf")
    local target = dir .. "/target.lua"
    vim.fn.writefile({ "one", "two", "three", "four" }, target)

    local run_default = function(line)
      vim.cmd("silent! %bwipeout!")
      captured = nil
      fzf.open({ { filename = "x", lnum = 1, func_type = "f", name = "n" } }, "t")
      -- The line fzf-lua would hand back to the action is whatever it
      -- displayed -- here, the one line `M.open` itself built, with the
      -- entry's filename swapped out for the path under test. Same shape a
      -- real selection carries: a one-element list.
      captured.opts.actions["default"]({ line })
    end

    -- A plain relative path (what `rg` prints on Unix, and what the imports
    -- report always writes) works.
    local rel = "TESTS/.fixture-ui-fzf/target.lua"
    run_default(rel .. ":2  something")
    H.contains(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), "target.lua", "gf opens the file")
    H.eq(vim.api.nvim_win_get_cursor(0)[1], 2, "at the line the entry named")

    -- BUG regression: an *absolute Windows* path carries a colon of its own
    -- (`E:\…`), which `^([^:]+):(%d+)` alone stops at -- the file field ends
    -- at the drive letter and the line number is then hunted for in the rest
    -- of the path, so the match fails outright and the action does nothing.
    -- Same blind spot `symbols/parser.lua`'s vimgrep reader and
    -- `ui/scratch.lua`'s follow key both had (see TESTS/README.md); fzf-lua's
    -- default action gets the exact same absolute paths, straight from rg via
    -- symbols/rg_index.lua, and had not been fixed. Now handled the same way:
    -- try the drive-prefixed shape first.
    local abs = vim.fn.fnamemodify(target, ":p")
    run_default(abs .. ":3  something")
    H.contains(
      vim.fs.normalize(vim.api.nvim_buf_get_name(0)),
      "target.lua",
      "an absolute path is followed too"
    )
    H.eq(vim.api.nvim_win_get_cursor(0)[1], 3, "at the line it named")

    -- A line with no path:line on it is not a jump: the buffer stays put.
    vim.cmd("silent! %bwipeout!")
    local before = vim.api.nvim_buf_get_name(0)
    run_default("no colon or line number here")
    H.eq(vim.api.nvim_buf_get_name(0), before, "no match means no edit")

    cleanup()
  end)

  package.loaded["fzf-lua"] = real_fzf_lua

  if not ok_body then
    error(err_body, 0)
  end
end
