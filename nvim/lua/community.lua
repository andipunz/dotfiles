-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.
--
-- Language packs only load when their toolchain is on PATH (Brewfile: go, node@24, uv),
-- so Mason never tries to install e.g. npm-based servers on a machine without node.

local function has(...)
  for _, cmd in ipairs { ... } do
    if vim.fn.executable(cmd) == 1 then return true end
  end
  return false
end

---@type LazySpec
local spec = {
  "AstroNvim/astrocommunity",
  { import = "astrocommunity.pack.lua" },
  { import = "astrocommunity.colorscheme.catppuccin" },
}

local function add(enabled, ...)
  if not enabled then return end
  for _, module in ipairs { ... } do
    table.insert(spec, { import = "astrocommunity." .. module })
  end
end

add(has "go", "pack.go")
add(has "node", "pack.typescript", "pack.vue", "pack.json", "pack.yaml", "pack.html-css", "pack.docker", "pack.bash")
add(has "uv" and has "python3", "pack.python.base", "pack.python.basedpyright", "pack.python.ruff")
add(has "cargo", "pack.rust")
-- macOS ships a /usr/bin/java stub that only prompts to install a JDK
add(has "java" and (vim.fn.has "mac" == 0 or vim.fn.system { "/usr/libexec/java_home" } and vim.v.shell_error == 0), "pack.java")

return spec
