-- TESTS/run.lua — headless test runner for insights.nvim.
--
-- Run from the repo root:
--   nvim --headless -u NONE -c "set rtp+=." -l TESTS/run.lua
--
-- lib.nvim has to be reachable: several insights modules
-- require it at module load. The runner puts a sibling checkout on the
-- runtimepath, or whatever $LIB_NVIM_PATH points at.

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

do
  local candidates = {}
  if vim.env.LIB_NVIM_PATH and vim.env.LIB_NVIM_PATH ~= "" then
    candidates[#candidates + 1] = vim.env.LIB_NVIM_PATH
  end
  candidates[#candidates + 1] = dir .. "../../lib.nvim"
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"

  for _, path in ipairs(candidates) do
    local norm = vim.fs.normalize(path)
    if vim.fn.isdirectory(norm .. "/lua/lib") == 1 then
      vim.opt.rtp:append(norm)
      package.path = table.concat({
        norm .. "/lua/?.lua",
        norm .. "/lua/?/init.lua",
        package.path,
      }, ";")
      break
    end
  end
end

if not pcall(require, "lib.lua.tables") then
  print("FAIL  cannot locate lib.nvim (a runtime dependency of insights.nvim).")
  print("      Set $LIB_NVIM_PATH, or check it out next to this repo.")
  os.exit(1)
end

local H = dofile(dir .. "harness.lua")

-- Ordered so a failure points at the smallest layer first.
local specs = {
  -- imports: the leaf helpers, then the scanners, then the report on top
  "import_util_spec.lua",
  "imports_langs_contract_spec.lua",
  "imports_langs_detail_spec.lua",
  "lua_imports_spec.lua",
  "imports_ts_requires_spec.lua",
  "imports_resolve_spec.lua",
  "imports_definition_spec.lua",
  "imports_graph_spec.lua",
  "import_index_spec.lua",
  "imports_report_spec.lua",
  "hover_spec.lua",

  -- symbols: patterns/parser, the scan layer, the scanners, the facade
  "symbols_patterns_parser_spec.lua",
  "scan_rg_spec.lua",
  "scan_cache_spec.lua",
  "symbols_ts_lua_spec.lua",
  "symbols_index_spec.lua",
  "symbols_open_spec.lua",

  -- metrics and the smell scans built on its file lister
  "metrics_analyzer_spec.lua",
  "metrics_report_spec.lua",
  "metrics_init_spec.lua",
  "smells_spec.lua",
  "smells_run_spec.lua",

  -- the remaining features
  "unimported_spec.lua",
  "conflicts_spec.lua",
  "compress_tree_spec.lua",
  "devserver_spec.lua",
  "devserver_extra_spec.lua",
  "ui_fileinfo_spec.lua",

  -- config, then everything that is wired from it
  "config_spec.lua",
  "bindings_spec.lua",
  "health_init_spec.lua",
}

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(dir .. name)
  local ok, err = pcall(run, H)
  if ok then
    print(("ok    %s"):format(name))
  else
    failed = failed + 1
    print(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  print(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

print("\nINSIGHTS_TESTS_OK")
