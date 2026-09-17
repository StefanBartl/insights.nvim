-- TESTS/symbols_index_spec.lua — the indexer and the scanner façade above it.
--
-- `rg_index.build` is one loop around `rg.run`, so the whole module is
-- testable without ripgrep by replacing `insights.scan.rg` in
-- `package.loaded` *before* `rg_index` is required for the first time. Doing
-- it after would be too late: `rg_index` binds the module to a local at load.
-- The replacement records every command it is handed, which is how the pass
-- de-duplication and the exclude/size/follow wiring are checked.
--
-- `insights.symbols` on top of it is pure dispatch, so its collaborators are
-- replaced the same way and what is pinned is which one each scope/type
-- combination reaches.

return function(H)
  local config = require("insights.config")

  -- Snapshot everything that gets replaced, so the suite leaves the module
  -- registry exactly as it found it.
  local saved = {}
  for _, name in ipairs({
    "insights.scan.rg",
    "insights.scan.cache",
    "insights.symbols.rg_index",
    "insights.symbols",
    "insights.symbols.ts_lua",
    "insights.symbols.ts_lua_tables",
    "insights.symbols.ts_lua_strings",
    "insights.ui.fzf",
    "insights.ui.telescope",
    "insights.ui.scratch",
  }) do
    saved[name] = package.loaded[name]
    package.loaded[name] = nil
  end

  -- The fake ripgrep: every pass gets the same two matches back, and the
  -- commands are recorded.
  local commands = {}
  local rg_answer = {
    lines = { "lua/mod.lua:3:1:local function alpha()", "lua/mod.lua:7:1:function M.beta()" },
    err = nil,
  }
  package.loaded["insights.scan.rg"] = {
    build_cmd = function(pattern, extensions, opts)
      return { "rg", pattern, exts = extensions, opts = opts }
    end,
    run = function(cmd, label)
      commands[#commands + 1] = { cmd = cmd, label = label }
      return rg_answer.lines, rg_answer.err
    end,
    exec_sync = function()
      return {}, 0
    end,
  }

  -- The fake cache: an in-memory store, so no files are written.
  local store = { value = nil, saves = 0, clears = 0 }
  package.loaded["insights.scan.cache"] = {
    load = function()
      if store.value then
        return store.value, nil
      end
      return nil, "no cache file"
    end,
    save = function(_, _, entries)
      store.saves = store.saves + 1
      store.value = entries
      return true, nil
    end,
    clear = function()
      store.clears = store.clears + 1
      store.value = nil
      return true, nil
    end,
    stats = function()
      return nil
    end,
  }

  local rg_index = require("insights.symbols.rg_index")
  local real_executable = vim.fn.executable

  -- `config.setup` deep-merges over the defaults, where every language is
  -- `true`. Naming only the wanted ones would therefore leave the other ten
  -- enabled and every pass count below would be the full 26.
  ---@param wanted table<string, boolean>
  ---@return table<string, boolean>
  local function only(wanted)
    local langs = {}
    for lang in pairs(require("insights.config.DEFAULTS").symbols.languages) do
      langs[lang] = wanted[lang] == true
    end
    return langs
  end

  local ok_body, err_body = pcall(function()
    -- ── build ──────────────────────────────────────────────────────────────
    config.setup({
      symbols = {
        languages = only({ lua = true }),
        indexing = {
          exclude_patterns = { "build/" },
          max_file_size_kb = 256,
          follow_symlinks = true,
        },
      },
    })
    local cfg = config.get()

    commands = {}
    local entries, errors, stats = rg_index.build(cfg)

    -- Lua declares five patterns; one rg pass runs per distinct pattern.
    H.eq(#commands, 5, "one pass per distinct pattern of the enabled language")
    H.eq(commands[1].label, "lua", "each pass is labelled with its language")
    H.eq(commands[1].cmd.opts.max_file_size_kb, 256, "the size cap reaches the command builder")
    H.eq(commands[1].cmd.opts.follow_symlinks, true, "and so does symlink following")
    H.eq(commands[1].cmd.opts.exclude_patterns[1], "build/", "and the exclusions")
    H.ok(commands[1].cmd.opts.cwd, "with an explicit search root, snapshotted once")

    -- Every pass returns the same two lines, so the parser sees 10 and
    -- reports the two distinct symbols it can name once per occurrence.
    H.eq(#entries, 10, "every match from every pass is parsed")
    H.eq(#errors, 0, "with no errors")
    H.eq(stats.total_symbols, 10, "the stats agree")
    H.eq(stats.total_files, 1, "counting distinct files, not matches")
    H.ok(type(stats.duration) == "number", "and the elapsed seconds")

    -- Two languages: each contributes its own passes.
    config.setup({ symbols = { languages = only({ lua = true, go = true }) } })
    commands = {}
    rg_index.build(config.get())
    H.eq(#commands, 7, "a second language adds its own passes")
    local labels = {}
    for _, c in ipairs(commands) do
      labels[c.label] = true
    end
    H.ok(labels.lua and labels.go, "both languages are searched")

    -- No language enabled: nothing to search for, said out loud.
    config.setup({ symbols = { languages = only({}) } })
    commands = {}
    local none, none_errors = rg_index.build(config.get())
    H.eq(#commands, 0, "no enabled language runs no pass")
    H.eq(#none, 0, "and finds nothing")
    H.eq(none_errors[1], "no languages enabled", "saying why")

    -- An rg error is collected rather than raised, and the pass still ends.
    config.setup({ symbols = { languages = only({ lua = true }) } })
    rg_answer = { lines = {}, err = "lua: rg exited 2" }
    local failed, failed_errors = rg_index.build(config.get())
    H.eq(#failed, 0, "a failing rg yields no entries")
    H.eq(#failed_errors, 5, "one error per failing pass")
    rg_answer = {
      lines = { "lua/mod.lua:3:1:local function alpha()" },
      err = nil,
    }

    -- Without ripgrep on PATH the build stops before any pass.
    vim.fn.executable = function()
      return 0
    end
    commands = {}
    local no_rg, no_rg_errors, no_rg_stats = rg_index.build(config.get())
    H.eq(#commands, 0, "no ripgrep, no passes")
    H.eq(#no_rg, 0, "and no entries")
    H.eq(no_rg_errors[1], "ripgrep (rg) not found in PATH", "with the reason")
    H.eq(no_rg_stats.total_symbols, 0, "and empty stats")
    vim.fn.executable = real_executable

    -- ── get: cache in front of build ──────────────────────────────────────
    config.setup({
      symbols = { languages = only({ lua = true }), cache = { enabled = true, ttl_seconds = 3600 } },
    })
    store.value, store.saves = nil, 0

    commands = {}
    local built, built_msg = rg_index.get(config.get())
    H.ok(#built > 0, "a cold cache builds")
    H.ok(#commands > 0, "by running the passes")
    H.contains(built_msg or "", "indexed", "and says it indexed")
    H.eq(store.saves, 1, "storing the result")

    commands = {}
    local cached, cached_msg = rg_index.get(config.get())
    H.eq(#commands, 0, "a warm cache answers without running anything")
    H.eq(#cached, #built, "with the same entries")
    H.contains(cached_msg or "", "cache:", "and says the answer came from the cache")

    commands = {}
    rg_index.get(config.get(), true)
    H.ok(#commands > 0, "force_rebuild goes past the cache")

    -- With the cache disabled nothing is stored and every call builds.
    config.setup({ symbols = { languages = only({ lua = true }), cache = { enabled = false } } })
    store.value, store.saves = nil, 0
    commands = {}
    rg_index.get(config.get())
    H.ok(#commands > 0, "a disabled cache always builds")
    H.eq(store.saves, 0, "and never writes")

    -- An empty result is not cached: a cached "nothing" would look like a
    -- project with no symbols until the TTL ran out.
    config.setup({ symbols = { languages = only({ lua = true }), cache = { enabled = true } } })
    store.value, store.saves = nil, 0
    rg_answer = { lines = {}, err = nil }
    rg_index.get(config.get())
    H.eq(store.saves, 0, "an empty index is not written to the cache")
    rg_answer = { lines = { "lua/mod.lua:3:1:local function alpha()" }, err = nil }

    -- ── rebuild ────────────────────────────────────────────────────────────
    store.clears = 0
    rg_index.rebuild(config.get())
    H.eq(store.clears, 1, "rebuild clears the cache first")
    H.ok(store.value, "and repopulates it")

    config.setup({ symbols = { languages = only({ lua = true }), cache = { enabled = false } } })
    store.clears = 0
    rg_index.rebuild(config.get())
    H.eq(store.clears, 0, "with the cache disabled there is nothing to clear")

    -- ── insights.symbols: dispatch ─────────────────────────────────────────
    local calls = {}
    package.loaded["insights.symbols.rg_index"] = {
      get = function(c, force)
        calls[#calls + 1] = { "rg_index.get", force, c.symbols.languages.lua }
        return { { name = "from-rg" } }, "rg msg"
      end,
      rebuild = function()
        calls[#calls + 1] = { "rg_index.rebuild" }
        return { { name = "rebuilt" } }, "rebuild msg"
      end,
    }
    package.loaded["insights.symbols.ts_lua"] = {
      scan_buffer = function()
        calls[#calls + 1] = { "ts_lua.scan_buffer" }
        return { { name = "buf-fn", lnum = 1, col = 0 } }
      end,
      scan_cwd = function()
        calls[#calls + 1] = { "ts_lua.scan_cwd" }
        return { { name = "cwd-fn", lnum = 1, col = 2 } }
      end,
    }
    package.loaded["insights.symbols.ts_lua_tables"] = {
      scan_buffer = function()
        calls[#calls + 1] = { "tables.scan_buffer" }
        return { { name = "buf-table" } }
      end,
      scan_cwd = function()
        calls[#calls + 1] = { "tables.scan_cwd" }
        return { { name = "cwd-table" } }
      end,
    }
    package.loaded["insights.symbols.ts_lua_strings"] = {
      scan_buffer = function()
        calls[#calls + 1] = { "strings.scan_buffer" }
        return { { name = "buf-string" } }
      end,
      scan_cwd = function()
        calls[#calls + 1] = { "strings.scan_cwd" }
        return { { name = "cwd-string" } }
      end,
    }
    package.loaded["insights.symbols"] = nil
    local symbols = require("insights.symbols")

    config.setup({ symbols = { use_treesitter_for_lua = false, default_scope = "cwd" } })

    calls = {}
    local got, got_msg = symbols.get()
    H.eq(calls[1][1], "rg_index.get", "the default scope goes to the rg indexer")
    H.eq(got[1].name, "from-rg", "returning its entries")
    H.eq(got_msg, "rg msg", "and its status line")

    calls = {}
    symbols.get("cwd", true)
    H.eq(calls[1][2], true, "force_rebuild is passed through")

    -- `default_scope = "buffer"` means a bare `get()` scans the buffer.
    config.setup({ symbols = { default_scope = "buffer" } })
    calls = {}
    local _, buffer_msg = symbols.get()
    H.contains(buffer_msg or "", "buffer", "the configured default scope is honoured")
    config.setup({ symbols = { default_scope = "cwd" } })

    -- The Tree-sitter cwd path merges TS Lua with rg for everything else,
    -- and asks rg for everything *but* Lua.
    config.setup({ symbols = { use_treesitter_for_lua = true } })
    calls = {}
    local merged, merged_msg = symbols.get("cwd")
    H.eq(calls[1][1], "rg_index.get", "the rg indexer still runs for the other languages")
    H.eq(calls[1][3], false, "with Lua switched off in the config it is handed")
    H.eq(calls[2][1], "ts_lua.scan_cwd", "and Tree-sitter handles Lua")
    H.eq(#merged, 2, "the two results are merged")
    H.eq(merged[1].name, "cwd-fn", "Tree-sitter entries come first")
    H.eq(merged[1].language, "lua", "stamped as Lua")
    H.eq(merged[1].signature, "cwd-fn()", "with a synthesised signature")
    H.eq(merged[2].name, "from-rg", "then the rg ones")
    H.contains(merged_msg or "", "TS Lua: 1", "and the message breaks the sources down")

    -- Splitting the language config must not mutate the caller's config.
    H.eq(
      config.get().symbols.languages.lua,
      true,
      "the live config still has Lua enabled afterwards"
    )

    -- get_buffer on a nameless buffer answers rather than scanning.
    vim.cmd("enew")
    local nameless, nameless_msg = symbols.get_buffer()
    H.eq(#nameless, 0, "a buffer with no file has no symbols")
    H.eq(nameless_msg, "current buffer has no file", "and says so")

    -- With a Lua buffer and the TS option on, the buffer scanner is used and
    -- the file name is stamped onto every match.
    local tmp = vim.fn.getcwd() .. "/TESTS/.fixture-symbols-index.lua"
    vim.fn.writefile({ "local function f() end" }, tmp)
    vim.cmd("edit " .. vim.fn.fnameescape(tmp))
    vim.bo.filetype = "lua"
    calls = {}
    local buf_entries, buf_msg = symbols.get_buffer()
    H.eq(calls[1][1], "ts_lua.scan_buffer", "a Lua buffer is scanned with Tree-sitter")
    H.eq(#buf_entries, 1, "returning its matches")
    H.contains(buf_entries[1].filename, "fixture-symbols-index.lua", "stamped with the file name")
    H.contains(buf_msg or "", "(TS)", "and the message names the backend")

    -- A non-Lua buffer falls back to running rg over the single file.
    vim.bo.filetype = "python"
    config.setup({
      symbols = { use_treesitter_for_lua = true, languages = only({ python = true }) },
    })
    commands = {}
    local py_entries, py_msg = symbols.get_buffer()
    H.ok(#commands > 0, "a non-Lua buffer is scanned with ripgrep")
    H.contains(
      vim.fs.normalize(commands[1].cmd.opts.cwd),
      "fixture-symbols-index.lua",
      "scoped to that one file"
    )
    H.eq(type(py_entries), "table", "answering a list")
    H.contains(py_msg or "", "(buffer)", "and a buffer-scoped message")

    -- get_tables / get_strings -------------------------------------------
    calls = {}
    local tables_buf, tables_msg = symbols.get_tables()
    H.eq(calls[1][1], "tables.scan_buffer", "get_tables defaults to the buffer scope")
    H.contains(tables_buf[1].filename or "", "fixture-symbols-index.lua", "stamping the file name")
    H.contains(tables_msg or "", "tables (buffer)", "with a buffer message")

    calls = {}
    local tables_cwd, tables_cwd_msg = symbols.get_tables("cwd")
    H.eq(calls[1][1], "tables.scan_cwd", "and scans the cwd when asked")
    H.eq(tables_cwd[1].name, "cwd-table", "returning its entries")
    H.contains(tables_cwd_msg or "", "tables (cwd)", "with a cwd message")

    calls = {}
    local strings_buf, strings_msg = symbols.get_strings()
    H.eq(calls[1][1], "strings.scan_buffer", "get_strings defaults to the buffer scope too")
    H.contains(
      strings_buf[1].filename or "",
      "fixture-symbols-index.lua",
      "stamping the file name onto each literal"
    )
    H.contains(strings_msg or "", "strings (buffer)", "with its own message")

    calls = {}
    symbols.get_strings("cwd")
    H.eq(calls[1][1], "strings.scan_cwd", "and scans the cwd when asked")

    calls = {}
    local rebuilt, rebuilt_msg = symbols.rebuild()
    H.eq(calls[1][1], "rg_index.rebuild", "rebuild goes straight to the indexer")
    H.eq(rebuilt[1].name, "rebuilt", "with its entries")
    H.eq(rebuilt_msg, "rebuild msg", "and its message")

    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(tmp)
  end)

  vim.fn.executable = real_executable
  for name, mod in pairs(saved) do
    package.loaded[name] = mod
  end
  config.setup({})

  if not ok_body then
    error(err_body, 0)
  end
end
