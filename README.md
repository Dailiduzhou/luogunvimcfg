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
| 粘贴 Cookie（推荐） | `<leader>lc` → 浏览器 F12 → Network → 任意 luogu.com.cn 请求 → Request Headers 里的 `Cookie` **整条**粘进去 |
| 交互式 | `<leader>lL` 开一个终端，按提示先输 `_uid` 再输 `__client_id` |
| 手写文件 | `echo '<__client_id>' > ~/.config/luogu-cli/cli.txt`、`echo '<_uid>' > ~/.config/luogu-cli/uid.txt`（提交前会自动迁移进 jar） |

> 登录态存在 `~/.config/luogu-cli/cookies.txt`（curl 的 cookie jar，权限 600）。
> 换机器时把整个 `~/.config/luogu-cli/` 拷过去即可，不用重新登录。

### cookie 为什么以前“总是过期”

`__client_id` 是 **30 天滑动有效期**（洛谷每次响应都会下发
`set-cookie: __client_id=…; Max-Age=2592000`），正常用着会自动续期。以前老是“过期”，
其实是三件事叠在一起：

1. **根本没存回来的 cookie。** 上游 CLI 用 `--cookie "…"` 把值写死，只发不收；
   服务端给的续期永远拿不到，等于拿着一份冻结的快照。现在 curl 用 `-b jar -c jar`
   读写同一个 jar，续期会落盘。
2. **不是过期，是 CDN 挑战。** 提交接口不带 `C3VK`（那个亲和 cookie 只有 5 分钟）时，
   洛谷返回 **307** 让你带上它再来。上游 CLI 不存 cookie，所以**每次**都撞 307，
   而旧封装把输出里的 “307” 直接当成“cookie 失效”——于是看起来天天在过期。
   现在 302/307 会带上新 `C3VK` 自动重试一次，重试不过才报错。
3. 旧代码用 `[%w]+` 解析 `__client_id`，值里万一有 `-` `_` `=` 就会被截断成错的值，
   表现同样是“未登录”。现在整条 Cookie 拆成 key=value，原样保存。

真过期只剩两种：**在别的设备/浏览器重新登录**（旧 `__client_id` 被顶掉）、
**点过退出登录**，或者**超过 30 天没提交过**。这时候 `<leader>lc` 重粘一次就行。

## 快捷键

`<space>l` 是洛谷分组（全局映射，任何窗口里 which-key 都看得到）：

| 键 | 作用 |
| --- | --- |
| `<space>l` | 主菜单 |
| `<space>ln` | 新建题目（文件名 = 题号，自动套模板） |
| `<space>lf` | 打开已有题目 |
| `<space>lo` | 题面（浏览器） |
| `<space>lv` | 题解（浏览器） |
| `<space>li` | 输入数据（打开/新建 `P1001.in`，下面 `lr` 就喂它） |
| `<space>lr` | 本地编译 + 运行（有同名 `.in` 就从它读输入） |
| `<space>ls` | 提交 |
| `<space>lL` | 登录（终端输 uid / client_id） |
| `<space>lc` | 粘贴 Cookie 登录 |
| `<space>lb` | 重新编译 LuoguCLI |

LSP：`gd` 定义 · `gr` 引用 · `K` 悬停 · `<space>cr` 重命名 · `<space>ca` 代码操作 · `<space>cf` 手动格式化 ·
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
:Luogu input P1001     打开/新建输入文件 P1001.in
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
| `~/.config/luogu-cli` | 登录态：`cookies.txt`（cookie jar，就是它了）+ 兼容上游 CLI 的 `cli.txt` / `uid.txt` + `LuoguCLI` 软链 |

## 写了哪些东西（以及为什么）

上游 `Luogu-On-Neovim` 只有一个 1.8 KB 的 lua 文件，把 5 个动作拼成
`:!~/.config/luogu-cli/LuoguCLI …`；真正干活的是它自带的 C 小程序（现在只用来做交互式登录，
提交已经不走它了）。直接照搬会有几处坑，
这个仓库把它们都处理掉了：

| 上游的问题 | 本配置的做法 |
| --- | --- |
| `install()` 会 `rm -rf /tmp/Luogu-On-Neovim` 再重新 `git clone`，每次都要联网 | 直接从 lazy.nvim 已 clone 的插件目录 `cmake` 构建（版本由 `lazy-lock.json` 锁住） |
| GCC 14+ 默认 `-std=gnu23`，而它是 K&R 老写法（`extern int login();` 后面又定义带参数的 `login`），新编译器下**根本编不过** | 构建时强制 `-DCMAKE_C_FLAGS=-std=gnu17 -w` |
| 提交走 `:!` + shell，文件名带空格/特殊字符就废；输出一闪而过 | 用 `vim.system` 跑 curl（不经 shell），原始 HTTP 状态 + 响应留在 `luogu://submit` 窗口里，评测记录链接直接提示并写进 `+` 寄存器 |
| 提交只发 `--cookie "…"`、**不存回来的 cookie**，于是每次撞 CDN 的 307 挑战，表现成“cookie 总是过期” | curl 用 `-b jar -c jar` 读写同一个 cookie jar，302/307 带新 `C3VK` 自动重试一次；报错按 HTTP 状态 + `errorType` 分类，不再乱猜 |
| 提交 body 是手工拼的 JSON（把 `\n` `\t` `"` `\\` 逐个替换），代码里有反斜杠/中文就可能拼坏 | 用 `vim.json.encode` 生成 JSON，`--data-binary @临时文件` 发出去，不经过 shell 引号 |
| 提交完靠 CLI 内部 `xdg-open` 打开评测页，没装 xdg-open 就什么都不发生 | 自己解析响应里的 `rid`，给出 `https://www.luogu.com.cn/record/<rid>` |
| 运行超时时只杀掉 `sh`，真正的程序变孤儿继续吃 CPU；stdout/stderr 两路缓冲导致输出乱序 | 用 `exec` 让 pid 就是程序本身，超时直接杀掉；`2>&1` + `stdbuf -oL` 让顺序和终端一致 |
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
  所以有 `.in` 文件时用 `sh -c 'exec <exe> < <in> 2>&1'` 重定向。

