-- Same theme as Ghostty and the work config: catppuccin follows the terminal
-- background (mocha when dark, latte when light).

---@type LazySpec
return {
  "AstroNvim/astroui",
  ---@type AstroUIOpts
  opts = {
    colorscheme = "catppuccin",
  },
}
