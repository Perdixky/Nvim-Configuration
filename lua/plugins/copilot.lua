return {
  "zbirenbaum/copilot.lua",
  config = function()
    require("copilot").setup({
      copilot_model = "gpt-41-copilot",
    })
  end,
}
