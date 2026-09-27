---@module 'insights.todos.highlight'
--- The in-buffer half of `insights.todos`: colour every annotation keyword
--- in the lines currently on screen, colour the rest of its comment more
--- quietly, and put the keyword's glyph in the sign column.
---
--- Visible range only, on purpose. A buffer is re-scanned when it is shown,
--- when it scrolls and (debounced) when it changes, and each pass reads only
--- the lines a window is displaying plus a margin -- which is what keeps a
--- 40,000-line log from paying for annotations it will never show. Extmarks
--- outside the range are cleared on each pass and come back when scrolled
--- to, so nothing is ever stale for longer than one scroll event.
---
--- `comments_only` asks Tree-sitter whether the match sits in a comment
--- capture, and falls back to the syntax stack where no parser is attached.
--- With neither available the match is kept: a plain-text file has no
--- comments to be inside of, and an annotation there is still one.
---
--- Highlight groups are redefined through `lib.nvim.ui.hl.persist`, so a
--- `:colorscheme` (or an `&background` flip) rebuilds them instead of
--- leaving the theme-derived foregrounds pointing at colours that no longer
--- exist.

local todos = require("insights.todos")

local M = {}

---@type integer
M.NS = vim.api.nvim_create_namespace("insights_todos")

--- Extmark priority, above Tree-sitter's comment colouring (100) so the
--- keyword's own colour shows.
local PRIORITY = 110

--- Lines beyond each window's visible range that are scanned too, so a
--- small scroll does not immediately hit unscanned ground.
local MARGIN = 40

---@type table<integer, uv.uv_timer_t>
local timers = {}

---@internal
---@return Insights.TodosConfig
local function config()
  return require("insights.config").get().todos
end

---@internal
---`error` -> `Error`, for the group names.
---@param category string
---@return string
local function capitalize(category)
  return (category:gsub("^%l", string.upper))
end

---@internal
---The first candidate that yields a colour: a `#rrggbb` literal as-is, a
---highlight group's foreground if the active theme gives it one.
---@param candidates string[]
---@return string|nil
local function resolve_color(candidates)
  for _, c in ipairs(candidates) do
    if c:sub(1, 1) == "#" then
      return c
    end
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = c, link = false })
    if ok and type(hl) == "table" and type(hl.fg) == "number" then
      return ("#%06x"):format(hl.fg)
    end
  end
  return nil
end

---@internal
---Black or white, whichever reads on `hex` -- for the keyword's own text
---when the keyword is drawn as a filled block.
---@param hex string
---@return string
local function contrast_fg(hex)
  local r = tonumber(hex:sub(2, 3), 16) or 0
  local g = tonumber(hex:sub(4, 5), 16) or 0
  local b = tonumber(hex:sub(6, 7), 16) or 0
  local luma = 0.299 * r + 0.587 * g + 0.114 * b
  return luma > 140 and "#000000" or "#ffffff"
end

---@internal
---`group_names` is a pure function of `category`, called once per match in
---`apply`'s hot loop -- cached so the `gsub` + three concatenations run
---once per category instead of once per occurrence.
---@type table<string, [string, string, string]>
local group_names_cache = {}

---Group names for a category.
---@param category string
---@return string fg, string bg, string sign
function M.group_names(category)
  local cached = group_names_cache[category]
  if cached then
    return cached[1], cached[2], cached[3]
  end
  local cat = capitalize(category)
  local fg, bg, sign = "InsightsTodoFg" .. cat, "InsightsTodoBg" .. cat, "InsightsTodoSign" .. cat
  group_names_cache[category] = { fg, bg, sign }
  return fg, bg, sign
end

---The highlight definitions for every configured category, resolved
---against the active theme. Called by `hl.persist` now and after each
---theme change.
---@return table<string, Lib.Highlight.Opts>
function M.groups()
  local out = {}
  for category, candidates in pairs(config().colors or {}) do
    local color = type(candidates) == "table" and resolve_color(candidates) or nil
    if color then
      local fg, bg, sign = M.group_names(category)
      out[fg] = { fg = color, bold = true }
      out[bg] = { bg = color, fg = contrast_fg(color), bold = true }
      out[sign] = { fg = color }
    end
  end
  return out
