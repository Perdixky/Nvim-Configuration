return {
  "xiyaowong/transparent.nvim",
  lazy = false,
  config = function()
    local transparent = require("transparent")
    transparent.setup({
      -- table: default groups
      groups = {
        "Normal",
        "NormalNC",
        "Comment",
        "Constant",
        "Special",
        "Identifier",
        "Statement",
        "PreProc",
        "Type",
        "Underlined",
        "Todo",
        "String",
        "Function",
        "Conditional",
        "Repeat",
        "Operator",
        "Structure",
        "LineNr",
        "NonText",
        "SignColumn",
        "CursorLine",
        "CursorLineNr",
        "StatusLine",
        "StatusLineNC",
        "EndOfBuffer",
      },
      -- table: additional groups that should be cleared
      extra_groups = {
        "NormalFloat", -- plugins which have float panel such as Lazy, Mason, LspInfo
      },
      -- table: groups you don't want to clear
      exclude_groups = {},
    })

    -- 使用 clear_prefix 清除所有 BufferLine 和 NeoTree 开头的高亮组
    transparent.clear_prefix("BufferLine")
    transparent.clear_prefix("NeoTree")
  end,
}
