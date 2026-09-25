return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = { enabled = false },
        clice = {
          cmd = { "/usr/bin/clice", "serve" },
          mason = false,
        },
      },
    },
  },
}