## 本地运行 / 测试数据

`<space>lr` 用 `g++ -O2 -std=c++17 -Wall -Wextra` 编译，产物在
`~/.cache/luogu/build/<题号>`，然后输出到 `luogu://run` 窗口。

- 输入：源码旁边的同名 `.in` 文件，例如 `solutions/P1001.in`（用 `<space>li` 直接打开/新建）。
  没有就喂空输入 —— `scanf` 立刻拿到 EOF、变量是未初始化的垃圾值，所以**建议每题都先建 `.in`**
- 时限：默认 10 秒（`lua/lg.lua` 里的 `lg.run_timeout`，暴力对拍嫌短可以改大）
- 超时不会留垃圾进程：命令是 `exec` 出去的（pid 就是你的程序），超时 nvim 直接杀；
  旧版本 nvim 上还有一道 SIGKILL 兜底
- stdout / stderr 合并进同一条管道（`2>&1`），并用 `stdbuf -oL -eL` 按行刷新，
  所以程序里交替 `printf` / `fprintf(stderr, …)` 的顺序是**真的执行顺序**（和终端里一样）
- 结尾会自动标一行：`[超时…]` / `[段错误 SIGSEGV]` / `[abort SIGABRT]` / `[退出码 N]`，
  本地就能看出洛谷上会不会 RE
- 编译参数：`lua/lg.lua` 里的 `lg.compile`
- 编译失败 → 输出进 `luogu://compile`；有警告 → 弹一条提示

## clangd / 格式化

解答目录里的 `.clangd` 由 `lua/plugins/luogu.lua` 自动生成，删掉会自动重建：

- `Compiler: g++` + `--query-driver=**`：让 clangd 去问真 GCC 要系统头文件路径，
  否则 `#include <bits/stdc++.h>` 直接 file not found、`std::` 补全全空
- `-std=c++17`（洛谷默认 C++14，但 C++17 一般也能过；想保险就改成 `-std=c++14`）
- **不**定义 `LOCAL`：洛谷评测机自己会定义 `ONLINE_JUDGE=luogu`，本地编译也不定义，
  编辑器看到的和真正编掉的保持一致（不然 `#ifdef LOCAL` 在编辑器里是有效代码、g++ 却滤掉）
- `--header-insertion=never`：不让 clangd 往文件里补 `#include`

**保存时自动格式化**由 clangd 内置的 clang-format 做，风格读解答目录的 `.clang-format`
（LLVM + 4 空格 + 100 列，`IndentWidth` / `ColumnLimit` 可自己改）。
不想要就删掉 `lua/plugins/lsp.lua` 里那个 `BufWritePre` autocmd。

补全用 blink.cmp，只留 clangd 这一路 source，并按 kind 滤掉了宏 / 枚举 / namespace
这些在 `using namespace std` 场景下最刷屏的候选。

## 常见问题

**提交没反应 / 提示"还没登录"**
`~/.config/luogu-cli/cookies.txt` 里没有 `__client_id`。用 `<space>lc` 粘整条 Cookie（要整条，
不是只粘一项），或 `<space>lL` 交互式登录。

**以前提交老是说“cookie 过期”**
多半不是过期：不带 `C3VK` 亲和 cookie 时洛谷返回 307，上游 CLI 不存 cookie 所以每次都撞，
旧封装又把 307 当成了过期。现在会自动重试挑战、并把每次下发的 `__client_id` 写回 jar。
详见上面「cookie 为什么以前总是过期」。

**提交返回 403「用户尚未登录」**
这才是真失效：30 天没用过、在别处重新登录过、或者点过退出登录。`<space>lc` 重粘一次。
提交窗口（`luogu://submit`）里会留着原始 HTTP 状态和响应，别猜，看它。

**`LuoguCLI` 编不出来**
看 `:messages` 里的报错。`lua/lg.lua` 的 `build_cli()` 是手动可复现的：
`cmake -S <插件>/luogu-cli -B <cache>/luogu-cli-build -DCMAKE_C_FLAGS="-std=gnu17 -w" && cmake --build <cache>/luogu-cli-build`。
缺 `cmake` / `cc` 它会直接告诉你。编好后 `<space>lb` 重跑一次即可。

**没有 C++ 语法高亮**
`~/.local/share/luogu/site/parser/cpp.so` 不存在。首次启动时后台编，编完会提示；
失败了看 `:messages`（一般是没有 `cc` 或没网 clone tree-sitter-cpp）。

**提示"只能提交源码" / "只能编译运行源码"**
当前 buffer 不是 `.cpp` / `.c`（例如你正停在 `P1001.in` 窗口里）。切回源码窗口再按。

**没有 xdg-open，打不开题面**
提示里会给完整地址（同时写进 `+` 寄存器），自己粘到浏览器即可。

## 和别的配置比

| | 主配置 | 力扣 | 洛谷（本仓库） |
| --- | --- | --- | --- |
| 启动 | `nvim` | `leetcode` | `luogu` |
| `NVIM_APPNAME` | `nvim` | `leetcode` | `luogu` |
| 配置 | `~/.config/nvim` | `~/.config/leetcode` | `~/.config/luogu` |
| 数据 | `~/.local/share/nvim` | `~/.local/share/leetcode` | `~/.local/share/luogu` |
