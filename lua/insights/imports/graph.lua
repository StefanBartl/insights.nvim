---@module 'insights.imports.graph'
---@brief Render the import/require dependency data as a Graphviz PNG.
---@description
--- `insights.imports` already has the full graph structure — every entry is
--- an edge (`filename` imports `module`) — just never rendered as one. This
--- turns it into a `digraph` (nodes: importing files, and internal target
--- modules; edges: import relationships) and hands the PNG to images.nvim.
---
--- Needs Graphviz (`dot`, or whichever `graph.layout` names) on PATH —
--- reading a dependency graph out of source text needs a real layout
--- engine, no pure-Lua substitute exists. Reported as a clear error rather
--- than a silent no-op when missing, same stance images.nvim takes for its
--- own ImageMagick-only features.
---
--- External modules are excluded by default (`graph.include_external`):
--- a real project typically imports far more external modules than it has
--- source files, and including them turns the graph into noise instead of
--- showing project structure. Scope is deliberately narrower than the
--- CROSS-PLUGIN.md idea's full "dependencies, call trees, symbol
--- distribution" — call trees and symbol-distribution graphs don't exist as
--- data anywhere in insights.nvim today (symbols.lua is a flat list), and
--- inventing that analysis is a separate, much bigger feature than
--- rendering data insights.nvim already collects.

local M = {}

local notify = require("insights.util.notify").create("[insights.imports.graph]")

---@internal
---Quote a DOT identifier/label, escaping backslashes and quotes.
---@param s string
---@return string
local function dot_quote(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

---Build a Graphviz `digraph` from import entries. Pure function — reused
---directly by the test suite, no Graphviz/terminal needed to check it.
---@param entries ImportEntry[]
---@param opts { include_external?: boolean }|nil
---@return string dot_source
function M.build_dot(entries, opts)
  opts = opts or {}
  local include_external = opts.include_external == true

  ---@type table<string, boolean>
  local file_nodes = {}
  ---@type table<string, boolean> module -> is_external
  local module_nodes = {}
  ---@type table<string, boolean>
  local seen_edge = {}
  ---@type { from: string, to: string }[]
  local edges = {}

  for _, e in ipairs(entries) do
    if include_external or not e.external then
      file_nodes[e.filename] = true
      module_nodes[e.module] = e.external or false
      local edge_key = e.filename .. "\1" .. e.module
      if not seen_edge[edge_key] then
        seen_edge[edge_key] = true
        edges[#edges + 1] = { from = e.filename, to = e.module }
      end
    end
  end

  local lines = {
    "digraph imports {",
    '  rankdir="LR";',
    '  node [shape=box, fontsize=10, fontname="sans-serif"];',
  }

  local files = vim.tbl_keys(file_nodes)
  table.sort(files)
  for _, f in ipairs(files) do
    lines[#lines + 1] = ("  %s [style=filled, fillcolor=%s];"):format(
      dot_quote(f),
      dot_quote("#cfe8ff")
    )
  end

  local modules = vim.tbl_keys(module_nodes)
  table.sort(modules)
  for _, m in ipairs(modules) do
    if module_nodes[m] then
      lines[#lines + 1] = ('  %s [style="filled,dashed", fillcolor=%s];'):format(
        dot_quote(m),
        dot_quote("#eeeeee")
      )
    end
  end

  table.sort(edges, function(a, b)
    if a.from ~= b.from then
      return a.from < b.from
    end
    return a.to < b.to
  end)
  for _, edge in ipairs(edges) do
    lines[#lines + 1] = ("  %s -> %s;"):format(dot_quote(edge.from), dot_quote(edge.to))
  end

  lines[#lines + 1] = "}"
  return table.concat(lines, "\n")
end

---Whether a Graphviz layout engine is on PATH.
---@param layout string|nil defaults to "dot"
---@return boolean
function M.available(layout)
  return vim.fn.executable(layout or "dot") == 1
end

---Render `dot_source` to `out_png` via the Graphviz CLI.
---
---Asynchronous: the result arrives through `on_done`, never as a return value.
---Laying out a dependency graph is genuinely expensive -- `dot` is doing real
---work proportional to the node and edge count, and on a large project that is
---seconds. It used to run through `vim.system(...):wait()`, so the editor was
---frozen for all of it with nothing on screen.
---@param dot_source string
---@param out_png string
---@param layout string|nil defaults to "dot"
---@param on_done fun(out_png: string|nil, err: string|nil)
---@return nil
function M.render(dot_source, out_png, layout, on_done)
  layout = layout or "dot"
  if not M.available(layout) then
    return on_done(
      nil,
      ("Graphviz layout '%s' not found (`%s` not on PATH)"):format(layout, layout)
    )
  end

  local dir = vim.fn.fnamemodify(out_png, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    local ok, err = pcall(vim.fn.mkdir, dir, "p")
    if not ok then
      return on_done(nil, "cannot create output dir: " .. tostring(err))
    end
  end

  vim.system(
    { layout, "-Tpng", "-o", out_png },
    { stdin = dot_source, text = true },
    function(result)
      -- vim.system callbacks run off the main loop; the caller notifies and
      -- hands the PNG to images.nvim, which draws into the terminal.
      vim.schedule(function()
        if result.code ~= 0 then
          on_done(nil, "graphviz failed: " .. vim.trim(result.stderr or ""))
          return
        end
        if vim.fn.filereadable(out_png) == 0 then
          on_done(nil, "graphviz produced no output file")
          return
        end
        on_done(out_png, nil)
      end)
    end
  )
end

---Build, render and show the dependency graph for `data` (already scanned
---by `insights.imports`), scoped to `filters` exactly like the text report.
---@param data ImportData
---@param filters string[]|nil
---@return boolean ok
function M.show(data, filters)
  local cfg = (require("insights.config").get().imports or {}).graph or {}

  if not M.available(cfg.layout) then
    notify.error(
      ("Graphviz not found (`%s` not on PATH) — install it to use :Insights imports graph"):format(
        cfg.layout or "dot"
      )
    )
    return false
  end

  local entries = require("insights.imports").filtered_entries(data, filters or {})
  if #entries == 0 then
    notify.warn("no matching import/require calls to graph")
    return false
  end

  local dot_source = M.build_dot(entries, { include_external = cfg.include_external })

  local proj = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  local out_png = (cfg.outdir or vim.fn.stdpath("cache") .. "/insights/graph")
    .. "/"
    .. proj
    .. "-imports.png"

  -- M.render is asynchronous now, so everything downstream of the layout moved
  -- into its callback. `true` here means "layout started" -- failures are
  -- reported through notify, which is where every failure below already went.
  M.render(dot_source, out_png, cfg.layout, function(png, err)
    if not png then
      notify.error(err or "graph render failed")
      return
    end

    local ok_images, images = pcall(require, "images")
    if not (ok_images and images.show) then
      notify.info("graph written: " .. png .. " (install images.nvim to view it inline)")
      return
    end

    images.show(png)
  end)

  return true
end

return M
