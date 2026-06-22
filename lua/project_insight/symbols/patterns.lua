---@module 'project_insight.symbols.patterns'
---@brief PCRE2 patterns and extension maps for ripgrep-based symbol detection.
local M = {}

---@class SymbolPattern
---@field language  string
---@field pattern   string   PCRE2 regex for rg --pcre2
---@field func_type string   "local"|"global"|"module"|"anonymous"|"method"|"exported"
---@field name_capture      integer  capture group index for the symbol name
---@field signature_capture integer|nil

---@type SymbolPattern[]
local PATTERNS = {
  -- Lua
  { language="lua", func_type="local",     name_capture=1, signature_capture=2,
    pattern=[[^\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
  { language="lua", func_type="global",    name_capture=1, signature_capture=2,
    pattern=[[^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
  { language="lua", func_type="module",    name_capture=1, signature_capture=2,
    pattern=[[^\s*function\s+([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
  { language="lua", func_type="module",    name_capture=1, signature_capture=2,
    pattern=[[^\s*([A-Za-z_][A-Za-z0-9_.]+)\s*=\s*function\s*\(([^)]*)\)]] },
  { language="lua", func_type="anonymous", name_capture=1, signature_capture=2,
    pattern=[[^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\(([^)]*)\)]] },

  -- Python
  { language="python", func_type="global", name_capture=1, signature_capture=2,
    pattern=[[^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
  { language="python", func_type="global", name_capture=1, signature_capture=2,
    pattern=[[^\s*async\s+def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
  { language="python", func_type="method", name_capture=1, signature_capture=2,
    pattern=[[^\s+def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },

  -- JavaScript
  { language="javascript", func_type="global",   name_capture=1, signature_capture=2,
    pattern=[[^\s*function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(([^)]*)\)]] },
  { language="javascript", func_type="exported", name_capture=1, signature_capture=2,
    pattern=[[^\s*export\s+function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(([^)]*)\)]] },
  { language="javascript", func_type="anonymous",name_capture=1, signature_capture=2,
    pattern=[[^\s*const\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:async\s*)?\(([^)]*)\)\s*=>]] },
  { language="javascript", func_type="method",   name_capture=1, signature_capture=2,
    pattern=[[^\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\(([^)]*)\)\s*\{]] },

  -- TypeScript
  { language="typescript", func_type="exported", name_capture=1, signature_capture=2,
    pattern=[[^\s*export\s+function\s+([A-Za-z_$][A-Za-z0-9_$]*)<[^>]*>\s*\(([^)]*)\)]] },
  { language="typescript", func_type="global",   name_capture=1, signature_capture=2,
    pattern=[[^\s*function\s+([A-Za-z_$][A-Za-z0-9_$]*)<[^>]*>\s*\(([^)]*)\)]] },

  -- Go
  { language="go", func_type="global", name_capture=1, signature_capture=2,
    pattern=[[^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
  { language="go", func_type="method", name_capture=1, signature_capture=2,
    pattern=[[^\s*func\s+\([^)]+\)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },

  -- Rust
  { language="rust", func_type="local",    name_capture=1, signature_capture=2,
    pattern=[[^\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
  { language="rust", func_type="exported", name_capture=1, signature_capture=2,
    pattern=[[^\s*pub\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
  { language="rust", func_type="method",   name_capture=1, signature_capture=2,
    pattern=[[^\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },

  -- C
  { language="c", func_type="global", name_capture=1, signature_capture=2,
    pattern=[[^\s*(?:static\s+)?(?:inline\s+)?[A-Za-z_][A-Za-z0-9_*\s]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*\{]] },

  -- C++
  { language="cpp", func_type="global", name_capture=1, signature_capture=2,
    pattern=[[^\s*(?:virtual\s+)?(?:static\s+)?(?:inline\s+)?[A-Za-z_][A-Za-z0-9_:*\s<>]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
  { language="cpp", func_type="method", name_capture=2, signature_capture=3,
    pattern=[[^\s*([A-Za-z_][A-Za-z0-9_]*)::\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },

  -- Java
  { language="java", func_type="method", name_capture=1, signature_capture=2,
    pattern=[[^\s*(?:public|private|protected)?\s*(?:static\s+)?(?:final\s+)?[A-Za-z_<>[\]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },

  -- Ruby
  { language="ruby", func_type="global", name_capture=1, signature_capture=2,
    pattern=[[^\s*def\s+([A-Za-z_][A-Za-z0-9_?!]*)\s*\(([^)]*)\)]] },
  { language="ruby", func_type="method", name_capture=1, signature_capture=2,
    pattern=[[^\s*def\s+self\.([A-Za-z_][A-Za-z0-9_?!]*)\s*\(([^)]*)\)]] },

  -- PHP
  { language="php", func_type="method", name_capture=1, signature_capture=2,
    pattern=[[^\s*(?:public|private|protected)?\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)]] },
}

---Extension → language mapping.
---@type table<string, string>
local EXT_TO_LANG = {
  lua="lua", py="python", pyw="python",
  js="javascript", jsx="javascript", mjs="javascript",
  ts="typescript", tsx="typescript",
  go="go", rs="rust",
  c="c", h="c",
  cpp="cpp", cc="cpp", cxx="cpp", hpp="cpp", hh="cpp", hxx="cpp",
  java="java", rb="ruby", php="php",
}

---Language → list of file extensions.
---@type table<string, string[]>
local LANG_EXTS = {
  lua        = { "lua" },
  python     = { "py", "pyw" },
  javascript = { "js", "jsx", "mjs" },
  typescript = { "ts", "tsx" },
  go         = { "go" },
  rust       = { "rs" },
  c          = { "c", "h" },
  cpp        = { "cpp", "cc", "cxx", "hpp", "hh", "hxx" },
  java       = { "java" },
  ruby       = { "rb" },
  php        = { "php" },
}

---Return enabled patterns.
---@param enabled_languages table<string, boolean>
---@return SymbolPattern[]
function M.get_patterns(enabled_languages)
  local out = {}
  for _, p in ipairs(PATTERNS) do
    if enabled_languages[p.language] then
      out[#out + 1] = p
    end
  end
  return out
end

---Return file extensions for enabled languages.
---@param enabled_languages table<string, boolean>
---@return string[]
function M.get_extensions(enabled_languages)
  local seen, result = {}, {}
  for lang, exts in pairs(LANG_EXTS) do
    if enabled_languages[lang] then
      for _, ext in ipairs(exts) do
        if not seen[ext] then
          seen[ext] = true
          result[#result + 1] = ext
        end
      end
    end
  end
  return result
end

---Detect language from filename.
---@param filename string
---@return string|nil
function M.detect_language(filename)
  local ext = filename:match("%.([^%.]+)$")
  return ext and EXT_TO_LANG[ext:lower()] or nil
end

---Infer func_type from matched text (fallback heuristic).
---@param text string
---@param language string
---@return string
function M.infer_func_type(text, language)
  if language == "lua" then
    if text:match("^%s*local%s+function") then return "local" end
    if text:match("^%s*function%s+[A-Za-z_][A-Za-z0-9_]*%.[A-Za-z_]") then return "module" end
    if text:match("^%s*function%s+") then return "global" end
    if text:match("=%s*function%s*%(") then return "anonymous" end
  end
  if language == "python" then
    if text:match("^%s+def%s+") then return "method" end
    if text:match("^%s*async%s+def") then return "global" end
  end
  if language == "javascript" or language == "typescript" then
    if text:match("^%s*export%s+function") then return "exported" end
    if text:match("=>") then return "anonymous" end
  end
  return "unknown"
end

return M
