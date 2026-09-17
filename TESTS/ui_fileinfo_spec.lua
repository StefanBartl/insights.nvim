-- TESTS/ui_fileinfo_spec.lua — the scratch buffer every text report is shown
-- in, the file-info float, and the platform helpers underneath both.
--
-- `insights.ui.scratch` requires `ui.kit` at module load, and ui.nvim is not
-- a CI checkout (only lib.nvim is), so a stand-in goes into `package.loaded`
-- before the first require. What it is used for -- the `?` cheatsheet -- is
-- then capturable as data rather than a window.
--
-- The picker adapters `ui/fzf.lua` and `ui/telescope.lua` are not covered
-- here: each is a single call into a backend that is not installed, and the
-- entry shape they are handed is already pinned where it is built
-- (`symbols_open_spec`, `imports_report_spec`). Only their "backend missing"
-- guard is checked, which is the one branch that runs without one.

return function(H)
  local config = require("insights.config")

  local real_kit = package.loaded["ui.kit"]
  local real_scratch = package.loaded["insights.ui.scratch"]

  local viewed
  package.loaded["ui.kit"] = {
    viewer = function(opts)
      viewed = opts
    end,
    confirm = function(opts)
      opts.on_answer(false)
    end,
  }
  package.loaded["insights.ui.scratch"] = nil
  local scratch = require("insights.ui.scratch")

  local ok_body, err_body = pcall(function()
    config.setup({})

    -- ── scratch.open ───────────────────────────────────────────────────────
    H.eq(scratch.open({}), nil, "nothing to display opens nothing")
    ---@diagnostic disable-next-line: param-type-mismatch
    H.eq(scratch.open(nil), nil, "and neither does nothing at all")

    vim.cmd("silent! %bwipeout!")
    local buf = scratch.open({ "first", "second" }, "Report")
    H.ok(buf, "a scratch buffer is returned")
    H.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], "first", "holding the lines")
    H.eq(vim.bo[buf].buftype, "nofile", "as a nofile buffer")
    H.eq(vim.bo[buf].modifiable, false, "read-only")
    H.eq(vim.bo[buf].swapfile, false, "with no swap file")
    H.eq(vim.bo[buf].bufhidden, "wipe", "wiped when it is left")
    H.eq(vim.api.nvim_buf_get_var(buf, "insights_scratch"), true, "and marked as one of ours")
    H.contains(vim.api.nvim_buf_get_name(buf), "insights://Report", "named after its title")
    H.eq(vim.api.nvim_win_get_buf(0), buf, "shown in the current window")

    -- The keymaps: the close keys, the follow key, and `?`.
    ---@param b integer
    ---@return table<string, boolean>
    local function lhs_set(b)
      local out = {}
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(b, "n")) do
        out[m.lhs] = true
      end
      return out
    end
    local keys = lhs_set(buf)
    H.ok(keys["q"], "q closes it")
    H.ok(keys["gf"], "the configured follow key is bound")
    H.ok(keys["?"], "and ? shows the cheatsheet")

    -- The cheatsheet lists exactly what is bound, plus itself.
    viewed = nil
    vim.api.nvim_feedkeys("?", "x", false)
    H.ok(viewed, "? opens a viewer")
    local sheet = table.concat(viewed.lines, "\n")
    H.contains(viewed.title, "Report Keys", "titled after the report")
    H.contains(sheet, "Close", "listing the close keys")
    H.contains(sheet, "Follow path:line", "the follow key")
    H.contains(sheet, "Show this help", "and itself")
    H.eq(viewed.filetype, "insights-scratch-help", "under its own filetype")

    -- Caller-supplied keymaps are bound and listed.
    local pressed
    local with_maps = scratch.open({ "a:1  line" }, "Custom", {
      keymaps = {
        {
          "n",
          "gd",
          function()
            pressed = true
          end,
          desc = "go to definition",
        },
      },
    })
    H.ok(lhs_set(with_maps)["gd"], "a caller-supplied keymap is bound")
    vim.api.nvim_feedkeys("gd", "x", false)
    H.ok(pressed, "and reaches its callback")
    viewed = nil
    vim.api.nvim_feedkeys("?", "x", false)
    H.contains(table.concat(viewed.lines, "\n"), "go to definition", "and is listed on the sheet")

    -- `follow_key = false` binds nothing for it.
    config.setup({ ui = { follow_key = false } })
    local no_follow = scratch.open({ "x" }, "NoFollow")
    H.eq(lhs_set(no_follow)["gf"], nil, "follow_key = false binds no follow key")
    viewed = nil
    vim.api.nvim_feedkeys("?", "x", false)
    H.excludes(table.concat(viewed.lines, "\n"), "Follow path:line", "and lists none")

    -- Custom close keys are honoured and reported.
    config.setup({ ui = { close_keys = { "<C-c>" }, follow_key = "gF" } })
    local custom = scratch.open({ "x" }, "Custom Keys")
    local custom_keys = lhs_set(custom)
    H.ok(custom_keys["<C-C>"] or custom_keys["<C-c>"], "a configured close key is bound")
    H.ok(custom_keys["gF"], "and a configured follow key")
    H.eq(custom_keys["q"], nil, "while the default one is not")
    config.setup({})

    -- The follow key opens `path:line` under the cursor.
    local dir, cleanup = H.fixture("ui-scratch")
    local target = dir .. "/target.lua"
    vim.fn.writefile({ "one", "two", "three" }, target)
    -- The reports write cwd-relative paths (`fnamemodify(path, ":.")`), which
    -- is what the follow key is written against.
    local rel = "TESTS/.fixture-ui-scratch/target.lua"
    vim.cmd("silent! %bwipeout!")
    scratch.open({ rel .. ":2  something" }, "Follow")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys("gf", "x", false)
    H.contains(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), "target.lua", "gf opens the file")
    H.eq(vim.api.nvim_win_get_cursor(0)[1], 2, "at the line the report named")

    -- Regression: `^([^:]+):(%d+)` alone stops at the first colon, so an
    -- *absolute Windows* path was never followed -- the drive letter's own
    -- colon ended the file field and the line number was then looked for in
    -- the rest of the path. Same blind spot as `symbols/parser.lua`'s vimgrep
    -- reader, and invisible on the imports report, whose paths are relative.
    local abs = vim.fn.fnamemodify(target, ":p")
    vim.cmd("silent! %bwipeout!")
    scratch.open({ abs .. ":3  something" }, "AbsPath")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys("gf", "x", false)
    H.contains(
      vim.fs.normalize(vim.api.nvim_buf_get_name(0)),
      "target.lua",
      "an absolute path is followed too"
    )
    H.eq(vim.api.nvim_win_get_cursor(0)[1], 3, "at the line it named")

    -- A line with no path:line on it is not a jump.
    vim.cmd("silent! %bwipeout!")
    scratch.open({ "just prose, no reference" }, "NoJump")
    local before = vim.api.nvim_buf_get_name(0)
    vim.api.nvim_feedkeys("gf", "x", false)
    H.eq(vim.api.nvim_buf_get_name(0), before, "a line with no reference goes nowhere")

    -- A sidebar-like window is never hijacked: the scratch buffer opens in a
    -- split instead of replacing, say, a file tree.
    vim.cmd("silent! %bwipeout!")
    vim.cmd("enew")
    vim.bo.buftype = "help"
    local sidebar_win = vim.api.nvim_get_current_win()
    local wins_before = #vim.api.nvim_list_wins()
    local in_split = scratch.open({ "report" }, "Split")
    H.ok(in_split, "the report still opens")
    H.ok(
      vim.api.nvim_get_current_win() ~= sidebar_win or #vim.api.nvim_list_wins() > wins_before,
      "without taking over the special window"
    )

    vim.cmd("silent! %bwipeout!")
    cleanup()

    -- ── the picker adapters' one testable branch ──────────────────────────
    local fzf = require("insights.ui.fzf")
    local telescope = require("insights.ui.telescope")
    if not pcall(require, "fzf-lua") then
      H.ok(
        pcall(fzf.open, { { filename = "a.lua", lnum = 1 } }, "T"),
        "without fzf-lua the adapter reports and returns rather than raising"
      )
    end
    if not pcall(require, "telescope.pickers") then
      H.ok(
        pcall(telescope.open, { { filename = "a.lua", lnum = 1 } }, "T"),
        "and the telescope adapter does the same without telescope.nvim"
      )
    end

    -- ── util.platform ──────────────────────────────────────────────────────
    local platform = require("insights.util.platform")
    H.eq(type(platform.is_windows()), "boolean", "the platform check answers a boolean")
    local sep = platform.is_windows() and "\\" or "/"
    H.eq(
      platform.joinpath({ "a", "b", "c" }),
      "a" .. sep .. "b" .. sep .. "c",
      "joinpath uses this platform's separator"
    )
    H.eq(platform.joinpath({ "only" }), "only", "a single part joins to itself")
    H.eq(platform.joinpath({}), "", "and no parts to nothing")

    local notify = require("insights.util.notify")
    H.eq(type(notify.create), "function", "the notify module re-exports the factory")
    local n = notify.create("[test]")
    for _, level in ipairs({ "info", "warn", "error", "debug" }) do
      H.eq(type(n[level]), "function", "a created notifier has " .. level)
    end

    -- ── fileinfo ───────────────────────────────────────────────────────────
    local fileinfo = require("insights.fileinfo")

    ---@return integer|nil
    local function float_win()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local wcfg = vim.api.nvim_win_get_config(win)
        if wcfg.relative and wcfg.relative ~= "" then
          return win
        end
      end
    end

    vim.cmd("silent! %bwipeout!")
    vim.cmd("enew")
    fileinfo.show()
    local nameless = float_win()
    H.ok(nameless, "a buffer with no file still opens the float")
    H.contains(
      table.concat(
        vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(nameless), 0, -1, false),
        "\n"
      ),
      "no associated file",
      "saying there is nothing to report"
    )
    -- Toggling: the same target closes it again.
    fileinfo.show()
    H.eq(float_win(), nil, "showing the same target again closes the float")

    local fdir, fcleanup = H.fixture("ui-fileinfo")
    local file = fdir .. "/stat-me.lua"
    vim.fn.writefile({ "return {}" }, file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    fileinfo.show()
    local info_win = float_win()
    H.ok(info_win, "a real file opens the float")
    local body = table.concat(
      vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(info_win), 0, -1, false),
      "\n"
    )
    H.contains(body, "Path:", "with the path")
    H.contains(body, "stat-me.lua", "naming the file")
    H.contains(body, "Type:        file", "its type")
    H.contains(body, "MiB", "its size in bytes and mebibytes")
    H.contains(body, "Permissions:", "its permissions")
    H.contains(body, "Modified:", "and its timestamps")
    if platform.is_windows() then
      H.contains(body, "Windows / limited POSIX meaning", "with the Windows caveat on permissions")
    else
      H.contains(body, "POSIX", "rendered as an rwx triple on POSIX")
    end

    -- Switching to another buffer and showing again replaces the float
    -- rather than toggling it closed.
    vim.cmd("enew")
    fileinfo.show()
    H.ok(float_win(), "a different target replaces the float instead of closing it")
    fileinfo.show()
    H.eq(float_win(), nil, "and the toggle still works afterwards")

    vim.cmd("silent! %bwipeout!")
    fcleanup()
  end)

  package.loaded["ui.kit"] = real_kit
  package.loaded["insights.ui.scratch"] = real_scratch
  config.setup({})

  if not ok_body then
    error(err_body, 0)
  end
end
