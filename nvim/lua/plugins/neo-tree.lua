-- Browsing up in the file tree (Backspace) should not change nvim's working directory:
-- one tmux session = one project, so lazygit (Space gg) and search (Space ff/fw) stay on
-- the project root no matter where the tree is.

---@type LazySpec
return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    filesystem = {
      bind_to_cwd = false,
    },
  },
}