end

---@internal
---`sign_text` results, keyed by keyword: the (icon, keyword) pair behind
---each call is fixed for as long as the config is (see `todos.reset`), so
---the glyph and the `strdisplaywidth` VimL call it costs are only paid once
---per keyword instead of once per occurrence in the scanned range.
---@type table<string, string>
local sign_text_cache = {}

---@internal
---@param icon string
---@param keyword string
---@return string
local function sign_text(icon, keyword)
  local cached = sign_text_cache[keyword]
  if cached then
    return cached
  end
  local text = vim.trim(icon or "")
  if text == "" or vim.fn.strdisplaywidth(text) > 2 then
    text = keyword:sub(1, 1)
  end
  sign_text_cache[keyword] = text
  return text
end

---@internal
---`eligible`'s file-size stat, cached per buffer for `SIZE_STAT_TTL_MS`: it
---is the first thing `refresh` checks, and `refresh` runs debounced on
---every `TextChanged`/`TextChangedI`/`WinScrolled` -- i.e. after
---essentially every burst of scrolling or typing -- so without a cache a
---size that practically never changes mid-session is re-stat'd from disk
---just as often. The TTL keeps a file that crosses `max_file_size_kb`
---mid-session (e.g. a growing log) from going unnoticed for long, without
---paying for a syscall on every refresh.
---
---Keyed on `name` too, not just the TTL: `:file`/`:saveas` repoints a
---buffer at a different path without touching its number and without
---firing `BufUnload`/`BufWipeout` (the only events `clear()` -- which drops
---this cache -- is wired to), so a size cached for the buffer's old name
---would otherwise go on answering for its new one until the TTL happened
---to expire.
---@type table<integer, { name: string, size: integer|nil, checked_at: integer }>
local size_cache = {}

local SIZE_STAT_TTL_MS = 3000
-- Exposed so a test can wait out exactly this long instead of duplicating
-- (and risking drift from) the constant above.
M.SIZE_STAT_TTL_MS = SIZE_STAT_TTL_MS

