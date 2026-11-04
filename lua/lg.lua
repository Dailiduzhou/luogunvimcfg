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

--- 洛谷站点 / 提交参数
M.site = "https://www.luogu.com.cn"
M.ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"

--- 洛谷的 C++ 语言 id（28 = C++14 / GCC）。想默认用 C++20 就改成 29
M.lang = 28

--- cookie jar（curl 的 Netscape 格式）
---
--- 为什么要有这个文件：洛谷每次响应都会重新下发
--- `set-cookie: __client_id=…; Max-Age=2592000`（30 天滑动续期）。
--- 只把 cookie 当固定字符串发（上游 CLI 的 `--cookie "…"` 就是这么干的）等于拿着一份
--- 冻结的快照，服务端给的续期永远拿不到 → 30 天一到就过期。让 curl 用 `-b jar -c jar`
--- 读同一个文件，续期才会落地。
M.jar = M.cli_dir .. "/cookies.txt"

--- 编译 / 运行产物
M.build_dir = vim.fs.normalize(vim.fn.stdpath("cache") .. "/build")

--- 本地运行的时限（毫秒）：洛谷一般 1s，但暴力对拍经常要更久，这里放宽
M.run_timeout = 10000

--- 本地编译 / clangd 用的 C++ 编译器
---
--- 为什么不能写死 g++：
---   Linux/WSL 上 g++ 就是 GCC，自带 libstdc++，`#include <bits/stdc++.h>` 找得到；
---   macOS 上 /usr/bin/g++ 其实是 Apple clang 的马甲，用的是 libc++ —— 那里**没有**
---   bits/stdc++.h，也没有 GNU 的 pb_ds，拿它编 OI 模板一上来就是 file not found。
---   所以 macOS 上要找 Homebrew 装的真 GCC（`brew install gcc` 装出来叫 g++-14 / g++-15）。
local function find_compiler()
  if jit.os == "OSX" then
    for _, cand in ipairs({ "g++-15", "g++-14", "g++-13", "g++-12" }) do
      if vim.fn.executable(cand) == 1 then
        return cand
      end
    end
  end
  return "g++"
end
M.compiler = find_compiler()

--- 编译参数（想换 C++ 版本 / 关掉警告就改这里）
M.compile = { M.compiler, "-O2", "-std=c++17", "-Wall", "-Wextra" }

--- 本地编译 / clangd 在 macOS 上额外要加的编译参数
---
--- Xcode 15/16 的 SDK 头文件里有 C11 的 `_Alignof`（被 <bits/stdc++.h> 一路带进来的
--- <mach/arm/_structs.h>），GCC 14 的 C++ 前端还不认它，症状是编什么都报
---   expected primary-expression before 'unsigned'
--- 换成 GCC 自己的同义写法就好（GCC 15 起原生支持，定义了也无害）。
---
--- 分成两份：`-Wa,…` 是给汇编器的，只给本地编译；clangd 不汇编，带了只会报
--- 一条 unused command-line argument 警告。
M.clangd_flags = {}
M.extra_flags = {}
if jit.os == "OSX" then
  M.clangd_flags = { "-D_Alignof=__alignof__" }
  M.extra_flags = {
    "-D_Alignof=__alignof__",
    -- 同一个 SDK 错配还会让汇编器（/usr/bin/as，其实是 clang）每编一次就警告：
    --   clang: warning: overriding deployment version from '16.0' to '26.0'
    -- 它只是噪音（GCC 默认按 macOS 16 编，as 却按当前 SDK 的版本），但会让每次
    -- <space>lr 都弹一条“编译通过，但有警告”。-Wa, 把选项透给汇编器。
    "-Wa,-Wno-overriding-deployment-version",
  }
  vim.list_extend(M.compile, M.extra_flags)
end

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

--- 读 cookie jar：name → value
---
--- 注意 `#HttpOnly_` 前缀：curl 存 HttpOnly cookie 时会把它加在域名前面，
--- 这一行**不是注释**，按 `#` 跳过就会漏掉 __client_id（正好是 HttpOnly 的那个）。
---@return table<string, string>
function M.jar_cookies()
  local out = {}
  local f = io.open(M.jar, "r")
  if not f then
    return out
  end
  for line in f:lines() do
    local l = line:gsub("^#HttpOnly_", "")
    if l ~= "" and l:sub(1, 1) ~= "#" then
      local fields = vim.split(l, "\t")
      if #fields >= 7 then
        out[fields[6]] = fields[7]
      end
    end
  end
  f:close()
  return out
end

--- 写入 / 更新 jar 里的若干 cookie（其余条目原样保留）
---@param cookies table<string, string>
function M.jar_set(cookies)
  vim.fn.mkdir(M.cli_dir, "p")
  local keep = {}
  local f = io.open(M.jar, "r")
  if f then
    for line in f:lines() do
      local l = line:gsub("^#HttpOnly_", "")
      local drop = false
      if l ~= "" and l:sub(1, 1) ~= "#" then
        local fields = vim.split(l, "\t")
        if #fields >= 7 and cookies[fields[6]] ~= nil then
          drop = true
        end
      end
      if not drop then
        keep[#keep + 1] = line
      end
    end
    f:close()
  end
  local expiry = os.time() + 30 * 24 * 3600
  for name, value in pairs(cookies) do
    keep[#keep + 1] = table.concat({ ".luogu.com.cn", "TRUE", "/", "TRUE", expiry, name, value }, "\t")
  end
  vim.fn.writefile(keep, M.jar)
  pcall(vim.uv.fs_chmod, M.jar, tonumber("600", 8)) -- 里面是登录态，别让别的用户读
end

--- 把上游 CLI 的 cli.txt / uid.txt 迁移进 jar（jar 里已经有 __client_id 就什么都不做）
---@return table<string, string>
function M.seed_jar()
  local jar = M.jar_cookies()
  if jar.__client_id then
    return jar
  end
  local function read(path)
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    local s = vim.trim(f:read("*a") or "")
    f:close()
    return s ~= "" and s or nil
  end
  local cookies = {}
  cookies.__client_id = read(M.cli_dir .. "/cli.txt")
  cookies._uid = read(M.cli_dir .. "/uid.txt")
  if not cookies.__client_id then
    return jar
  end
  if not cookies._uid then
    cookies._uid = nil
  end
  M.jar_set(cookies)
  return M.jar_cookies()
end

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
