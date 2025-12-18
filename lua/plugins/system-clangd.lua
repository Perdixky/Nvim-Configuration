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

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts = opts or {}
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

      return opts
    end,
  },
}
