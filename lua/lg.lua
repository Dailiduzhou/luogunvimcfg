-- 路径 / 小工具（luogu 插件配置、LSP 配置、:Luogu 命令都要用）
-- 对应力扣那套配置里的 lua/lc.lua。
local M = {}

--- 解答目录：所有题目的源码平铺在这里，文件名就是题号（P1001.cpp / B2001.cpp / CF1A.cpp）
--
-- 注意：Windows 上 vim.fn.stdpath() 返回反斜杠，而打开文件时用的路径可能正斜杠也可能反斜杠。
-- 统一用 vim.fs.normalize（Windows 下转正斜杠、展开 ~），否则前缀判断会漏，
-- 症状就是“明明在解答目录里，clangd 却不启动”。判断请用 lg.is_solution()。
M.solutions = vim.fs.normalize(vim.fn.stdpath("data") .. "/solutions")

--- 上游 LuoguCLI 把 cookie 和二进制都写死在 ~/.config/luogu-cli（见 luogu-cli/user.c、
--- luogu-cli/main.c），改不了，所以只能跟着它走：本配置把编出来的可执行文件软链到这里，
--- 登录写下的 cli.txt（__client_id）/ uid.txt（_uid）也在这里。
M.cli_dir = vim.fs.normalize(vim.fn.expand("~/.config/luogu-cli"))
M.cli = M.cli_dir .. "/LuoguCLI"

--- 编译 / 运行产物
M.build_dir = vim.fs.normalize(vim.fn.stdpath("cache") .. "/build")

--- 本地运行的时限（毫秒）：洛谷一般 1s，但暴力对拍经常要更久，这里放宽
M.run_timeout = 10000

--- 编译参数（想换 C++ 版本 / 关掉警告就改这里）
M.compile = { "g++", "-O2", "-std=c++17", "-Wall", "-Wextra" }

--- 新建题目用的模板
M.template = table.concat({
  "#include <bits/stdc++.h>",
  "using namespace std;",
  "",
  "int main() {",
  "    ",
  "    return 0;",
  "}",
}, "\n")

--- 这个路径是不是解答目录下的文件（两边都先 normalize，兼容正/反斜杠）
---@param path string
---@return boolean
function M.is_solution(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  return vim.startswith(vim.fs.normalize(path), M.solutions .. "/")
end

--- 文件不存在才写（已存在就不动，方便你自己改）
---@param path string
---@param content string
function M.ensure_file(path, content)
  if vim.uv.fs_stat(path) then
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(vim.split(content, "\n"), path)
end

--- 从文件名猜题号：P1001.cpp → P1001、cf1a.cpp → CF1A、AT_abc123_a.cpp → AT_abc123_a
--- 洛谷的题号前缀（P/B/T/U/CF/AT/SP/UVA …）统一转大写，因为题号在服务器上就是这么存的。
---@param bufnr? integer
---@return string?
function M.problem_id(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == "" then
    return nil
  end
  -- :t:r = 去掉目录和扩展名
  local base = vim.fn.fnamemodify(name, ":t:r")
  -- 至少含一个数字，这样 notes.cpp / random.cpp 这种不会被误当成题号
  local id = base:match("^([%a][%w_]*%d[%w_]*)$")
  if not id then
    return nil
  end
  -- AT 系题号（AT_abc123_a）后半截本来就是小写，只把前缀大写；
  -- 其余（p1001 / cf1a / uva100）整串大写，因为服务器上就是这么存的
  local upper = id:upper()
  if upper:match("^AT_") then
    return "AT_" .. id:sub(4)
  end
  return upper
end

--- 把上游那个 C 版 LuoguCLI 编出来，软链到 ~/.config/luogu-cli/LuoguCLI
---
--- 为什么要自己写一遍（而不是调插件自带的 install()）：
---   * 插件的 install() 会 rm -rf /tmp/Luogu-On-Neovim 再重新 git clone，每次都要联网；
---   * 这里直接从 lazy.nvim 已经 clone 好的插件目录编（版本由 lazy-lock.json 锁着）。
---
--- 另一个坑：GCC 14+ 默认 -std=gnu23，而上游代码是 K&R 风格的老写法
--- （user.h 里 `extern int login();` 后面又定义 `int login(char *, char *)`），
--- C23 里 `()` 表示“参数表未指定”会和带参数的函数定义冲突 → 直接编译失败。
--- 所以构建时强制回 -std=gnu17。
---@return boolean ok, string? msg
function M.build_cli()
  local src = vim.fs.normalize(vim.fn.stdpath("data") .. "/lazy/Luogu-On-Neovim/luogu-cli")
  if vim.fn.isdirectory(src) == 0 then
    return false, "找不到插件源码：" .. src .. "\n先让 lazy.nvim 把 Luogu-On-Neovim 装上（:Lazy sync）。"
  end
  for _, tool in ipairs({ "cmake", "cc" }) do
    if vim.fn.executable(tool) == 0 then
      return false, ("没装 %s，编不了上游的 C 版 LuoguCLI（登录/提交要用它）。"):format(tool)
    end
  end

  local out = vim.fs.normalize(vim.fn.stdpath("cache") .. "/luogu-cli-build")
  vim.fn.mkdir(out, "p")

  local function run(cmd)
    local res = vim.system(cmd, { text = true }):wait(300000)
    if res.code ~= 0 then
      error(("%s 失败（退出码 %d）\n%s%s"):format(
        table.concat(cmd, " "),
        res.code,
        res.stdout or "",
        res.stderr or ""
      ), 0)
    end
  end

  local ok, err = pcall(function()
    run({
      "cmake",
      "-S",
      src,
      "-B",
      out,
      "-DCMAKE_BUILD_TYPE=Release",
      -- 见函数注释：GCC 14+ 的默认 C23 会把这套老代码编挂
      "-DCMAKE_C_FLAGS=-std=gnu17 -w",
    })
    run({ "cmake", "--build", out, "-j" })
  end)
  if not ok then
    return false, tostring(err)
  end

  local bin = out .. "/LuoguCLI"
  if vim.uv.fs_stat(bin) == nil then
    return false, "构建结束了但没产出可执行文件：" .. bin
  end

  vim.fn.mkdir(M.cli_dir, "p")
  os.remove(M.cli)
  -- 软链而不是拷贝：:Lazy build 重新编完新二进制后这里自动跟上
  local linked = vim.uv.fs_symlink(bin, M.cli)
  if not linked then
    vim.uv.fs_copyfile(bin, M.cli)
  end
  vim.uv.fs_chmod(M.cli, tonumber("755", 8))

  -- 上游 main.c 用这个文件判断“装过了”
  local marker = io.open(M.cli_dir .. "/a.txt", "a")
  if marker then
    marker:close()
  end

  return true, M.cli
end

return M
