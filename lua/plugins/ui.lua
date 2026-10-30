return {
  -- 主题，和主配置保持一致
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha",
        integrations = {
          treesitter = true,
          native_lsp = { enabled = true },
          which_key = true,
        },
      })
      vim.cmd.colorscheme("catppuccin")
    end,
  },

  -- 图标（补全菜单 / 状态栏用）
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- which-key：所有快捷键按 desc 分组弹出。
  -- Luogu-On-Neovim 的 setup() 里会 require("which-key")，所以它不能延迟到很晚才加载。
  {
    "folke/which-key.nvim",
    lazy = false,
    priority = 900,
    opts = {
      preset = "classic",
      delay = 200,
    },
    config = function(_, opts)
      require("which-key").setup(opts)
      require("which-key").add({
        { "<leader>l", group = "luogu" },
        { "<leader>s", group = "luogu（上游自带）" },
        { "<leader>c", group = "code" },
        { "<leader>x", group = "诊断 / 列表" },
        { "<leader>q", group = "quit" },
      })
    end,
  },

  -- 状态栏（模式、文件名、diagnostics、行列）
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        theme = "auto",
        section_separators = "",
        component_separators = "|",
        globalstatus = false,
      },
    },
  },
}