---Is the buffer one the highlighter should touch?
---@param bufnr integer
---@return boolean
function M.eligible(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.bo[bufnr].buftype ~= "" then
    return false
  end
  local cfg = config().highlight or {}
  local ft = vim.bo[bufnr].filetype
  for _, skip in ipairs(cfg.exclude_filetypes or {}) do
    if ft == skip then
      return false
    end
  end
  local max_kb = cfg.max_file_size_kb
  if type(max_kb) == "number" and max_kb > 0 then
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
      local uv = vim.uv or vim.loop
      local now = uv.now()
      local cached = size_cache[bufnr]
      local size
      if cached and cached.name == name and now - cached.checked_at < SIZE_STAT_TTL_MS then
        size = cached.size
      else
        local st = uv.fs_stat(name)
        size = st and st.size or nil
        size_cache[bufnr] = { name = name, size = size, checked_at = now }
      end
      if size and size > max_kb * 1024 then
        return false
      end
    end
  end
  return true
end

---@internal
---The buffer's parser, if its filetype has one. `get_parser` raises on 0.10
---and returns nil on 0.11 when there is none; both read as "no parser".
---@param bufnr integer
---@return vim.treesitter.LanguageTree|nil
local function parser_for(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if ok and parser then
    return parser
  end
  return nil
end

---@internal
---Tree-sitter's answer, or nil when the buffer has no parser.
---
---`get_node`, not `get_captures_at_pos`: the latter reads the *highlighter's*
---trees and answers with nothing at all for a buffer that has a parser but
---no active Tree-sitter highlighting -- which is exactly the buffer where a
---wrong "not a comment" would go unnoticed. The node tree is there
---regardless, once parsed (see `apply`, which parses the range it scans).
---Every language names its comment node with the word in it (`comment`,
---`line_comment`, `block_comment`), and a keyword inside a doc comment sits
---in a child node of one, so the walk goes up to the root before giving up.
---
---Three layers, cheapest and most common first:
---
---1. The host language's own node, injections ignored entirely. This alone
---   answers most matches: a doc-comment markup grammar layered *on top of*
---   an already-`comment`-typed host node (nvim-treesitter's `comment`
---   catch-all for TODO/FIXME markup, `jsdoc` for JS/TS `/** */`, `luadoc`
---   for Lua's own `---@param`/`---@field`/...) has node types that never
---   contain the word "comment" themselves (`source`, `tag`, `name`, ...),
---   so asking the injected grammar first -- as this function used to --
---   answers "not a comment" for text that plainly is one. The host tree
---   was never fooled by that, so it is checked before any injection.
---2. Sitting inside a tree whose *language* is literally named `comment`,
---   however many injection layers deep (a `comment` markup grammar can
---   itself be injected inside another embedded language, e.g. vimscript
---   inside a Lua string). `language_for_range` recurses through every
---   injection layer and answers by name, which is reliable where a node's
---   own type is not.
---3. A genuinely different embedded language with its own real comment
---   syntax (SQL in a string, vimscript in a `vim.cmd()` call) whose
---   injected grammar is not itself named `comment` -- only that grammar's
---   own node types reveal the position is inside one of its comments.
---@param bufnr integer
---@param row integer
---@param col integer
---@param parser vim.treesitter.LanguageTree|nil Already-resolved parser for
---`bufnr`, e.g. `apply`'s -- avoids re-resolving it for every match.
---@return boolean|nil
local function ts_in_comment(bufnr, row, col, parser)
  parser = parser or parser_for(bufnr)
  if not parser then
    return nil
  end

  local ok_host, host_node = pcall(vim.treesitter.get_node, {
    bufnr = bufnr,
    pos = { row, col },
    ignore_injections = true,
  })
  if ok_host and host_node then
    local n = host_node
    while n do
      if n:type():find("comment", 1, true) then
        return true
      end
      n = n:parent()
    end
  end

  local range = { row, col, row, col }
  local ok_lt, lang_tree = pcall(parser.language_for_range, parser, range)
  if ok_lt and lang_tree and lang_tree:lang() == "comment" then
    return true
  end

  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = bufnr,
    pos = { row, col },
    ignore_injections = false,
  })
  if not ok then
    return nil
  end
  while node do
    if node:type():find("comment", 1, true) then
      return true
    end
    node = node:parent()
  end
  return false
end

---Does position (`row`, `col`, both 0-based) sit inside a comment?
---@param bufnr integer
---@param row integer
---@param col integer
---@param parser vim.treesitter.LanguageTree|nil Already-resolved parser for
---`bufnr`, if the caller has one -- see `ts_in_comment`.
---@return boolean
function M.is_comment(bufnr, row, col, parser)
  local ts = ts_in_comment(bufnr, row, col, parser)
  if ts ~= nil then
    return ts
  end
  -- No parser: the syntax stack, which only knows the buffer shown in the
  -- current window -- hence buf_call.
  local in_comment = nil
  vim.api.nvim_buf_call(bufnr, function()
    if vim.bo[bufnr].syntax == "" then
      return
    end
    local stack = vim.fn.synstack(row + 1, col + 1)
    if type(stack) ~= "table" or #stack == 0 then
      in_comment = false
      return
    end
    in_comment = false
    for _, id in ipairs(stack) do
      if vim.fn.synIDattr(vim.fn.synIDtrans(id), "name"):find("Comment", 1, true) then
        in_comment = true
        return
      end
    end
  end)
  if in_comment == nil then
    return true
  end
  return in_comment
end

---Scan lines `first`..`last` (0-based, `last` exclusive) and place the
---extmarks. Clears the range first, so it is safe to call repeatedly.
---@param bufnr integer
---@param first integer
---@param last integer
---@return integer count Keywords marked.
function M.apply(bufnr, first, last)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end
  local cfg = config().highlight or {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  first = math.max(first, 0)
  last = math.min(last, line_count)
  if first >= last then
    return 0
  end

  vim.api.nvim_buf_clear_namespace(bufnr, M.NS, first, last)

  local re = todos.compiled_pattern()
  if not re then
    return 0
  end
  -- A tree that is not known to be parsed can hand `get_node` a stale
  -- node. Parsing is incremental, and this range is what is scanned below.
  -- Resolved once here and threaded into `is_comment` below, which would
  -- otherwise re-resolve the same parser for every match in the range.
  local parser
  if cfg.comments_only ~= false then
    parser = parser_for(bufnr)
    if parser then
      pcall(parser.parse, parser, { first, 0, last, 0 })
    end
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, first, last, false)
  local count = 0
  for i, line in ipairs(lines) do
    local row = first + i - 1
    local start = 0
    while start < #line do
      -- `match_line`, not `match_str(line:sub(start + 1))`: it matches
      -- directly against the buffer from a byte offset and returns indices
      -- already relative to that offset, so a line with several matches
      -- does not allocate a shrinking copy of its own tail on every one.
      local s, e = re:match_line(bufnr, row, start)
      if not s then
        break
      end
      local col_s, col_e = start + s, start + e
      local word = line:sub(col_s + 1, col_e)
      local info = todos.lookup(word)
      if info and (cfg.comments_only == false or M.is_comment(bufnr, row, col_s, parser)) then
        local fg, bg, sign = M.group_names(info.color)
        local mark = {
          end_col = col_e,
          hl_group = bg,
          priority = PRIORITY,
        }
        if cfg.signs ~= false then
          mark.sign_text = sign_text(info.icon, info.keyword)
          mark.sign_hl_group = sign
        end
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.NS, row, col_s, mark)
        if col_e < #line then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, M.NS, row, col_e, {
            end_col = #line,
            hl_group = fg,
            priority = PRIORITY,
          })
        end
        count = count + 1
      end
      start = col_e
    end
  end
  return count
