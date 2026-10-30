-- 诊断列表（clangd / clang-tidy 的报错）。
-- <space>xx 看全部诊断，<space>xX 看当前文件 —— 和 LazyVim 的按键一致。
return {
  {
    "folke/trouble.nvim",
    cmd = { "Trouble" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      modes = {
        lsp = {
          win = { position = "right" },
        },
      },
    },
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "诊断列表（全部）" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "诊断列表（当前文件）" },
      { "<leader>cs", "<cmd>Trouble symbols toggle<cr>", desc = "符号列表" },
      { "<leader>cS", "<cmd>Trouble lsp toggle<cr>", desc = "LSP 引用 / 定义 / …" },
      { "<leader>xL", "<cmd>Trouble loclist toggle<cr>", desc = "位置列表" },
      { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix 列表" },
      {
        "[q",
        function()
          if require("trouble").is_open() then
            require("trouble").prev({ skip_groups = true, jump = true })
          else
            local ok, err = pcall(vim.cmd.cprev)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = "上一个诊断 / Quickfix",
      },
      {
        "]q",
        function()
          if require("trouble").is_open() then
            require("trouble").next({ skip_groups = true, jump = true })
          else
            local ok, err = pcall(vim.cmd.cnext)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = "下一个诊断 / Quickfix",
      },
    },
  },
}
