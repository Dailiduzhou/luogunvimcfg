# luogunvimcfg

洛谷（[Luogu-On-Neovim](https://github.com/Bot-wxt1221/Luogu-On-Neovim)）专用 Neovim 配置，
独立于主配置 `~/.config/nvim`（LazyVim），也独立于力扣那套 `leetcodenvimcfg`，三者互不影响。

- 命令名：`luogu`（等价于 `NVIM_APPNAME=luogu nvim`）
- 配置目录：`~/.config/luogu`（就是本仓库，启动器会自动建符号链接）
- 数据 / 缓存 / 状态：`~/.local/share/luogu`、`~/.cache/luogu`、`~/.local/state/luogu`
- 题目源码：`~/.local/share/luogu/solutions/P1001.cpp`

> 上游插件已归档（2025-03 起只读），作者自己也写明了 **不支持 Windows**。
> 本仓库在 Linux / macOS / WSL 上验证过；Windows 上请用 WSL。

## 安装

```sh
git clone <this-repo> ~/code/luogunvimcfg
echo 'export PATH="$HOME/code/luogunvimcfg/bin:$PATH"' >> ~/.bashrc   # 换成你的 shell 的 rc
exec $SHELL -l
luogu                                                                 # 首次启动会自动装插件
```

`bin/luogu` 会确保 `$XDG_CONFIG_HOME/luogu`（默认 `~/.config/luogu`）指向本仓库
（和 nvim 的 `stdpath("config")` 算法一致）；不想让它自动建就自己来：

```sh
ln -s ~/code/luogunvimcfg ~/.config/luogu
```

如果配置目录**已存在但不是本仓库**，启动器只警告、不覆盖 —— 免得悄悄用了别的配置
（那正是"改了这个仓库却没生效"的典型症状）。

依赖：`nvim`(>=0.10)、`git`、`curl`、`cc`、`g++`、`clangd`、`cmake`。

### 首次启动会做三件事

1. `lazy.nvim` 装插件（`~/.local/share/luogu/lazy/`，版本锁在 `lazy-lock.json`）
2. **编上游那个 C 版 CLI**：`cmake` 构建 `luogu-cli/`，产物软链到 `~/.config/luogu-cli/LuoguCLI`
3. **编 C++ 语法解析器**：`cc` 编 `tree-sitter-cpp` 成 `~/.local/share/luogu/site/parser/cpp.so`

2 和 3 都只做一次；之后的启动只是 `stat` 一下。

## 用起来

```sh
luogu               # 打开
luogu P1001.cpp     # 顺便打开某道题（文件在 ~/.local/share/luogu/solutions/）
```

第一次先登录（三个办法，任选）：

| 办法 | 操作 |
| --- | --- |
| 粘贴 Cookie（推荐） | `<leader>lc` → 把浏览器 F12 → Network → 任意 luogu.com.cn 请求 → Request Headers 里的 `Cookie` 整条粘进去 |
| 交互式 | `<leader>lL` 开一个终端，按提示先输 `_uid` 再输 `__client_id` |
| 手写文件 | `echo '<__client_id>' > ~/.config/luogu-cli/cli.txt`、`echo '<_uid>' > ~/.config/luogu-cli/uid.txt` |

> 只认得这两个 cookie：`__client_id`（登录态）和 `_uid`（用户 id）。
> 换机器时把 `~/.config/luogu-cli/` 拷过去即可，不用重新登录。

## 快捷键

`<space>l` 是洛谷分组（全局映射，任何窗口里 which-key 都看得到）：

| 键 | 作用 |
| --- | --- |
| `<space>l` | 主菜单 |
| `<space>ln` | 新建题目（文件名 = 题号，自动套模板） |
| `<space>lf` | 打开已有题目 |
| `<space>lo` | 题面（浏览器） |
| `<space>lv` | 题解（浏览器） |
| `<space>lr` | 本地编译 + 运行（有同名 `.in` 就从它读输入） |
| `<space>ls` | 提交 |
| `<space>lL` | 登录（终端输 uid / client_id） |
| `<space>lc` | 粘贴 Cookie 登录 |
| `<space>lb` | 重新编译 LuoguCLI |

LSP：`K` 悬停 · `<space>cr` 重命名 · `<space>ca` 代码操作 · `<space>cf` 手动格式化 ·
`<space>cd` 诊断浮窗 · `]d`/`[d` 上下一条诊断

诊断列表（Trouble）：`<space>xx` 全部 · `<space>xX` 当前文件 · `<space>xL` 位置列表 ·
`<space>xQ` Quickfix · `<space>cs` 符号

其它：`<C-s>` 保存 · `<Esc>` 清搜索高亮 · `<space>qq` 退出

上游插件自己的 `<space>s*` 映射（`so`/`ss`/`sp`/`sl`/`si`）也保留着，功能和上面一一对应
（它们是在 which-key 初始化之后才生效的，行为上就是 `:!LuoguCLI …` 的老写法）。
不想要就把 `lua/plugins/luogu.lua` 里 `require("Luogu-On-Neovim").setup()` 那行注释掉。

## `:Luogu` 子命令

```
:Luogu                 主菜单
:Luogu new P1001       新建题目（已存在就直接打开，不覆盖）
:Luogu files           从已有题目里选
:Luogu open P1001      浏览器打开题面
:Luogu solution P1001  浏览器打开题解
:Luogu run             本地编译运行
:Luogu submit          提交当前文件（题号取自文件名）
:Luogu login           交互式登录
:Luogu cookie <串>     粘贴 Cookie 登录
:Luogu build           重新编译 LuoguCLI
```

题号从文件名推：`P1001.cpp` → `P1001`、`cf1a.cpp` → `CF1A`、`AT_abc123_a.cpp` → `AT_abc123_a`。

## 目录

| 路径 | 说明 |
| --- | --- |
| `~/.config/luogu` | 本仓库（配置，就是这里） |
| `bin/luogu` | 启动器 |
| `~/.local/share/luogu` | 插件、语法解析器（`site/parser`） |
| `~/.local/share/luogu/solutions` | 题目源码 + 自动生成的 `.clangd` / `.clang-format` / `template.cpp` |
| `~/.local/share/luogu/site` | treesitter 的 `parser/` 与 `queries/`（nvim 的 rtp 只认这里的，别放 data 根目录） |
| `~/.cache/luogu/build` | `<space>lr` 编出来的可执行文件 |
| `~/.cache/luogu/luogu-cli-build` | 上游 C 版 CLI 的构建目录 |
| `~/.config/luogu-cli` | 上游 CLI 硬编码的登录信息（`cli.txt` / `uid.txt`）和 `LuoguCLI` 软链 |

## 写了哪些东西（以及为什么）

上游 `Luogu-On-Neovim` 只有一个 1.8 KB 的 lua 文件，把 5 个动作拼成
`:!~/.config/luogu-cli/LuoguCLI …`；真正干活的是它自带的 C 小程序。直接照搬会有几处坑，
这个仓库把它们都处理掉了：

| 上游的问题 | 本配置的做法 |
| --- | --- |
| `install()` 会 `rm -rf /tmp/Luogu-On-Neovim` 再重新 `git clone`，每次都要联网 | 直接从 lazy.nvim 已 clone 的插件目录 `cmake` 构建（版本由 `lazy-lock.json` 锁住） |
| GCC 14+ 默认 `-std=gnu23`，而它是 K&R 老写法（`extern int login();` 后面又定义带参数的 `login`），新编译器下**根本编不过** | 构建时强制 `-DCMAKE_C_FLAGS=-std=gnu17 -w` |
| 提交走 `:!` + shell，文件名带空格/特殊字符就废；输出一闪而过 | 用 `vim.system` 异步执行，原始响应留在 `luogu://submit` 窗口里，评测记录链接直接提示并写进 `+` 寄存器 |
| 提交完靠 CLI 内部 `xdg-open` 打开评测页，没装 xdg-open 就什么都不发生 | 自己解析响应里的 `rid`，给出 `https://www.luogu.com.cn/record/<rid>` |
| 只有 5 个映射，没有新建/运行/格式化/补全 | 加了 `<space>l*` 一整套、`:Luogu` 子命令、clangd + blink.cmp、保存自动格式化、诊断列表 |

另外两个本地环境相关的坑：

- **C++ 高亮**：Neovim 自带 `c` parser 但**没有 `cpp`**；`nvim-treesitter` 的 main 分支
  装 parser 要额外一个 `tree-sitter` CLI。这里干脆不装它，直接用 `cc` 把
  `tree-sitter-cpp` 的 `parser.c` + `scanner.c` 编成 `cpp.so` 放进 `site/parser/`，
  再把它的 `queries/*.scm`（高亮 / 缩进 / 折叠）拷到 `site/queries/cpp/`。
  注意必须放 `stdpath("data")/site` 而不是 `stdpath("data")` 根目录 ——
  后者不在 runtimepath 里，症状是 `Parser could not be created`。
- **本地运行喂输入**：`vim.system` 的 `stdin` 只支持 `string` / `string[]` / `true`，
  **不支持传文件描述符**（非法值会被静默忽略，症状是程序读不到输入、一直卡到超时），
  所以有 `.in` 文件时用 `sh -c '<exe> < <in>'` 重定向。

## 本地运行 / 测试数据

`<space>lr` 用 `g++ -O2 -std=c++17 -Wall -Wextra` 编译，产物在
`~/.cache/luogu/build/<题号>`，然后输出到 `luogu://run` 窗口。

- 输入：源码旁边的同名 `.in` 文件，例如 `solutions/P1001.in`；没有就喂空输入（`scanf` 立刻拿到 EOF）
- 时限：默认 10 秒（`lua/lg.lua` 里的 `lg.run_timeout`，暴力对拍嫌短可以改大）
- 编译参数：`lua/lg.lua` 里的 `lg.compile`
- 编译失败 → 输出进 `luogu://compile`；有警告 → 弹一条提示

## clangd / 格式化

解答目录里的 `.clangd` 由 `lua/plugins/luogu.lua` 自动生成，删掉会自动重建：

- `Compiler: g++` + `--query-driver=**`：让 clangd 去问真 GCC 要系统头文件路径，
  否则 `#include <bits/stdc++.h>` 直接 file not found、`std::` 补全全空
- `-std=c++17`（洛谷默认 C++14，但 C++17 一般也能过；想保险就改成 `-std=c++14`）
- `-DLOCAL`：方便写 `#ifdef LOCAL` 的调试代码
- `--header-insertion=never`：不让 clangd 往文件里补 `#include`

**保存时自动格式化**由 clangd 内置的 clang-format 做，风格读解答目录的 `.clang-format`
（LLVM + 4 空格 + 100 列，`IndentWidth` / `ColumnLimit` 可自己改）。
不想要就删掉 `lua/plugins/lsp.lua` 里那个 `BufWritePre` autocmd。

补全用 blink.cmp，只留 clangd 这一路 source，并按 kind 滤掉了宏 / 枚举 / namespace
这些在 `using namespace std` 场景下最刷屏的候选。

## 常见问题

**提交没反应 / 提示"还没登录"**
`~/.config/luogu-cli/cli.txt` 不存在或者是空的。用 `<space>lc` 粘 Cookie，或 `<space>lL` 交互式登录。

**提交返回 307 / 401**
cookie 过期了（洛谷的 `__client_id` 有有效期）。重新粘一次。

**`LuoguCLI` 编不出来**
看 `:messages` 里的报错。`lua/lg.lua` 的 `build_cli()` 是手动可复现的：
`cmake -S <插件>/luogu-cli -B <cache>/luogu-cli-build -DCMAKE_C_FLAGS="-std=gnu17 -w" && cmake --build <cache>/luogu-cli-build`。
缺 `cmake` / `cc` 它会直接告诉你。编好后 `<space>lb` 重跑一次即可。

**没有 C++ 语法高亮**
`~/.local/share/luogu/site/parser/cpp.so` 不存在。首次启动时后台编，编完会提示；
失败了看 `:messages`（一般是没有 `cc` 或没网 clone tree-sitter-cpp）。

**提交时提示"只能提交源码"**
当前 buffer 不是 `.cpp` / `.c`（例如你打开的是 `P1001.in`）。

**没有 xdg-open，打不开题面**
提示里会给完整地址（同时写进 `+` 寄存器），自己粘到浏览器即可。

## 和别的配置比

| | 主配置 | 力扣 | 洛谷（本仓库） |
| --- | --- | --- | --- |
| 启动 | `nvim` | `leetcode` | `luogu` |
| `NVIM_APPNAME` | `nvim` | `leetcode` | `luogu` |
| 配置 | `~/.config/nvim` | `~/.config/leetcode` | `~/.config/luogu` |
| 数据 | `~/.local/share/nvim` | `~/.local/share/leetcode` | `~/.local/share/luogu` |
