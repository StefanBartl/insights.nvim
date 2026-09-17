-- TESTS/imports_resolve_spec.lua — turning a module path back into a file,
-- without running `require`.
--
-- The ordering is the contract: a file in the project wins over anything on
-- the runtimepath. "Go to definition" from the imports report would otherwise
-- open the plugin-manager's copy of the module the reader is editing, which
-- looks right and silently is not.

return function(H)
  local resolve = require("insights.imports.resolve")

  local dir, cleanup = H.fixture("imports-resolve")

  ---@param rel string
  ---@param body string
  local function write(rel, body)
    local path = dir .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({ body }, path)
    return path
  end

  -- The four project-local candidate shapes ---------------------------------
  write("lua/proj/flat.lua", "return {}")
  write("lua/proj/pkg/init.lua", "return {}")
  write("bare/thing.lua", "return {}")
  write("bare/pkg/init.lua", "return {}")

  H.contains(
    vim.fs.normalize(resolve.module_path("proj.flat", dir) or ""),
    "lua/proj/flat.lua",
    "lua/<rel>.lua"
  )
  H.contains(
    vim.fs.normalize(resolve.module_path("proj.pkg", dir) or ""),
    "lua/proj/pkg/init.lua",
    "lua/<rel>/init.lua"
  )
  H.contains(
    vim.fs.normalize(resolve.module_path("bare.thing", dir) or ""),
    "bare/thing.lua",
    "<rel>.lua"
  )
  H.contains(
    vim.fs.normalize(resolve.module_path("bare.pkg", dir) or ""),
    "bare/pkg/init.lua",
    "<rel>/init.lua"
  )

  -- Order: `lua/<rel>.lua` is tried before `<rel>.lua` -----------------------
  write("lua/proj/both.lua", "return 'under lua'")
  write("proj/both.lua", "return 'at the root'")
  H.contains(
    vim.fs.normalize(resolve.module_path("proj.both", dir) or ""),
    "lua/proj/both.lua",
    "the lua/ candidate is tried first"
  )

  -- An absolute path comes back, whatever the cwd is ------------------------
  local abs = resolve.module_path("proj.flat", dir)
  H.ok(abs and (abs:match("^%a:") or abs:sub(1, 1) == "/"), "the answer is an absolute path")

  -- Nothing to resolve -------------------------------------------------------
  H.eq(
    resolve.module_path("definitely.not.a.module.anywhere.at.all", dir),
    nil,
    "an unresolvable module answers nil rather than guessing"
  )

  -- Beyond the project: the runtimepath ------------------------------------
  -- This repository is on the runtimepath while the suite runs, so its own
  -- modules resolve from a cwd that knows nothing about them -- which is the
  -- fallback chain (loader cache / package.path / nvim_get_runtime_file)
  -- doing its job.
  local empty, empty_cleanup = H.fixture("imports-resolve-empty")
  local runtime_hit = resolve.module_path("insights.imports.resolve", empty)
  H.ok(runtime_hit ~= nil, "a module on the runtimepath resolves from an unrelated cwd")
  H.contains(
    vim.fs.normalize(runtime_hit or ""),
    "insights/imports/resolve.lua",
    "to its own source file"
  )
  empty_cleanup()

  -- A project file shadows the runtimepath copy -----------------------------
  -- The same module name, resolved against a cwd that has one: the local file
  -- wins, which is the reason step 1 exists at all.
  write("lua/insights/imports/resolve.lua", "-- a decoy, not the real module")
  H.contains(
    vim.fs.normalize(resolve.module_path("insights.imports.resolve", dir) or ""),
    vim.fs.normalize(dir) .. "/lua/insights/imports/resolve.lua",
    "a project file shadows the runtimepath copy"
  )

  -- Default cwd --------------------------------------------------------------
  -- No cwd given means the editor's; the suite runs from the repository root,
  -- so this module resolves to the checkout being tested rather than to an
  -- installed copy.
  local default = resolve.module_path("insights.imports.resolve")
  H.ok(default ~= nil, "module_path defaults to the current working directory")
  H.contains(
    vim.fs.normalize(default or ""),
    vim.fs.normalize(vim.fn.getcwd()),
    "and resolves inside it"
  )

  cleanup()
end
