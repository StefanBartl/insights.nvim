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
      local res = vim
        .system({ "powershell", "-NoProfile", "-NonInteractive", "-Command", cmd }, { text = true })
        :wait()
      H.eq(res.code, 0, "tree: the command parses and runs for " .. vim.inspect(name))
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
        vim.wait(60000, function()
          return done
        end, 50)
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
