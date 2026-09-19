-- TESTS/compress_tree_spec.lua — the two features that build a shell command
-- and hand it to the platform layer.
--
-- **No shell is started.** Both modules reach the outside world through
-- exactly one seam, `insights.util.platform`, and that module is replaced in
-- `package.loaded` before either is required. The commands they build are
-- recorded instead of run, which is the only way to check the Windows half on
-- a Unix machine and the Unix half on Windows -- the branch not taken locally
-- is the one that breaks silently.

return function(H)
  local config = require("insights.config")

  -- Restored by name at the end, not `pairs(saved)`: storing `nil` in a Lua
  -- table does not create a key, so a module that had not been required by
  -- anything yet (`saved[name] == nil`, the common case for a fresh test
  -- run) would silently never get its `package.loaded` slot cleared back to
  -- nil -- the fake stubbed in below for this one spec would leak into
  -- every later spec's `require` for the rest of the process.
  local stubbed_modules = { "insights.util.platform", "insights.compress", "insights.tree" }
  local saved = {}
  for _, name in ipairs(stubbed_modules) do
    saved[name] = package.loaded[name]
    package.loaded[name] = nil
  end

  -- The stand-in platform layer.
  local shell = { calls = {}, answer = { ok = true, stdout = "", stderr = "" } }
  local windows = false
  local clipboard = { ok = true, text = nil }

  package.loaded["insights.util.platform"] = {
    is_windows = function()
      return windows
    end,
    joinpath = function(parts)
      return table.concat(parts, windows and "\\" or "/")
    end,
    run_shell = function(cmd, cb)
      shell.calls[#shell.calls + 1] = cmd
      local a = shell.answer
      cb(a.ok, a.stdout, a.stderr)
    end,
    copy_to_clipboard = function(text)
      clipboard.text = text
      return clipboard.ok
    end,
  }

  local compress = require("insights.compress")
  local tree = require("insights.tree")

  local dir, cleanup = H.fixture("compress-tree")

  local ok_body, err_body = pcall(function()
    -- ══ compress ═══════════════════════════════════════════════════════════
    ---@param cfg table
    ---@return boolean, string
    local function run_compress(cfg)
      shell.calls = {}
      local ok, msg
      compress.compress(dir, cfg, function(o, m)
        ok, msg = o, m
      end)
      return ok, msg or ""
    end

    -- Unknown engine: refused before anything is created.
    local ok_unknown, msg_unknown = run_compress({ engine = "rar" })
    H.falsy(ok_unknown, "an unknown engine is refused")
    H.contains(msg_unknown, "unknown compress engine", "saying so")
    H.contains(msg_unknown, "auto | tar | zip | powershell", "and listing the valid ones")
    H.eq(#shell.calls, 0, "without running anything")

    -- A wrong-type engine (e.g. `true`, which `cfg.engine or "auto"` alone
    -- would let through since it is truthy) must degrade to "auto" instead of
    -- crashing the "unknown engine" message's string concatenation (ERR-22).
    windows = false
    ---@diagnostic disable-next-line: assign-type-mismatch
    local ok_bad_type, msg_bad_type = run_compress({ engine = true, outdir = "" })
    H.ok(ok_bad_type, "a wrong-type engine falls back to auto instead of erroring")
    H.contains(shell.calls[2], "tar", "and auto resolves to tar on Unix, same as a real auto")
    H.excludes(msg_bad_type, "boolean", "no crash artifact leaking into the message")

    -- `auto` resolves per platform.
    windows = false
    local ok_tar = run_compress({ engine = "auto", outdir = "" })
    H.ok(ok_tar, "auto succeeds on Unix")
    H.contains(shell.calls[2], "tar", "picking tar")

    windows = true
    run_compress({ engine = "auto", outdir = "" })
    H.contains(shell.calls[2], "Compress-Archive", "and PowerShell on Windows")
    windows = false

    -- outdir resolution: "" places `compressed/` inside the directory itself.
    H.eq(vim.fn.isdirectory(dir .. "/compressed"), 1, "an empty outdir creates compressed/ inside")

    local elsewhere = dir .. "/archives"
    run_compress({ engine = "tar", outdir = elsewhere })
    H.eq(
      vim.fn.isdirectory(elsewhere .. "/" .. vim.fn.fnamemodify(dir, ":t") .. "-compressed"),
      1,
      "a configured outdir gets a <name>-compressed subdirectory"
    )

    -- tar: two commands, the listing and then the archive.
    local ok_t, msg_t = run_compress({ engine = "tar", outdir = "" })
    H.ok(ok_t, "tar reports success")
    H.eq(#shell.calls, 2, "running a listing and an archive command")
    H.contains(shell.calls[1], "find", "the listing is find")
    H.contains(shell.calls[1], "-not -path", "excluding .git")
    H.contains(shell.calls[2], "--exclude=", "and so does tar")
    H.contains(shell.calls[2], "-czf", "writing a gzipped tarball")
    H.contains(msg_t, ".tar.gz", "and the message names the archive")

    -- zip: same shape, different tool.
    local ok_z, msg_z = run_compress({ engine = "zip", outdir = "" })
    H.ok(ok_z, "zip reports success")
    H.contains(shell.calls[2], "zip -r", "recursing")
    H.contains(shell.calls[2], "--exclude '*.git/*'", "with the git exclusion")
    H.contains(msg_z, ".zip", "and the message names the archive")

    -- powershell: the listing is captured and written from Lua, because
    -- PowerShell's own `>` writes UTF-16LE.
    windows = true
    shell.answer = { ok = true, stdout = "C:\\p\\a.txt\r\nC:\\p\\b.txt\r\n", stderr = "" }
    local ok_p, msg_p = run_compress({ engine = "powershell", outdir = "" })
    H.ok(ok_p, "the PowerShell engine reports success")
    H.contains(shell.calls[1], "Get-ChildItem", "listing with Get-ChildItem")
    H.contains(shell.calls[1], "-notlike", "and filtering .git out")
    H.excludes(shell.calls[1], "Out-File", "never redirecting to a file in the shell")
    H.contains(shell.calls[2], "Compress-Archive", "then archiving")
    H.contains(msg_p, ".zip", "and the message names the archive")
    H.eq(
      -- Real Lua-side I/O, so "/" throughout even for the PowerShell
      -- engine -- only the shell command strings it builds are
      -- backslash-spelled, see lua/insights/compress/init.lua.
      H.read(dir .. "/compressed/file-list.txt"):gsub("\r", ""),
      "C:\\p\\a.txt\nC:\\p\\b.txt",
      "with the listing written from Lua, one path per line"
    )
    windows = false
    shell.answer = { ok = true, stdout = "", stderr = "" }

    -- Failures: each engine reports the step that failed rather than raising.
    shell.answer = { ok = false, stdout = "", stderr = "find exploded" }
    local ok_f1, msg_f1 = run_compress({ engine = "tar", outdir = "" })
    H.falsy(ok_f1, "a failing listing fails the whole run")
    H.contains(msg_f1, "file listing failed", "naming the step")
    H.contains(msg_f1, "find exploded", "and quoting the error")
    H.eq(#shell.calls, 1, "without attempting the archive")

    local _, msg_f2 = run_compress({ engine = "zip", outdir = "" })
    H.contains(msg_f2, "file listing failed", "the zip engine fails the same way")

    windows = true
    local _, msg_f3 = run_compress({ engine = "powershell", outdir = "" })
    H.contains(msg_f3, "file listing failed", "and so does the PowerShell one")
    windows = false

    -- A listing that works and an archive step that does not.
    local step = 0
    package.loaded["insights.util.platform"].run_shell = function(cmd, cb)
      step = step + 1
      shell.calls[#shell.calls + 1] = cmd
      -- Written out rather than as `step > 1 and false or true`: that idiom
      -- collapses to `true` whenever the "true" branch is `false`.
      if step > 1 then
        cb(false, "", "archiver exploded")
      else
        cb(true, "listed\n", "")
      end
    end
    step, shell.calls = 0, {}
    local ok_a, msg_a
    compress.compress(dir, { engine = "tar", outdir = "" }, function(o, m)
      ok_a, msg_a = o, m
    end)
    H.falsy(ok_a, "a failing archive step fails the run")
    H.contains(msg_a or "", "tar failed", "naming the archiver")

    step, shell.calls = 0, {}
    compress.compress(dir, { engine = "zip", outdir = "" }, function(_, m)
      msg_a = m
    end)
    H.contains(msg_a or "", "zip failed", "and the zip one names itself")

    windows = true
    step, shell.calls = 0, {}
    compress.compress(dir, { engine = "powershell", outdir = "" }, function(_, m)
      msg_a = m
    end)
    H.contains(msg_a or "", "Compress-Archive failed", "and so does Compress-Archive")
    windows = false

    package.loaded["insights.util.platform"].run_shell = function(cmd, cb)
      shell.calls[#shell.calls + 1] = cmd
      local a = shell.answer
      cb(a.ok, a.stdout, a.stderr)
    end
    shell.answer = { ok = true, stdout = "", stderr = "" }

    -- ══ tree ═══════════════════════════════════════════════════════════════
    local outdir = dir .. "/treeout"
    config.setup({
      tree = {
        outdir = outdir,
        outfile_fmt = "%s-tree.txt",
        exclude_patterns = { "*/.git/*", "*/node_modules/*" },
      },
    })

    ---@return boolean, string, any
    local function run_tree()
      shell.calls = {}
      local ok, msg, extra
      tree.write_tree(function(o, m, p)
        ok, msg, extra = o, m, p
      end)
      return ok, msg or "", extra
    end

    -- Unix: find + sed + sort, with one -not -path per exclusion.
    windows = false
    shell.answer = { ok = true, stdout = "lua/a.lua\nlua/b.lua\n", stderr = "" }
    local ok_w, msg_w, path_w = run_tree()
    H.ok(ok_w, "write_tree succeeds")
    H.contains(shell.calls[1], "find ", "the Unix command uses find")
    H.contains(shell.calls[1], "-type f", "listing files")
    local _, not_paths = shell.calls[1]:gsub("%-not %-path", "")
    H.eq(not_paths, 2, "with one exclusion per configured pattern")
    H.contains(shell.calls[1], "| sed -e", "stripping the root prefix with sed")
    H.contains(shell.calls[1], "| sort", "and sorting")
    H.contains(path_w, "-tree.txt", "the output path follows outfile_fmt")
    H.contains(msg_w, "tree written:", "and the message says so")
    H.eq(H.read(path_w), "lua/a.lua\nlua/b.lua", "with the listing written from Lua")
    H.eq(vim.fn.isdirectory(outdir), 1, "creating the output directory on the way")

    -- Regression: the Unix root-prefix strip used to escape the CWD for
    -- `sed`'s BRE with Lua's own escape character, `%`, which sed treats as
    -- an ordinary literal -- so `%` was prefixed onto the real path and the
    -- pattern could never match it. `#` also needs escaping here specifically
    -- because it is this command's own `s#...#...#` delimiter. Checked
    -- against the whole command (not just an extracted pattern) since
    -- `shellescape`'s quoting style is host-dependent.
    local cmd = tree._internal.build_tree_cmd("/home/u/a.b#c project", {})
    H.contains(cmd, "a\\.b\\#c project", "'.' and the '#' delimiter are BRE-escaped")
    H.excludes(cmd, "%", "not prefixed with Lua's own escape character")

    -- `+`, `(`, `)` etc. are already literal in POSIX BRE; escaping them
    -- would hand GNU sed's backslash-escaped extensions (`\+`, `\(`, ...) a
    -- meaning they must not have here.
    local cmd2 = tree._internal.build_tree_cmd("/home/u/a+b(c)", {})
    H.contains(cmd2, "a+b(c)", "'+()' stay literal, unescaped")

    -- Windows: a PowerShell pipeline, with the globs turned into regexes.
    windows = true
    run_tree()
    local ps = shell.calls[1]
    H.contains(ps, "Get-ChildItem", "the Windows command uses Get-ChildItem")
    H.contains(ps, "-Recurse -File", "listing files recursively")
    H.contains(ps, "$rx=@(", "with a regex array built from the glob patterns")
    H.contains(ps, "[\\\\/]node_modules[\\\\/]", "each glob made path-separator-agnostic")
    H.contains(ps, "Sort-Object", "and sorted")

    -- Regression: the glob-to-regex translation used to escape regex
    -- metacharacters with Lua's escape character, `%`, rather than the `\`
    -- that .NET's regex engine (which `-match` uses) understands. The default
    -- exclusion `*/.git/*` became `.*[\/]%.git[\/].*`, a pattern requiring a
    -- literal `%` before the segment that matched no real path at all -- while
    -- `node_modules`, which contains no metacharacter, survived untouched and
    -- did work. On Windows, `:Insights tree`/`count` included every file
    -- under `.git/`, the bulk of the listing on any real repository. The Unix
    -- branch was never affected: it passes globs to `find -not -path`
    -- verbatim, with no translation at all.
    H.contains(ps, "\\.git", "a dot is escaped regex-style now")
    H.excludes(ps, "%.git", "not Lua-pattern-style")
    H.excludes(ps, "sed", "with no Unix tools assumed")
    windows = false

    -- With no exclusions the filter is left out entirely.
    config.setup({ tree = { outdir = outdir, outfile_fmt = "%s-tree.txt", exclude_patterns = {} } })
    windows = true
    run_tree()
    H.excludes(shell.calls[1], "$rx=@(", "no exclusions means no filter stage")
    windows = false
    run_tree()
    H.excludes(shell.calls[1], "-not -path", "on Unix too")
    config.setup({
      tree = {
        outdir = outdir,
        outfile_fmt = "%s-tree.txt",
        exclude_patterns = { "*/.git/*", "*/node_modules/*" },
      },
    })

    -- Failures.
    shell.answer = { ok = false, stdout = "", stderr = "find exploded" }
    local ok_fail, msg_fail, path_fail = run_tree()
    H.falsy(ok_fail, "a failing listing fails write_tree")
    H.contains(msg_fail, "tree write failed", "with a message")
    H.contains(msg_fail, "find exploded", "quoting the shell error")
    H.ok(path_fail, "and the intended output path is still reported")

    -- An outdir that cannot be created.
    config.setup({ tree = { outdir = dir .. "/compressed/file-list.txt", outfile_fmt = "%s.txt" } })
    shell.answer = { ok = true, stdout = "x\n", stderr = "" }
    shell.calls = {}
    local ok_dir, msg_dir
    tree.write_tree(function(o, m)
      ok_dir, msg_dir = o, m
    end)
    H.falsy(ok_dir, "an outdir that cannot be created fails before the shell runs")
    H.contains(msg_dir or "", "cannot create outdir", "with that reason")
    H.eq(#shell.calls, 0, "and nothing is spawned")
    config.setup({ tree = { outdir = outdir, outfile_fmt = "%s-tree.txt" } })

    -- ── count_files ────────────────────────────────────────────────────────
    shell.answer = { ok = true, stdout = "a\nb\nc\n", stderr = "" }
    local count_ok, count_msg, count
    tree.count_files(function(o, m, n)
      count_ok, count_msg, count = o, m, n
    end)
    H.ok(count_ok, "count_files succeeds")
    H.eq(count, 3, "counting the listing's lines in Lua, not with wc")
    H.contains(count_msg or "", "files: 3", "and saying so")

    shell.answer = { ok = true, stdout = "a\r\nb\r\n", stderr = "" }
    tree.count_files(function(_, _, n)
      count = n
    end)
    H.eq(count, 2, "CRLF output counts the same")

    shell.answer = { ok = true, stdout = "", stderr = "" }
    tree.count_files(function(_, _, n)
      count = n
    end)
    H.eq(count, 0, "an empty listing is zero files")

    shell.answer = { ok = false, stdout = "", stderr = "boom" }
    local count_fail_ok, count_fail_msg
    tree.count_files(function(o, m)
      count_fail_ok, count_fail_msg = o, m
    end)
    H.falsy(count_fail_ok, "a failing listing fails the count")
    H.contains(count_fail_msg or "", "count failed", "with a message")

    -- ── copy_to_clipboard ──────────────────────────────────────────────────
    shell.answer = { ok = true, stdout = "lua/a.lua\nlua/b.lua\n", stderr = "" }
    local written_path = select(3, run_tree())

    clipboard.ok, clipboard.text = true, nil
    local clip_ok, clip_msg
    tree.copy_to_clipboard(function(o, m)
      clip_ok, clip_msg = o, m
    end)
    H.ok(clip_ok, "the generated tree file is copied")
    H.contains(clip_msg or "", "copied to clipboard", "and says so")
    H.eq(clipboard.text, "lua/a.lua\nlua/b.lua", "handing the file's contents to the backend")

    clipboard.ok = false
    tree.copy_to_clipboard(function(o, m)
      clip_ok, clip_msg = o, m
    end)
    H.falsy(clip_ok, "a clipboard backend that refuses is reported")
    H.contains(clip_msg or "", "clipboard backend unavailable", "with that message")
    clipboard.ok = true

    vim.fn.delete(written_path)
    tree.copy_to_clipboard(function(o, m)
      clip_ok, clip_msg = o, m
    end)
    H.falsy(clip_ok, "with no tree file there is nothing to copy")
    H.contains(clip_msg or "", "tree file not found", "and it says which one is missing")
  end)

  for _, name in ipairs(stubbed_modules) do
    package.loaded[name] = saved[name]
  end
  config.setup({})
  cleanup()

  if not ok_body then
    error(err_body, 0)
  end
end
