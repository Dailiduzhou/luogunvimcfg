-- 洛谷本体：Bot-wxt1221/Luogu-On-Neovim + 快捷键 + 自动生成的本地分析配置
--
-- 注意：这个插件上游已经归档（2025-03 起只读），而且作者自己写明不支持 Windows。
-- 它的“功能”其实就是一个 C 写的小命令行（luogu-cli/），lua 那层只是把 5 个命令
-- 拼成 `:!~/.config/luogu-cli/LuoguCLI …`。所以这里做了三件事：
--   1. 用它自己的 setup()（上游的 <leader>s* 映射照旧可用）
--   2. 自己再写一套 <leader>l* 的封装（lua/luogu.lua）：不经过 shell、异步、
--      把评测记录链接直接提示出来
--   3. 把它的构建换成从 lazy.nvim 的插件目录直接 cmake（不再 rm -rf /tmp 重新 clone）
local lg = require("lg")
local luogu = require("luogu")

local CLI = lg.cli
local SOLUTIONS = lg.solutions

-- ─────────────────────────────────────────────────────────────────────────────
-- 生成的文件（都在解答目录里，只在不存在时写，删掉会自动重建）
-- ─────────────────────────────────────────────────────────────────────────────

-- clangd 配置：洛谷的解答是单文件、没有 compile_commands.json，
-- 关键的是 `Compiler:`——clangd 会用这个驱动去问系统头文件路径，
-- 否则 `#include <bits/stdc++.h>`、libstdc++ 的头文件会全部报红。
--
-- 编译器不能写死 g++：macOS 上 /usr/bin/g++ 是 Apple clang（libc++，没有
-- bits/stdc++.h），必须用 Homebrew 的真 GCC，见 lua/lg.lua 的 find_compiler。
local clangd_add = {
  "    # 洛谷默认提交 C++14，但 C++17 也能过；想更保险就改成 -std=c++14",
  "    - -std=c++17",
}
if #lg.clangd_flags > 0 then
  clangd_add[#clangd_add + 1] = "    # 见 lua/lg.lua 的 M.clangd_flags：macOS 上 SDK 错配要补的参数"
  for _, flag in ipairs(lg.clangd_flags) do
    clangd_add[#clangd_add + 1] = "    - " .. flag
  end
end
vim.list_extend(clangd_add, {
  "    # 注意：这里**不**定义 LOCAL。洛谷评测机自己会定义 ONLINE_JUDGE=luogu，",
  "    # 本地编译（lg.compile）也不定义 LOCAL —— 编辑器看到的和真正编译的保持一致，",
  "    # 不然 #ifdef LOCAL 的代码在编辑器里是“有效代码”、g++ 却把它滤掉。",
  "    # 本地调试时 main 用不到参数/变量，这类警告是噪音",
  "    - -Wno-unused-parameter",
  "    - -Wno-unused-variable",
  "    - -Wno-sign-compare",
})

local CLANGD_CONFIG = string.format([[
# 由 ~/.config/luogu/lua/plugins/luogu.lua 生成
# 文件被删掉的话，下次启动会自动重建；你手动改过的内容不会被覆盖
CompileFlags:
  Compiler: %s
  Add:
%s
Completion:
  ArgumentLists: FullPlaceholders
Index:
  # 一堆互不相干的单文件，没必要后台建索引
  Background: Skip
]], lg.compiler, table.concat(clangd_add, "\n"))

-- clang-format 风格：clangd 内置的格式化器（保存时格式化用的就是它）会读这个文件
local CLANG_FORMAT = [[
# 由 ~/.config/luogu/lua/plugins/luogu.lua 生成
# 文件被删掉的话，下次启动会自动重建；你手动改过的内容不会被覆盖
BasedOnStyle: LLVM

# OI 常见写法：4 空格缩进、行宽放宽
IndentWidth: 4
ColumnLimit: 100
]]

--- <leader>l 分组（全局映射，面板/输出窗口里也能用；which-key 里能看到分组名）
local function setup_keymaps()
  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
  end

  map("<leader>l", luogu.menu, "洛谷主菜单")
  map("<leader>ln", luogu.new, "新建题目")
  map("<leader>lf", luogu.files, "打开已有题目")
  map("<leader>lo", luogu.open, "题面（浏览器）")
  map("<leader>lv", luogu.solution, "题解（浏览器）")
  map("<leader>li", luogu.input, "输入数据（P1001.in）")
  map("<leader>lr", luogu.run, "本地编译运行")
  map("<leader>ls", luogu.submit, "提交")
  map("<leader>lL", luogu.login, "登录（终端输入 uid / client_id）")
  map("<leader>lc", luogu.cookie, "粘贴 Cookie 登录")
  map("<leader>lb", luogu.build, "重新编译 LuoguCLI")
end

return {
  "Bot-wxt1221/Luogu-On-Neovim",

  -- 插件本身很轻（就一个 lua 文件），而且要在启动时就注册好按键；
  -- 真正干活的 C 版 LuoguCLI 是按需编、按需调的。
  lazy = false,

  dependencies = { "folke/which-key.nvim" }, -- 它的 setup() 里 require("which-key")

  -- 编 C 版 LuoguCLI（详见 lua/lg.lua 的 build_cli：为什么要 -std=gnu17、为什么不用插件的 install()）
  build = function()
    local ok, msg = lg.build_cli()
    if not ok then
      vim.notify("LuoguCLI 编译失败（登录/提交会不可用）：\n" .. tostring(msg), vim.log.levels.ERROR, {
        title = "luogu",
      })
    end
  end,

  -- 放 init 而不是 config：即使插件因为某些原因没加载，:Luogu 和快捷键也是好的
  init = function()
    setup_keymaps()
    luogu.setup_command()
  end,

  config = function()
    -- 上游自己的映射（<leader>so/ss/sp/sl/si）。想只用本配置的那套，
    -- 把下面这行注释掉即可（功能一一对应，见 README）。
    require("Luogu-On-Neovim").setup()

    -- 本地分析配置 + 新建题目的模板
    local clangd_file = SOLUTIONS .. "/.clangd"
    lg.ensure_file(clangd_file, CLANGD_CONFIG)
    -- 两处老版本的痕迹，只动这两行，其它手改过的内容不动：
    --   * `- -DLOCAL`：和本地编译参数不一致，会让 #ifdef LOCAL 的两边看到不一样的东西
    --   * `Compiler: g++`：macOS 上那是 Apple clang（libc++，没有 bits/stdc++.h）
    local lines = vim.fn.readfile(clangd_file)
    local changed = false
    local kept = {}
    for _, line in ipairs(lines) do
      if line:match("^%s*%-%s+%-DLOCAL%s*$") then
        changed = true
      else
        local compiler = line:match("^%s*Compiler:%s*(%S+)%s*$")
        -- 只在 macOS 上把当年写死的 g++ 换成真正找到的 GCC；用户自己改过的其它值不动
        if compiler == "g++" and lg.compiler ~= "g++" then
          line = "  Compiler: " .. lg.compiler
          changed = true
        end
        kept[#kept + 1] = line
      end
    end
    if changed then
      vim.fn.writefile(kept, clangd_file)
    end
    lg.ensure_file(SOLUTIONS .. "/.clang-format", CLANG_FORMAT)
    lg.ensure_file(SOLUTIONS .. "/template.cpp", lg.template)

    -- macOS 上没有真正的 GCC 时，bits/stdc++.h 必然找不到，早点说清楚
    if jit.os == "OSX" and lg.compiler == "g++" then
      vim.schedule(function()
        vim.notify(
          "macOS 上没找到真正的 GCC（g++-14 / g++-15 …）。\n"
            .. "本机会退回 Apple clang 的 libc++，而它没有 bits/stdc++.h：\n"
            .. "C++ 文件会满屏报错、<space>lr 也编不过。\n修复：brew install gcc 后重开。",
          vim.log.levels.WARN,
          { title = "luogu" }
        )
      end)
    end

    -- 二进制不在（首次启动 / 手动删了 / cmake 装晚了）就补一次
    if vim.fn.executable(CLI) == 0 then
      vim.schedule(function()
        local ok, msg = lg.build_cli()
        if not ok then
          vim.notify("LuoguCLI 没编出来，登录/提交不可用：\n" .. tostring(msg), vim.log.levels.ERROR, {
            title = "luogu",
          })
        end
      end)
    end
  end,
}
