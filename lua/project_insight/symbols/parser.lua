---@module 'project_insight.symbols.parser'
---@brief Parse ripgrep --vimgrep output into SymbolEntry objects.
local M = {}

local patterns_mod = require("project_insight.symbols.patterns")

---Parse a single `filename:line:col:text` line from rg --vimgrep.
---Returns nil on malformed input.
---@param line string
---@return { filename:string, lnum:integer, col:integer, text:string }|nil
local function parse_vimgrep_line(line)
  if type(line) ~= "string" or line == "" then return nil end
  local parts = {}
  local pos = 1
  for i = 1, 3 do
    local cp = line:find(":", pos, true)
    if not cp then return nil end
    parts[i] = line:sub(pos, cp - 1)
    pos = cp + 1
  end
  parts[4] = line:sub(pos)
  local lnum = tonumber(parts[2])
  local col  = tonumber(parts[3])
  if not lnum or not col then return nil end
  return { filename = parts[1], lnum = lnum, col = col, text = vim.trim(parts[4]) }
end

---Extract function name from matched text.
---@param text     string
---@param language string
---@return string|nil
local function extract_name(text, language)
  if language == "lua" then
    return text:match("function%s+([A-Za-z_][A-Za-z0-9_.]*)")
        or text:match("([A-Za-z_][A-Za-z0-9_.]*)%s*=%s*function")
  end
  if language == "python" then
    return text:match("def%s+([A-Za-z_][A-Za-z0-9_]*)")
  end
  if language == "javascript" or language == "typescript" then
    return text:match("function%s+([A-Za-z_$][A-Za-z0-9_$]*)")
        or text:match("const%s+([A-Za-z_$][A-Za-z0-9_$]*)%s*=")
        or text:match("([A-Za-z_$][A-Za-z0-9_$]*)%s*%(")
  end
  if language == "go" then
    return text:match("func%s+%(.-%)%s+([A-Za-z_][A-Za-z0-9_]*)")
        or text:match("func%s+([A-Za-z_][A-Za-z0-9_]*)")
  end
  if language == "rust" then
    return text:match("fn%s+([A-Za-z_][A-Za-z0-9_]*)")
  end
  if language == "c" or language == "cpp" then
    return text:match("([A-Za-z_][A-Za-z0-9_]*)%s*%(")
  end
  if language == "java" then
    return text:match("[%s%w]+%s+([A-Za-z_][A-Za-z0-9_]*)%s*%(")
  end
  if language == "ruby" then
    return text:match("def%s+([A-Za-z_][A-Za-z0-9_?!]*)")
  end
  if language == "php" then
    return text:match("function%s+([A-Za-z_][A-Za-z0-9_]*)")
  end
  return nil
end

---Extract a cleaned signature like `foo(x, y)` from matched text.
---@param text string
---@param name string
---@return string
local function extract_signature(text, name)
  local name_pos = text:find(name, 1, true)
  if not name_pos then return name .. "()" end
  local ps = text:find("%(", name_pos)
  if not ps then return name .. "()" end
  local depth, pe = 1, nil
  for i = ps + 1, #text do
    local c = text:sub(i, i)
    if c == "(" then depth = depth + 1
    elseif c == ")" then
      depth = depth - 1
      if depth == 0 then pe = i; break end
    end
  end
  if not pe then return name .. "(...)" end
  local params = vim.trim(text:sub(ps + 1, pe - 1))
  if #params > 40 then params = params:sub(1, 37) .. "..." end
  return name .. "(" .. params .. ")"
end

---Parse rg output lines into structured entries.
---@param lines              string[]
---@param enabled_languages  table<string, boolean>
---@return table[], string[]  entries, errors
function M.parse(lines, enabled_languages)
  if type(lines) ~= "table" then
    return {}, { "expected table of strings" }
  end

  local entries, errors = {}, {}

  for i, line in ipairs(lines) do
    local rg = parse_vimgrep_line(line)
    if rg then
      local lang = patterns_mod.detect_language(rg.filename)
      if lang and enabled_languages[lang] then
        local name = extract_name(rg.text, lang)
        if name then
          entries[#entries + 1] = {
            filename  = rg.filename,
            lnum      = rg.lnum,
            col       = rg.col,
            text      = rg.text,
            name      = name,
            func_type = patterns_mod.infer_func_type(rg.text, lang),
            language  = lang,
            signature = extract_signature(rg.text, name),
          }
        else
          errors[#errors + 1] = string.format("line %d: no name extracted: %s", i, line)
        end
      end
    else
      errors[#errors + 1] = string.format("line %d: parse failed: %s", i, line)
    end
  end

  return entries, errors
end

return M
