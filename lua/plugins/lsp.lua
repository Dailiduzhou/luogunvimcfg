-- clangd（C/C++ 补全、诊断、格式化）+ blink.cmp（补全菜单）

--- 用 clangd 格式化（只有它参与）
---@param bufnr? integer
---@param async? boolean
local function format(bufnr, async)
  local attached = false
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if c.name == "clangd" then
      attached = true
    end
  end
  if not attached then
    return
  end
  vim.lsp.buf.format({
    bufnr = bufnr,
    async = async ~= false,
    timeout_ms = 3000,
    filter = function(client)
      return client.name == "clangd"
    end,
  })
end

return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      -- blink.cmp 只在 InsertEnter 时加载，这里 pcall 一下：没有也不至于起不来 clangd
      local ok_blink, blink = pcall(require, "blink.cmp")

      vim.lsp.config("clangd", {
        cmd = {
          "clangd",
          "--background-index",
          "--clang-tidy",
          -- never：不要往解答文件里补 #include。洛谷的模板本来就是 bits/stdc++.h + using namespace std
          "--header-insertion=never",
          -- 新版 clangd（>=18）这个参数必须带值，只写参数名会报 invalid value
          "--function-arg-placeholders=true",
          "--fallback-style=LLVM",
          -- clangd 18+ 只会在 --query-driver 白名单里的驱动器上查询系统头文件路径。
          -- 解答目录的 .clangd 里写的是 `Compiler: g++`，没有这一项时 clangd 不会去问 g++，
          -- 于是 #include <bits/stdc++.h> 直接 "file not found"、std:: 补全全空。
          "--query-driver=**",
        },
        root_markers = { ".clangd", "compile_commands.json", "compile_flags.txt" },
        capabilities = ok_blink and blink.get_lsp_capabilities() or nil,
      })
      vim.lsp.enable("clangd")

      vim.diagnostic.config({
        virtual_text = true,
        severity_sort = true,
        float = { border = "rounded" },
      })

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local map = function(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc })
          end

          map("n", "gd", vim.lsp.buf.definition, "跳转定义")
          map("n", "gr", vim.lsp.buf.references, "查找引用")
          map("n", "K", vim.lsp.buf.hover, "悬停文档")
          map("n", "<leader>cr", vim.lsp.buf.rename, "重命名")
          map("n", "<leader>ca", vim.lsp.buf.code_action, "代码操作")
          map("n", "<leader>cd", vim.diagnostic.open_float, "诊断详情")
          map({ "n", "v" }, "<leader>cf", function()
            format(ev.buf)
          end, "格式化（clangd / clang-format）")
          map("n", "]d", function()
            vim.diagnostic.jump({ count = 1 })
          end, "下一个诊断")
          map("n", "[d", function()
            vim.diagnostic.jump({ count = -1 })
          end, "上一个诊断")

          -- 保存时自动格式化（风格读解答目录的 .clang-format）。
          -- 不想要就删掉这个 autocmd。
          if vim.bo[ev.buf].filetype == "cpp" or vim.bo[ev.buf].filetype == "c" then
            vim.api.nvim_create_autocmd("BufWritePre", {
              buffer = ev.buf,
              group = vim.api.nvim_create_augroup("luogu_format_on_save", { clear = false }),
              desc = "保存时自动格式化",
              callback = function(args)
                format(args.buf, false)
              end,
            })
          end
        end,
      })
    end,
  },

  {
    "saghen/blink.cmp",
    version = "1.*",
    event = "InsertEnter",
    opts = {
      -- blink 的命令是**按顺序执行、第一个成功就停**。
      -- 写成 { "select_next", "snippet_forward", ... } 的话，菜单开着时 select_next 必定成功，
      -- snippet_forward 永远轮不到 —— 这就是 "Tab 跳不动占位符" 的原因。所以顺序反过来。
      keymap = {
        preset = "enter", -- <CR> 接受
        ["<Tab>"] = { "snippet_forward", "select_next", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "select_prev", "fallback" },
        ["<C-y>"] = { "select_and_accept", "fallback" },
      },
      appearance = { nerd_font_variant = "mono" },

      sources = {
        -- 只留 clangd：buffer/path 会把当前 buffer 里的任意单词和文件路径也当候选
        default = { "lsp" },
        -- 打字满 2 个字符才弹（输入 . / -> / :: 这类触发字符时不受此限制），
        -- 免得刚敲一个字母 i 就被 INT_MAX / isalnum 这种刷屏
        min_keyword_length = 2,

        providers = {
          lsp = {
            -- bits/stdc++.h + using namespace std 让候选池是整个 std + libstdc++，
            -- 按 kind 滤掉最没用的几类（保留 for/if 的 snippet、关键字、函数、类/结构体）
            transform_items = function(_, items)
              local drop = {
                [1] = true, -- Text        宏 / 常量（INT_MAX、INT16_MAX …）
                [8] = true, -- Interface   概念（ranges::forward_range …）
                [9] = true, -- Module      namespace（std、chrono …）
                [13] = true, -- Enum
                [20] = true, -- EnumMember  枚举成员
                [21] = true, -- Constant
              }
              return vim.tbl_filter(function(item)
                return not drop[item.kind]
              end, items)
            end,
          },
        },
      },

      completion = {
        trigger = {
          show_on_keyword = true, -- 打字就弹（for/if 的 snippet 靠它才出来）
          show_on_trigger_character = true, -- 输入 . -> :: 也弹
          show_in_snippet = true,
        },
        list = {
          selection = {
            preselect = true, -- 菜单弹出时高亮第一项，<CR> 直接接受
            auto_insert = false,
          },
        },
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        menu = { draw = { treesitter = { "lsp" } } },
      },
      signature = { enabled = true },
      -- 纯 Lua 模糊匹配，省掉下载/编译 Rust 二进制这一步
      fuzzy = { implementation = "lua" },
    },
  },
}
