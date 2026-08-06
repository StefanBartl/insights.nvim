---@module 'insights.scan.rg'
---@brief Ripgrep command builder and executor.
---
--- Low-level scan utility: reports status only, never notifies the user
--- directly — callers decide whether/how to surface an error (see
--- Refactoring..md "fail late / report at the boundary").
local M = {}

---Build rg --vimgrep command arguments.
---@param pattern string   PCRE2 pattern
---@param extensions string[]  e.g. {"lua", "py"}
---@param opts { cwd?: string, exclude_patterns?: string[], max_file_size_kb?: integer, follow_symlinks?: boolean }
---@return string[]
function M.build_cmd(pattern, extensions, opts)
  opts = opts or {}
  local cmd = { "rg", "--vimgrep", "--no-heading", "--pcre2" }

  for _, ext in ipairs(extensions) do
    cmd[#cmd + 1] = "--glob"
    cmd[#cmd + 1] = "*." .. ext
  end

  for _, excl in ipairs(opts.exclude_patterns or {}) do
    cmd[#cmd + 1] = "--glob"
    cmd[#cmd + 1] = "!" .. excl
  end

  if opts.max_file_size_kb and opts.max_file_size_kb > 0 then
    cmd[#cmd + 1] = "--max-filesize"
    cmd[#cmd + 1] = tostring(opts.max_file_size_kb) .. "K"
  end

  if opts.follow_symlinks then
    cmd[#cmd + 1] = "--follow"
  end

  cmd[#cmd + 1] = pattern
  cmd[#cmd + 1] = opts.cwd or "."

  return cmd
end

---How long a single rg invocation may take before it is given up on. A scan of
---a very large tree can legitimately take a while; this only exists so a wedged
---process can't hang the editor forever.
local TIMEOUT_MS = 120000

---Execute rg and wait for it; returns (lines, exit_code).
---
---Deliberately `vim.system` + `vim.wait` rather than `vim.fn.systemlist`, even
---though both block the caller and this function's signature is unchanged.
---
---The reason is specifically `vim.schedule`, not libuv: a bare `vim.uv` timer
---does keep ticking during `vim.fn.system`, but scheduled callbacks do not run
---until the main loop is free. `lib.nvim.progress` needs them — its delay guard
---is `vim.schedule_wrap`'d and the statusline style's `:redrawstatus` is
---`vim.schedule`'d — so under `systemlist` a handle never becomes visible at
---all. Measured against this repo's own tree: 0 statusline updates with
---`systemlist`, 75 with the `vim.wait` pump, same instrumentation both times.
---That is what lets `symbols.rg_index` report progress from an otherwise
---synchronous build without every caller having to become callback-based.
---@param cmd string[]
---@return string[], integer
function M.exec_sync(cmd)
  local result = nil
  vim.system(cmd, { text = true }, function(res)
    result = res
  end)

  local completed = vim.wait(TIMEOUT_MS, function()
    return result ~= nil
  end, 10)
  if not completed or not result then
    return {}, -1
  end

  local out = result.stdout or ""
  if out == "" then
    return {}, result.code
  end
  -- `systemlist`'s contract: one entry per line, no trailing empty element.
  return vim.split(out:gsub("\r?\n$", ""), "\r?\n"), result.code
end

---Run one rg search and return lines. Never notifies — returns an error
---message instead so the caller can decide whether/how to report it.
---@param cmd string[]
---@param label string|nil   e.g. language name, used in the error message
---@return string[] lines
---@return string|nil err
function M.run(cmd, label)
  if vim.fn.executable("rg") ~= 1 then
    return {}, "ripgrep (rg) not found in PATH"
  end
  local lines, code = M.exec_sync(cmd)
  if code == 0 then
    return lines, nil
  elseif code == 1 then
    return {}, nil -- exit 1 = no matches, not an error
  else
    return {}, string.format("%s: rg exited %d", label or "rg", code)
  end
end

return M
