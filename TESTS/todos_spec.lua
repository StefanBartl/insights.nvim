-- TESTS/todos_spec.lua — annotation comments: the keyword table, the scan
-- and the in-buffer highlight.
--
-- **No rg process is started.** The scan goes through `insights.scan.rg`,
-- whose `vim.system` is replaced for the duration by a fake that answers a
-- fixed `--vimgrep` listing -- including a Windows drive path, the shape
-- that once made the symbol parser discard every hit. `lib.nvim.ui.list` is
-- replaced too, so the quickfix branch is captured rather than opened.
--
-- The highlight tests run against a real scratch buffer. The comment gate
-- needs a Tree-sitter parser to say "this is not a comment"; the Lua parser
-- ships with Neovim, but the negative assertion is skipped rather than
-- failed where it is not available, so the suite stays honest on a bare
-- runtime.

return function(H)
  local config = require("insights.config")

  local replaced_modules = { "lib.nvim.ui.list", "insights.todos", "insights.todos.highlight" }
  local saved = {}
  for _, name in ipairs(replaced_modules) do
    saved[name] = package.loaded[name]
  end

  local qf_calls = {}
  package.loaded["lib.nvim.ui.list"] = {
    qf = function(items, title, opts)
      qf_calls[#qf_calls + 1] = { items = items, title = title, opts = opts }
    end,
  }

  package.loaded["insights.todos"] = nil
  package.loaded["insights.todos.highlight"] = nil
  local todos = require("insights.todos")
  local highlight = require("insights.todos.highlight")

  -- A known config: the shipped table, quickfix UI, no debounce.
  config.setup({ todos = { search = { ui = "qf" }, highlight = { debounce_ms = 0 } } })
  todos.reset()

  -- keyword table ---------------------------------------------------------

  do
    local kws = todos.keywords()
    H.ok(kws.FIX, "shipped table has FIX")
    H.eq(kws.FIX.color, "error", "FIX is an error")
    H.eq(kws.PERF.color, "default", "a keyword with no colour gets 'default'")
    H.eq(todos.lookup("BUG").keyword, "FIX", "alias resolves to its keyword")
    H.eq(todos.lookup("TODO").keyword, "TODO", "keyword resolves to itself")
    H.eq(todos.lookup("todo"), nil, "lookup is case-sensitive")
    H.eq(todos.lookup("NOPE"), nil, "unknown word is nil")
  end

  do
    local words = todos.words()
    local seen = {}
    for _, w in ipairs(words) do
      H.falsy(seen[w], "word listed once: " .. w)
      seen[w] = true
    end
    H.ok(seen.FIXME and seen.TODO and seen.REFACTOR, "words cover keywords and aliases")
    -- Longest first, so the alternation cannot match FIX inside FIXME.
    local pos = {}
    for i, w in ipairs(words) do
      pos[w] = i
    end
    H.ok(pos.FIXME < pos.FIX, "longer word precedes its prefix")
  end

  do
    H.contains(todos.vim_pattern({ "TODO", "FIX" }), "\\v\\C<(TODO|FIX)>", "vim pattern shape")
    H.eq(todos.rg_pattern({ "TODO", "FIX" }), "\\b(TODO|FIX)\\b", "rg pattern shape")
  end

  -- compiled_pattern: cached, not recompiled per call (fix: classify() used
  -- to call vim.regex() fresh on every match, one compilation per
  -- annotation comment in the whole tree instead of once per scan).
  do
    local re1 = todos.compiled_pattern()
    local re2 = todos.compiled_pattern()
    H.eq(re1, re2, "the same word list reuses the same compiled regex")
    local re3 = todos.compiled_pattern({ "TODO", "FIX" })
    H.ok(re3 ~= re1, "a different word list compiles its own regex")
    todos.reset()
    local re4 = todos.compiled_pattern()
    H.ok(re4 ~= re1, "reset() drops the cached regex too")
  end

  -- a host overriding the table: add one, drop one -------------------------

  do
    config.setup({
      todos = {
        search = { ui = "qf" },
        highlight = { debounce_ms = 0 },
        keywords = { HACK = false, FOO = { color = "info", alt = { "BAR" } } },
      },
    })
    todos.reset()
    local kws = todos.keywords()
    H.eq(kws.HACK, nil, "`false` drops a shipped keyword")
    H.eq(kws.FOO.color, "info", "a host keyword is added")
    H.eq(todos.lookup("BAR").keyword, "FOO", "its alias resolves")
    H.eq(todos.lookup("HACK"), nil, "the dropped keyword is not a word any more")
    H.eq(#config.issues(), 0, "todos.keywords is an open key path: no unknown-key warning")
    config.setup({ todos = { search = { ui = "qf" }, highlight = { debounce_ms = 0 } } })
    todos.reset()
  end

  -- filter resolution -----------------------------------------------------

  do
    local words = todos.words_for({ "fix" })
    H.ok(words, "a lowercase keyword resolves")
    local set = {}
    for _, w in ipairs(words) do
      set[w] = true
    end
    H.ok(set.FIX and set.FIXME and set.BUG, "filter expands to keyword plus aliases")
    H.falsy(set.TODO, "filter excludes other keywords")

    local via_alias = todos.words_for({ "BUG" })
    H.ok(via_alias, "an alias resolves to its keyword")
    local via_set = {}
    for _, w in ipairs(via_alias) do
      via_set[w] = true
    end
    H.ok(via_set.FIX, "...and yields the keyword's full word set")

    H.eq(todos.words_for({}), nil, "empty filter is no filter")
    H.eq(todos.words_for(nil), nil, "nil filter is no filter")
  end

  -- vimgrep parsing and classification -------------------------------------

  do
    local hit = todos.parse_vimgrep("lua/a.lua:12:5:  -- TODO: something")
    H.eq(hit.filename, "lua/a.lua", "posix path")
    H.eq(hit.lnum, 12, "line")
    H.eq(hit.col, 5, "column")
    H.eq(hit.text, "  -- TODO: something", "text keeps leading whitespace")

    local win = todos.parse_vimgrep("E:\\repos\\x.nvim\\lua\\b.lua:3:1:-- FIXME broken")
    H.ok(win, "windows drive path parses")
    H.eq(win.filename, "E:\\repos\\x.nvim\\lua\\b.lua", "drive letter kept in the path")
    H.eq(win.lnum, 3, "windows line")

    H.eq(todos.parse_vimgrep("not a vimgrep line"), nil, "garbage is nil")

    local word, info, col = todos.classify("-- FIXME: broken")
    H.eq(word, "FIXME", "classify finds the word")
    H.eq(info.keyword, "FIX", "...and its keyword")
    H.eq(col, 4, "...and where it starts")
    H.eq(todos.classify("no annotation here"), nil, "no word, no result")
    H.eq(todos.classify("-- FIXME", { "TODO" }), nil, "a filter restricts classify")
  end

  -- token parsing for :Insights todos ------------------------------------

  do
    local p = todos.parse_tokens({ "fix", "qf", "Todo" })
    H.eq(p.ui, "qf", "UI token found in any position")
    H.eq(#p.keywords, 2, "the rest are keywords")
    H.eq(p.keywords[1], "FIX", "keywords are upper-cased")
    H.eq(p.keywords[2], "TODO", "...all of them")
    local none = todos.parse_tokens({})
    H.eq(none.ui, nil, "no tokens: no ui")
    H.eq(#none.keywords, 0, "no tokens: no filter")
  end

  -- the scan, against a fake rg ------------------------------------------

  local real_system = vim.system
  local seen_cmd
  local rg_lines = {
    "lua/z.lua:2:4:-- TODO: last file first, to test the sort",
    "lua/a.lua:9:1:-- BUG: alias hit",
    "lua/a.lua:4:1:-- FIX: keyword hit",
    "E:\\repos\\p\\lua\\w.lua:7:3:  -- REFACTOR later",
    "lua/a.lua:5:1:local TODO_COUNT = 1 -- no word boundary match on TODO_COUNT",
    "lua/a.lua:6:1:-- NOPE: not a keyword, rg would not have returned it but be safe",
  }
  vim.system = function(cmd, _, cb)
    seen_cmd = cmd
    local res = { code = 0, stdout = table.concat(rg_lines, "\n") .. "\n", stderr = "" }
    if cb then
      vim.schedule(function()
        cb(res)
      end)
    end
    return {
      wait = function()
        return res
      end,
    }
  end

  local ok_scan, scan_err = pcall(function()
    local entries, err = todos.scan({})
    H.eq(err, nil, "scan reports no error")
    H.eq(#entries, 4, "four hits carry a known word (TODO_COUNT and NOPE do not)")
    H.eq(entries[1].filename, "E:\\repos\\p\\lua\\w.lua", "sorted by file: drive path first")
    H.eq(entries[1].keyword, "REF", "REFACTOR resolves to REF")
    H.eq(entries[2].filename, "lua/a.lua", "then a.lua")
    H.eq(entries[2].lnum, 4, "...its lines in order")
    H.eq(entries[3].lnum, 9, "...")
    H.eq(entries[3].word, "BUG", "the matched word is kept")
    H.eq(entries[3].keyword, "FIX", "...next to its keyword")
    H.eq(entries[3].color, "error", "...and its category")
    H.eq(entries[4].filename, "lua/z.lua", "z.lua last")
    H.eq(entries[4].text, "-- TODO: last file first, to test the sort", "text is trimmed")
    H.eq(entries[4].name, entries[4].text, "name aliases text for the picker adapters")

    H.ok(vim.tbl_contains(seen_cmd, "--case-sensitive"), "rg runs case-sensitive")
    H.ok(vim.tbl_contains(seen_cmd, "--vimgrep"), "...in vimgrep mode")
    local pattern = seen_cmd[#seen_cmd - 1]
    H.contains(pattern, "\\b(", "the pattern is the word alternation")
    H.contains(pattern, "FIXME", "...with aliases in it")

    -- A keyword filter narrows both the rg pattern and the classification.
    local only_fix = todos.scan({ keywords = { "FIX" } })
    H.eq(#only_fix, 2, "FIX filter: the FIX and BUG lines")
    local filtered_pattern = seen_cmd[#seen_cmd - 1]
    H.falsy(filtered_pattern:find("TODO", 1, true), "filtered pattern omits other keywords")

    local none, none_err = todos.scan({ keywords = { "NOSUCH" } })
    H.eq(#none, 0, "unknown filter yields nothing")
    H.ok(none_err, "...and says so")

    -- open() to the quickfix list goes through lib.nvim.ui.list.qf.
    local count = todos.open({ ui = "qf" })
    H.eq(count, 4, "open returns the count")
    H.eq(#qf_calls, 1, "quickfix populated once")
    H.eq(#qf_calls[1].items, 4, "...with every entry")
    H.contains(qf_calls[1].items[2].text, "[FIX]", "quickfix text carries the keyword")
    H.contains(qf_calls[1].title, "4 found", "title carries the count")
  end)
  vim.system = real_system
  if not ok_scan then
    error(scan_err, 0)
  end

  -- the highlight, against a real buffer ---------------------------------

  do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = ""
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "-- TODO: first",
      "local x = 1 -- FIXME trailing",
      "local TODO = 2",
      "-- nothing here",
      "-- BUG and HACK on one line",
    })
    vim.bo[buf].filetype = "lua"

    local has_parser = pcall(vim.treesitter.get_parser, buf, "lua")
    if has_parser then
      -- Make sure the tree exists before the capture query runs.
      pcall(function()
        vim.treesitter.get_parser(buf, "lua"):parse()
      end)
    end

    highlight.setup_groups()
    local fg, bg, sign = highlight.group_names("error")
    H.eq(fg, "InsightsTodoFgError", "group naming")
    H.eq(bg, "InsightsTodoBgError", "...bg")
    H.eq(sign, "InsightsTodoSignError", "...sign")
    local defined = vim.api.nvim_get_hl(0, { name = "InsightsTodoBgError" })
    H.ok(defined and next(defined) ~= nil, "groups are defined after setup_groups")

    local count = highlight.apply(buf, 0, 5)
    local marks = vim.api.nvim_buf_get_extmarks(buf, highlight.NS, 0, -1, { details = true })
    if has_parser then
      H.eq(count, 4, "TODO, FIXME, BUG, HACK inside comments; `local TODO` is code")
    else
      H.ok(count >= 4, "without a parser the code line is not excluded")
    end
    H.ok(#marks >= count, "one extmark per keyword at least")

    local rows = {}
    for _, m in ipairs(marks) do
      rows[m[2]] = true
    end
    H.ok(rows[0], "line 1 marked")
    H.ok(rows[1], "line 2 marked")
    H.falsy(rows[3], "a plain comment is not marked")
    if has_parser then
      H.falsy(rows[2], "`local TODO = 2` is not a comment, not marked")
    end

    local sign_found = false
    for _, m in ipairs(marks) do
      if m[4].sign_text then
        sign_found = true
      end
    end
    H.ok(sign_found, "a sign was placed")

    highlight.clear(buf)
    H.eq(
      #vim.api.nvim_buf_get_extmarks(buf, highlight.NS, 0, -1, {}),
      0,
      "clear removes every mark"
    )

    -- eligibility
    H.ok(highlight.eligible(buf), "a normal buffer is eligible")
    vim.bo[buf].buftype = "nofile"
    H.falsy(highlight.eligible(buf), "a nofile buffer is not")
    vim.bo[buf].buftype = ""
    vim.bo[buf].filetype = "help"
    H.falsy(highlight.eligible(buf), "an excluded filetype is not")

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- restore ---------------------------------------------------------------

  config.setup({})
  for _, name in ipairs(replaced_modules) do
    package.loaded[name] = saved[name]
  end
end
