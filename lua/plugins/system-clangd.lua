local function is_windows()
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

local function mason_root()
  return (vim.fn.stdpath("data") .. "/mason"):gsub("\\", "/"):lower()
end

local function is_mason_path(path)
  local normalized = (path or ""):gsub("\\", "/"):lower()
  return vim.startswith(normalized, mason_root())
end

local function is_executable(path)
  return path and path ~= "" and vim.fn.executable(path) == 1
end

local function path_sep()
  return is_windows() and ";" or ":"
end

local function strip_trailing_slashes(path)
  return (path or ""):gsub("[/\\]+$", "")
end

local function sanitize_path_segment(segment)
  local s = vim.trim(segment or "")
  s = s:gsub('^"', ""):gsub('"$', "")
  return strip_trailing_slashes(s)
end

local function mason_bin()
  return mason_root() .. "/bin"
end

local function strip_mason_bin_from_path(original)
  local sep = path_sep()
  local parts = {}

  for segment in string.gmatch(original or "", "([^" .. sep .. "]+)") do
    local raw = sanitize_path_segment(segment)
    local normalized = raw:gsub("\\", "/"):lower()

    if normalized ~= "" and normalized ~= mason_bin() then
      parts[#parts + 1] = raw
    end
  end

  return table.concat(parts, sep)
end

local function find_system_clangd()
  local env = os.getenv("CLANGD_PATH")
  if is_executable(env) and not is_mason_path(env) then
    return env
  end

  if is_windows() then
    local program_files = os.getenv("ProgramFiles")
    local program_files_x86 = os.getenv("ProgramFiles(x86)")
    local candidates = {
      program_files and (program_files .. "\\LLVM\\bin\\clangd.exe") or nil,
      program_files_x86 and (program_files_x86 .. "\\LLVM\\bin\\clangd.exe") or nil,
      "C:\\LLVM\\bin\\clangd.exe",
    }

    for _, candidate in ipairs(candidates) do
      if is_executable(candidate) and not is_mason_path(candidate) then
        return candidate
      end
    end
  end

  local output
  if is_windows() then
    output = vim.fn.systemlist({ "where", "clangd" })
  else
    output = vim.fn.systemlist({ "which", "-a", "clangd" })
  end

  for _, line in ipairs(output) do
    local candidate = vim.trim(line)
    if candidate ~= "" and not candidate:match("^INFO:") and not is_mason_path(candidate) then
      return candidate
    end
  end
end

local function normalize_cmd(cmd)
  if type(cmd) == "string" then
    return { cmd }
  end
  if type(cmd) ~= "table" then
    return { "clangd" }
  end
  return vim.deepcopy(cmd)
end

local function build_clangd_cmd(base_cmd, root_dir)
  local cmd = normalize_cmd(base_cmd)
  local filtered = {}

  for _, arg in ipairs(cmd) do
    if type(arg) == "string" and not arg:match("^%-%-compile%-commands%-dir") then
      filtered[#filtered + 1] = arg
    end
  end

  if root_dir and root_dir ~= "" then
    filtered[#filtered + 1] = "--compile-commands-dir=" .. root_dir
  end

  return filtered
end

local last_clangd_root = nil

local function resolve_clangd_root(bufnr, markers)
  local root = vim.fs.root(bufnr, markers or {})
  if root and root ~= "" then
    last_clangd_root = root
    return root
  end

  local clients = vim.lsp.get_clients({ name = "clangd" })
  for _, client in ipairs(clients) do
    if client.root_dir and client.root_dir ~= "" then
      last_clangd_root = client.root_dir
      return client.root_dir
    end
  end

  return last_clangd_root
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local base_opts = {
        servers = {
          -- Ensure mason installs the server
          clangd = {
            keys = {
              { "<leader>ch", "<cmd>LspClangdSwitchSourceHeader<cr>", desc = "Switch Source/Header (C/C++)" },
            },
            root_markers = {
              "compile_commands.json",
              "compile_flags.txt",
              "configure.ac", -- AutoTools
              "Makefile",
              "configure.ac",
              "configure.in",
              "config.h.in",
              "meson.build",
              "meson_options.txt",
              "build.ninja",
              ".git",
            },
            capabilities = {
              offsetEncoding = { "utf-16" },
            },
            cmd = {
              "clangd",
              "--background-index",
              "--clang-tidy",
              "--header-insertion=iwyu",
              "--completion-style=detailed",
              "--fallback-style=llvm",
            },
            init_options = {
              usePlaceholders = true,
              completeUnimported = true,
              clangdFileStatus = true,
            },
          },
        },
        setup = {
          clangd = function(_, opts)
            local clangd_ext_opts = LazyVim.opts("clangd_extensions.nvim")
            require("clangd_extensions").setup(vim.tbl_deep_extend("force", clangd_ext_opts or {}, { server = opts }))
            return false
          end,
        },
      }

      opts = vim.tbl_deep_extend("force", base_opts, opts or {})

      local clangd_markers = opts.servers.clangd.root_markers
      opts.servers.clangd.root_dir = function(bufnr, on_dir)
        on_dir(resolve_clangd_root(bufnr, clangd_markers))
      end

      local system_clangd = find_system_clangd()

      opts.servers = opts.servers or {}
      opts.servers.clangd = opts.servers.clangd or {}

      -- Always disable mason for clangd.
      opts.servers.clangd.mason = false

      local cmd = opts.servers.clangd.cmd
      if type(cmd) == "string" then
        cmd = { cmd }
      end
      if type(cmd) ~= "table" then
        cmd = { "clangd" }
      end

      local requested_cmd = cmd[1] or "clangd"
      if type(requested_cmd) == "string" and is_mason_path(requested_cmd) then
        requested_cmd = "clangd"
      end

      cmd[1] = system_clangd or requested_cmd
      opts.servers.clangd.cmd = cmd

      -- If we can't locate a system clangd path, at least ensure we don't pick the one from mason/bin via PATH.
      opts.servers.clangd.cmd_env = opts.servers.clangd.cmd_env or {}
      if not system_clangd then
        opts.servers.clangd.cmd_env.PATH = strip_mason_bin_from_path(vim.env.PATH)
      else
        opts.servers.clangd.cmd_env.PATH = opts.servers.clangd.cmd_env.PATH or vim.env.PATH
      end

      opts.servers.clangd._base_cmd = vim.deepcopy(opts.servers.clangd.cmd)
      opts.servers.clangd.cmd = function(dispatchers, config)
        local base_cmd = config._base_cmd
        local resolved_cmd = build_clangd_cmd(base_cmd, config.root_dir)
        config.cmd = resolved_cmd
        return vim.lsp.rpc.start(resolved_cmd, dispatchers, {
          cwd = config.cmd_cwd,
          env = config.cmd_env,
          detached = config.detached,
        })
      end

      return opts
    end,
  },

  {
    "p00f/clangd_extensions.nvim",
    lazy = true,
    config = function() end,
    opts = {
      inlay_hints = {
        inline = false,
      },
      ast = {
        --These require codicons (https://github.com/microsoft/vscode-codicons)
        role_icons = {
          type = "",
          declaration = "",
          expression = "",
          specifier = "",
          statement = "",
          ["template argument"] = "",
        },
        kind_icons = {
          Compound = "",
          Recovery = "",
          TranslationUnit = "",
          PackExpansion = "",
          TemplateTypeParm = "",
          TemplateTemplateParm = "",
          TemplateParamObject = "",
        },
      },
    },
  },
}
