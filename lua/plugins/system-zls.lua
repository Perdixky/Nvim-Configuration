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
  local value = vim.trim(segment or "")
  value = value:gsub('^"', ""):gsub('"$', "")
  return strip_trailing_slashes(value)
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

local function find_system_zls()
  local env = os.getenv("ZLS_PATH")
  if is_executable(env) and not is_mason_path(env) then
    return env
  end

  if is_windows() then
    local program_files = os.getenv("ProgramFiles")
    local program_files_x86 = os.getenv("ProgramFiles(x86)")
    local local_app_data = os.getenv("LOCALAPPDATA")
    local candidates = {
      program_files and (program_files .. "\\zls\\zls.exe") or nil,
      program_files_x86 and (program_files_x86 .. "\\zls\\zls.exe") or nil,
      "C:\\zls\\zls.exe",
      local_app_data and (local_app_data .. "\\zls\\zls.exe") or nil,
    }

    for _, candidate in ipairs(candidates) do
      if is_executable(candidate) and not is_mason_path(candidate) then
        return candidate
      end
    end
  end

  local output
  if is_windows() then
    output = vim.fn.systemlist({ "where", "zls" })
  else
    output = vim.fn.systemlist({ "which", "-a", "zls" })
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
    return { "zls" }
  end
  return vim.deepcopy(cmd)
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local base_opts = {
        servers = {
          zls = {
            root_markers = {
              "zls.json",
              "build.zig",
              "build.zig.zon",
              ".git",
            },
            cmd = { "zls" },
          },
        },
      }

      opts = vim.tbl_deep_extend("force", base_opts, opts or {})
      opts.servers = opts.servers or {}
      opts.servers.zls = opts.servers.zls or {}

      local system_zls = find_system_zls()
      opts.servers.zls.mason = false

      local cmd = normalize_cmd(opts.servers.zls.cmd)
      local requested_cmd = cmd[1] or "zls"
      if type(requested_cmd) == "string" and is_mason_path(requested_cmd) then
        requested_cmd = "zls"
      end
      cmd[1] = system_zls or requested_cmd

      opts.servers.zls.cmd_env = opts.servers.zls.cmd_env or {}
      if not system_zls then
        opts.servers.zls.cmd_env.PATH = strip_mason_bin_from_path(vim.env.PATH)
      else
        opts.servers.zls.cmd_env.PATH = opts.servers.zls.cmd_env.PATH or vim.env.PATH
      end

      opts.servers.zls._base_cmd = vim.deepcopy(cmd)
      opts.servers.zls.cmd = function(dispatchers, config)
        local resolved_cmd = normalize_cmd(config._base_cmd)
        config.cmd = resolved_cmd
        return vim.lsp.rpc.start(resolved_cmd, dispatchers, {
          cwd = config.root_dir,
          env = config.cmd_env,
          detached = config.detached,
        })
      end

      return opts
    end,
  },
}
