return {
  {
    "folke/tokyonight.nvim",
    opts = {
      -- Neovim detects the terminal background at startup.
      style = "moon",
      light_style = "day",
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    -- The generic colorscheme follows 'background'; do not pin a variant.
    opts = { colorscheme = "tokyonight" },
  },
}
