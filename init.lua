-- 洛谷（Luogu-On-Neovim）专用 Neovim —— 完全独立于 ~/.config/nvim（LazyVim）
--
-- 启动：终端执行 `luogu`（= NVIM_APPNAME=luogu nvim，见 bin/luogu）
--
-- 目录：
--   config      ~/.config/luogu                （就是本仓库，启动器会自动建软链）
--   插件/数据   ~/.local/share/luogu
--   解答文件    ~/.local/share/luogu/solutions （P1001.cpp …；.clangd / .clang-format 也在这层）
--   会话/缓存   ~/.local/state/luogu、~/.cache/luogu
--   登录信息    ~/.config/luogu-cli            （上游 LuoguCLI 硬编码在这里：cli.txt / uid.txt）
--
-- 和主配置、和 leetcode 那套都互不影响：三个 NVIM_APPNAME（nvim / luogu / leetcode）
-- 各有各的 config / data / state / cache。
--
-- 这里只装洛谷用得上的一套东西：启动快，C++ 开箱可用。

local opt = vim.opt

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

opt.number = true
opt.relativenumber = true
opt.mouse = "a"
opt.clipboard = "unnamedplus"
opt.termguicolors = true
opt.signcolumn = "yes"
opt.updatetime = 200
opt.timeoutlen = 300
opt.expandtab = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true
opt.splitright = true
opt.splitbelow = true
opt.undofile = true
opt.scrolloff = 4
opt.confirm = true
opt.wrap = false
opt.completeopt = "menu,menuone,noselect" -- blink.cmp 要求 noselect

-- OI 习惯：C / C++ 用 cindent（`}` 自动回到上一级、预处理行不会乱缩进）
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function(args)
    vim.bo[args.buf].cindent = true
    vim.bo[args.buf].smartindent = false
  end,
})

-- 让 :find / gf 也能在解答目录里找题
opt.path:append(require("lg").solutions)

-- 快捷键（洛谷相关在 <leader>l 分组，见 lua/plugins/luogu.lua）
vim.keymap.set({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "保存" })
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "清除搜索高亮" })
vim.keymap.set("n", "<leader>qq", "<cmd>qa<cr>", { desc = "退出" })

-- C++ 语法高亮：nvim 自带 c 但没有 cpp，parser 由 lua/cppts.lua 自己编（首次启动后台进行）
vim.api.nvim_create_autocmd("FileType", {
  pattern = "cpp",
  callback = function(args)
    require("cppts").start(args.buf)
  end,
})
require("cppts").ensure()

-- lazy.nvim 引导
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "无法克隆 lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\n按任意键退出...", "MoreMsg" },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { import = "plugins" },
  },
  install = { colorscheme = { "catppuccin", "habamax" } },
  checker = { enabled = false }, -- 专用环境，不需要自动查更新
  change_detection = { notify = false },
})