end

---Remove everything this module placed in a buffer.
---@param bufnr integer
function M.clear(bufnr)
  if timers[bufnr] then
    timers[bufnr]:stop()
    timers[bufnr]:close()
    timers[bufnr] = nil
  end
  size_cache[bufnr] = nil
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.NS, 0, -1)
  end
end

---Re-scan the parts of `bufnr` that some window is showing.
---@param bufnr integer
function M.refresh(bufnr)
  if not M.eligible(bufnr) then
    M.clear(bufnr)
    return
  end
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins == 0 then
    return
  end
  -- One clear for the whole buffer, then one apply per window's range:
  -- ranges of two windows on the same buffer may overlap, and clearing per
  -- range would wipe the first window's marks while placing the second's.
  vim.api.nvim_buf_clear_namespace(bufnr, M.NS, 0, -1)
  for _, win in ipairs(wins) do
    -- One table, not two values: an API call returns a single result.
    local range = vim.api.nvim_win_call(win, function()
      return { vim.fn.line("w0"), vim.fn.line("w$") }
    end)
    M.apply(bufnr, range[1] - 1 - MARGIN, range[2] + MARGIN)
  end
end

---`refresh`, debounced per buffer.
---@param bufnr integer
function M.schedule(bufnr)
  local ms = (config().highlight or {}).debounce_ms
  if type(ms) ~= "number" or ms <= 0 then
    M.refresh(bufnr)
    return
  end
  local t = timers[bufnr]
  if not t then
    t = (vim.uv or vim.loop).new_timer()
    timers[bufnr] = t
  end
  t:stop()
  t:start(ms, 0, function()
    vim.schedule(function()
      if timers[bufnr] then
        M.refresh(bufnr)
      end
    end)
  end)
end

---Define the highlight groups now and again after every theme change.
---@return Lib.UI.HL.PersistHandle
function M.setup_groups()
  return require("lib.nvim.ui.hl").persist(M.groups, { name = "insights_todos" })
end

---Drop `sign_text`'s per-keyword cache, so a re-run of `setup()` with a
---changed icon table is picked up instead of serving a stale glyph.
function M.reset()
  sign_text_cache = {}
end

return M
