return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      local existing = opts.servers.qmlls or {}
      local base_cmd = existing.cmd or { "qmlls" }

      opts.servers.qmlls = vim.tbl_deep_extend("force", existing, {
        root_dir = function(bufnr, on_dir)
          local root = vim.fs.root(bufnr, { ".qmlls.ini", ".git" })
          if root then
            on_dir(root)
          end
        end,
        _base_cmd = base_cmd,
        cmd = function(dispatchers, config)
          local cmd = config._base_cmd or { "qmlls" }
          if type(cmd) == "string" then
            cmd = { cmd }
          end
          return vim.lsp.rpc.start(cmd, dispatchers, {
            cwd = config.root_dir, -- 关键：让 qmlls 在项目根启动，才能读到 .qmlls.ini
            env = config.cmd_env,
            detached = config.detached,
          })
        end,
      })

      return opts
    end,
  },
}
