-- This will run last in the setup process.

-- On Linux servers over SSH there is no system clipboard: copy via OSC52 (tmux and
-- Ghostty pass it on to macOS) and paste from nvim's own register (use Cmd-V for the
-- macOS clipboard), since OSC52 reads would need a permission prompt every time.
if vim.fn.has "mac" == 0 and not vim.env.DISPLAY and not vim.env.WAYLAND_DISPLAY then
  local osc52 = require "vim.ui.clipboard.osc52"
  local function paste() return { vim.fn.split(vim.fn.getreg "", "\n"), vim.fn.getregtype "" } end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy "+", ["*"] = osc52.copy "*" },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end
