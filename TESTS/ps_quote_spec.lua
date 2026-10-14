-- TESTS/ps_quote_spec.lua -- the PowerShell commands of insights.compress and
-- insights.tree against paths that hold a typographic single quote.
--
-- PowerShell counts U+2018..U+201B as quote characters. The commands used to
-- double only the ASCII `'`, so a project directory called `it’s` closed the
-- string early (a parse error, or script text taken from the directory name).
-- Needs Windows and a real powershell: the commands are run, not just read.

return function(H)
  local platform = require("insights.util.platform")

  if not platform.is_windows() then
    print("      (skipped: the PowerShell engines are Windows-only)")
    return
  end
  if vim.fn.executable("powershell") ~= 1 then
    print("      (skipped: powershell.exe not on PATH)")
    return
  end

  local compress = require("insights.compress")
  local tree = require("insights.tree")

  local function q(cp)
    return vim.fn.nr2char(cp)
  end
  local names = {
    "it" .. q(0x2019) .. "s",
    "a" .. q(0x2018) .. "b",
    "c" .. q(0x201A) .. "d",
    "e" .. q(0x201B) .. "f",
    "g'h",
    "x'; Write-Output INJECTED; '",
    "x" .. q(0x2019) .. "; Write-Output INJECTED; " .. q(0x2019),
  }

  ---@type table<string, true>
  local compress_names = { [names[1]] = true, [names[5]] = true, [names[7]] = true }

  local dir, cleanup = H.fixture("ps-quote")
  local ok_body, err_body = pcall(function()
    for _, name in ipairs(names) do
      local sub = dir .. "/" .. name
      vim.fn.mkdir(sub, "p")
      vim.fn.writefile({ "x" }, sub .. "/a.txt")

      -- tree: the listing command runs and lists the file relative to the project
      local cmd = tree._internal.build_tree_cmd(sub, {})
      -- (a bounded wait: a PowerShell that never ends is reported with what it printed, not waited for)
      local res = vim
        .system({ "powershell", "-NoProfile", "-NonInteractive", "-Command", cmd }, { text = true })
        :wait(10000)
      local probes = ""
      if res.code == 124 then
        -- the process was killed after 30 s: say whether PowerShell works at all here, and whether a closed stdin helps
        local function probe(label, command, stdin)
          local t0 = vim.uv.hrtime()
          local r = vim
            .system(
              { "powershell", "-NoProfile", "-NonInteractive", "-Command", command },
              { text = true, stdin = stdin }
            )
            :wait(8000)
          return ("%s: code=%s %.1fs out=%s"):format(
            label,
            tostring(r.code),
            (vim.uv.hrtime() - t0) / 1e9,
            vim.inspect((r.stdout or ""):sub(1, 80))
          )
        end
        probes = " | probes: "
          .. probe("version", "$PSVersionTable.PSVersion.ToString()", nil)
          .. " ; "
          .. probe("same command, stdin closed", cmd, false)
        -- the same command as -EncodedCommand (UTF-16LE base64): no command-line codepage involved
        local enc = vim.base64.encode(vim.iconv(cmd, "utf-8", "utf-16le") or "")
        local t0 = vim.uv.hrtime()
        local r = vim
          .system(
            { "powershell", "-NoProfile", "-NonInteractive", "-EncodedCommand", enc },
            { text = true, stdin = false }
          )
          :wait(8000)
        probes = probes
          .. (" ; encoded: code=%s %.1fs out=%s err=%s"):format(
            tostring(r.code),
            (vim.uv.hrtime() - t0) / 1e9,
            vim.inspect((r.stdout or ""):sub(1, 80)),
            vim.inspect((r.stderr or ""):sub(1, 80))
          )
        -- the listing on its own, the directory handed over in the environment (no path text in the command line)
        local function env_probe(label, command, where)
          local t1 = vim.uv.hrtime()
          local pr = vim
            .system(
              { "powershell", "-NoProfile", "-NonInteractive", "-Command", command },
              { text = true, stdin = false, env = { PSQ_DIR = where } }
            )
            :wait(8000)
          return (" ; %s: code=%s %.1fs out=%s"):format(
            label,
            tostring(pr.code),
            (vim.uv.hrtime() - t1) / 1e9,
            vim.inspect((pr.stdout or ""):sub(1, 60))
          )
        end
        local list =
          "Get-ChildItem -LiteralPath $env:PSQ_DIR -Recurse -File | Select-Object -ExpandProperty FullName"
        probes = probes
          .. env_probe("gci temp (ascii)", list, vim.uv.os_tmpdir())
          .. env_probe("gci fixture (env)", list, sub)
      end
      H.eq(
        res.code,
        0,
        "tree: the command parses and runs for "
          .. vim.inspect(name)
          .. " (stderr: "
          .. vim.inspect(res.stderr)
          .. ", stdout: "
          .. vim.inspect(res.stdout)
          .. ")"
          .. probes
      )
      H.contains(res.stdout or "", "a.txt", "tree: and lists the file for " .. vim.inspect(name))
      H.excludes(res.stdout or "", "INJECTED", "tree: no script text taken from the name")

      -- compress (two more PowerShell processes per name, so only the
      -- representative ones): listing and Compress-Archive both run, the
      -- archive exists
      if compress_names[name] then
        local done, ok, msg
        compress.compress(sub, { engine = "powershell", outdir = "" }, function(o, m)
          done, ok, msg = true, o, m
        end)
        vim.wait(30000, function()
          return done
        end, 50)
        local stage = ""
        if not done then
          -- how far it got: the listing is written between the two PowerShell runs, the archive by the second one
          local function size(path)
            local st = vim.uv.fs_stat(path)
            return st and tostring(st.size) or "absent"
          end
          stage = (" [file-list.txt: %s, zip: %s]"):format(
            size(sub .. "/compressed/file-list.txt"),
            size(sub .. "/compressed/" .. name .. ".zip")
          )
        end
        H.ok(
          done == true,
          "compress: calls back within 30 s for "
            .. vim.inspect(name)
            .. " (done="
            .. tostring(done)
            .. ")"
            .. stage
        )
        H.ok(ok, "compress: succeeds for " .. vim.inspect(name) .. " -- " .. tostring(msg))
        H.eq(
          vim.fn.filereadable(sub .. "/compressed/" .. name .. ".zip"),
          1,
          "compress: and writes the archive"
        )
      end
    end
  end)
  cleanup()
  if not ok_body then
    error(err_body, 0)
  end
end
