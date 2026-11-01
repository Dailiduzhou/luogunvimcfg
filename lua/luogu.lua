-- :Luogu 命令 + 对上游 C 版 LuoguCLI 的封装
--
-- 上游插件（lua/Luogu-On-Neovim.lua）的实现是：
--   vim.api.nvim_command("!~/.config/luogu-cli/LuoguCLI submit "..input.." %")
-- 有几个问题：`:!` 走 shell，文件名里带空格/特殊字符就废；输出被塞进 :messages 一闪而过；
-- 提交完只靠 CLI 内部 xdg-open 打开评测页（没装 xdg-open 就什么也不发生）。
-- 这里用 vim.system 重写一遍：异步、不经过 shell、把原始响应留在窗口里，并把评测记录
-- 链接直接提示（同时写进 + 寄存器）。
local lg = require("lg")

local M = {}

local notify = function(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "luogu" })
end

--- 输出窗口（编译错误、提交响应都往这里放）
---@param title string
---@param lines string[]
function M.show(title, lines)
  -- 同名 buffer 已经开了就复用，避免每次提交都多一个
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == title then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_set_name, buf, title)

  vim.cmd("botright 12split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.wrap = true -- 长输出不折行的话会被截在窗口右边看不到
  vim.bo[buf].modifiable = false
end

--- CLI 可执行文件；没有就现编一次（第一次用、或者 :Lazy update 之后都可能是这种状态）
---@return string?
function M.cli()
  if vim.fn.executable(lg.cli) == 1 then
    return lg.cli
  end
  notify("正在编译 LuoguCLI（只需一次）…")
  local ok, msg = lg.build_cli()
  if not ok then
    notify("LuoguCLI 没编出来，登录/提交不可用：\n" .. tostring(msg), vim.log.levels.ERROR)
    return nil
  end
  return lg.cli
end

--- 当前文件是不是能编译/提交的源码（.cpp / .c …，大小写不敏感：.CPP 也认）
---@param file string
---@return boolean
local function is_source(file)
  local ext = vim.fn.fnamemodify(file, ":e"):lower()
  return vim.tbl_contains({ "c", "cc", "cpp", "cxx", "c++" }, ext)
end

--- 当前 buffer 要操作的源码
---
--- 本身就是 .cpp/.c 就用它；停在同一道题的 .in/.out/.ans 上也认（`<space>li` 开输入文件、
--- 改完测试数据顺手 `<space>lr` / `<space>ls` 是最自然的动作，不该只给一句“只能运行源码”）。
---@return string? file 源码路径
---@return string? from 如果是从 .in 转过来的，返回当前文件名（用于提示）
local function source_file()
  local cur = vim.api.nvim_buf_get_name(0)
  if cur == "" or not lg.is_solution(cur) then
    return nil
  end
  if is_source(cur) then
    return cur
  end
  local ext = vim.fn.fnamemodify(cur, ":e"):lower()
  if not vim.tbl_contains({ "in", "out", "ans" }, ext) then
    return nil
  end
  local stem = vim.fn.fnamemodify(cur, ":r")
  for _, candidate_ext in ipairs({ "cpp", "cc", "cxx", "c", "c++" }) do
    local candidate = stem .. "." .. candidate_ext
    if vim.fn.filereadable(candidate) == 1 then
      return candidate, vim.fn.fnamemodify(cur, ":t")
    end
  end
  return nil
end

--- 写盘：当前是 .in 时，同题源码 buffer 若开着且有改动，一起写掉（不然编的是磁盘上的旧版本）
---@param file string
local function write_source(file)
  vim.cmd.write()
  local buf = vim.fn.bufnr(file)
  if buf ~= -1 and vim.bo[buf].modified then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd.write()
    end)
  end
end

--- 有没有登录过（cookie 以 jar 为准，jar 里没东西时会从上游 CLI 的 cli.txt 迁移过来）
---@return boolean
function M.logged_in()
  return lg.seed_jar().__client_id ~= nil
end

--- 题号：命令行给了就用命令行的，否则从当前文件名猜
---@param code? string
---@return string?
local function resolve_code(code)
  if type(code) == "string" and code ~= "" then
    return (code:gsub("^(%a+)", function(s)
      return s:upper()
    end))
  end
  return lg.problem_id(0)
end

--- 用浏览器打开链接；没有 xdg-open / 没配 opener 时退回把地址打出来
---@param url string
local function open_url(url)
  local ok, res = pcall(vim.ui.open, url)
  if not ok or res == nil then
    notify("打不开浏览器（没装 xdg-open？），地址是：\n" .. url, vim.log.levels.WARN)
    pcall(vim.fn.setreg, "+", url)
  end
end

--- 新建一道题：solutions/P1001.cpp（已存在就直接打开，不覆盖）
---@param code? string
function M.new(code)
  if not code or code == "" then
    code = vim.fn.input("题号（例如 P1001 / CF1A / AT_abc123_a）: ")
  end
  if code == "" then
    return
  end
  code = resolve_code(code)
  local file = lg.solutions .. "/" .. code .. ".cpp"
  vim.fn.mkdir(lg.solutions, "p")
  lg.ensure_file(file, lg.template)
  vim.cmd.edit(vim.fn.fnameescape(file))
end

--- 打开题库里已有的题目（不额外装 telescope，用内置 vim.ui.select）
function M.files()
  local files = vim.fn.globpath(lg.solutions, "*.cpp", false, true)
  if #files == 0 then
    notify("解答目录还是空的：" .. lg.solutions .. "\n先 :Luogu new P1001")
    return
  end
  table.sort(files)
  vim.ui.select(files, {
    prompt = "打开题目",
    format_item = function(f)
      return vim.fn.fnamemodify(f, ":t")
    end,
  }, function(choice)
    if choice then
      vim.cmd.edit(vim.fn.fnameescape(choice))
    end
  end)
end

--- 浏览器打开题面
---@param code? string
function M.open(code)
  code = resolve_code(code)
  if not code then
    notify("这个文件名里没有题号。把文件命名成 P1001.cpp，或者 :Luogu open P1001", vim.log.levels.WARN)
    return
  end
  open_url("https://www.luogu.com.cn/problem/" .. code)
end

--- 浏览器打开题解
---@param code? string
function M.solution(code)
  code = resolve_code(code)
  if not code then
    notify("这个文件名里没有题号。把文件命名成 P1001.cpp，或者 :Luogu solution P1001", vim.log.levels.WARN)
    return
  end
  open_url("https://www.luogu.com.cn/problem/solution/" .. code)
end

--- 打开（没有就新建）这道题的输入文件 P1001.in，方便 <space>lr 前喂测试数据
---@param code? string
function M.input(code)
  code = resolve_code(code)
  if not code then
    notify("这个文件名里没有题号。把文件命名成 P1001.cpp，或者 :Luogu input P1001", vim.log.levels.WARN)
    return
  end
  local infile = lg.solutions .. "/" .. code .. ".in"
  vim.fn.mkdir(lg.solutions, "p")
  lg.ensure_file(infile, "")
  vim.cmd("split " .. vim.fn.fnameescape(infile))
end

--- 运行结果的尾巴：区分“正常退出”“被信号干掉”“超时”（定义在 M.run 之前才能当局部函数引用）
---
--- 两个容易踩的地方：
---   * 被信号杀死时 nvim 给的是 **code=0 + signal=N**（不是 code≠0），所以要先看 signal；
---   * 超时是 **code=124**（nvim 强制终止后设的哨兵值，见 :h SystemObj:wait），不是 signal。
---@param run vim.SystemCompleted
---@return string?
local run_tail

--- 本地编译 + 运行（有同名 .in 文件就从它读输入）
function M.run()
  local file, from = source_file()
  if not file then
    local cur = vim.api.nvim_buf_get_name(0)
    if cur == "" or not lg.is_solution(cur) then
      notify("先打开解答目录里的题目文件（:Luogu new P1001 / :Luogu files）", vim.log.levels.WARN)
    else
      notify(
        ("当前是 .%s 文件，旁边没找到同题的源码（P1001.cpp 那种）"):format(
          vim.fn.fnamemodify(cur, ":e")
        ),
        vim.log.levels.WARN
      )
    end
    return
  end
  if from then
    notify(("当前是 %s，编译运行同题的 %s"):format(from, vim.fn.fnamemodify(file, ":t")))
  end
  write_source(file)

  vim.fn.mkdir(lg.build_dir, "p")
  local base = vim.fn.fnamemodify(file, ":t:r")
  local exe = lg.build_dir .. "/" .. base
  local infile = vim.fn.fnamemodify(file, ":r") .. ".in"

  local cmd = vim.deepcopy(lg.compile)
  vim.list_extend(cmd, { "-o", exe, file })

  vim.system(cmd, { text = true }, function(build)
    -- vim.system 的回调是 fast event 上下文，里面不能调 vim.fn.*（会报 E5560），
    -- 所以下面整段都塞进 vim.schedule。
    vim.schedule(function()
      local build_out = vim.trim((build.stdout or "") .. (build.stderr or ""))
      if build.code ~= 0 then
        M.show("luogu://compile", vim.split(build_out, "\n"))
        notify("编译失败", vim.log.levels.ERROR)
        return
      end

      -- 运行：一律走 `sh -c`，但注意两个细节
      --
      -- 1) 用 `exec`：让 sh **把自己替换成**程序，这样 nvim 手里的 pid 就是程序本身。
      --    不 exec 的话 sh 是父进程，超时只杀掉 sh，程序变孤儿接着吃 CPU（还杀不掉，
      --    风扇狂转、下次编译还可能撞上正在运行的二进制）。
      -- 2) `2>&1`：stdout 和 stderr 合并进**同一条**管道。分开收再拼的话，
      --    两路各自缓冲、顺序就乱（程序里交替 printf/fprintf 时最明显）。
      --
      -- 另外 vim.system 的 stdin 只支持 string / string[] / true，**不支持文件描述符**
      -- （nvim 0.12 把非法值直接忽略，症状就是程序读不到输入、一直卡到超时），
      -- 所以有 .in 文件时还是用 shell 重定向：大文件不用整个读进内存。
      local has_in = vim.fn.filereadable(infile) == 1

      -- stdbuf -oL -eL：让 stdout 也按行刷新，和终端里看到的行为一致。
      -- 不加的话，stdout 接管道时是**全缓冲**，程序里交替 printf/fprintf 的输出
      -- 会变成“先所有 stderr、再所有 stdout”——看起来就像顺序乱了（其实不是 2>&1 的锅）。
      -- 静态链接时 stdbuf 不生效但也不会出错；系统没有 stdbuf（比如 macOS）就跳过。
      local runner = vim.fn.executable("stdbuf") == 1 and "stdbuf -oL -eL " or ""
      local inner = "exec " .. runner .. vim.fn.shellescape(exe)
      if has_in then
        inner = inner .. " < " .. vim.fn.shellescape(infile)
      end
      inner = inner .. " 2>&1"

      local opts = { text = true, timeout = lg.run_timeout }
      if not has_in then
        opts.stdin = "" -- 没有 .in：立刻 EOF，scanf 不会挂着等输入
      end

      local proc
      proc = vim.system({ "sh", "-c", inner }, opts, function(run)
        vim.schedule(function()
          local lines = vim.split(run.stdout or "", "\n")
          -- 最后一行通常是空字符串，先拿掉，尾巴提示才能写在正确位置
          if lines[#lines] == "" then
            lines[#lines] = nil
          end
          local tail = run_tail(run)
          if tail then
            lines[#lines + 1] = tail
          end
          M.show("luogu://run", lines)
        end)
      end)

      -- 兜底：nvim 0.12 超时是直接 SIGKILL（:h SystemObj:wait），已经不会留孤儿；
      -- 但旧版本（<0.11）超时只发 SIGTERM，程序屏蔽了 SIGTERM 就永远不退出、回调也
      -- 永远不回来。这里 300ms 后补一刀，对已经退出的进程是无害的。
      vim.defer_fn(function()
        pcall(function()
          proc:kill("sigkill")
        end)
      end, lg.run_timeout + 300)

      if build_out ~= "" then
        notify("编译通过，但有警告：\n" .. build_out:sub(1, 400), vim.log.levels.WARN)
      end
    end)
  end)
end

run_tail = function(run)
  -- 超时：nvim 强制终止后把 code 设成 124
  if run.code == 124 then
    return ("[超时：%.1f 秒后被杀]"):format(lg.run_timeout / 1000)
  end
  -- 被信号杀死：code 是 0，真正的信息在 signal 里（signal=11 就是洛谷上的 RE）
  local sig = run.signal
  if sig ~= nil and sig ~= 0 then
    local named = { [11] = "段错误 SIGSEGV", [6] = "abort SIGABRT", [8] = "浮点错误 SIGFPE" }
    return ("[%s]"):format(named[sig] or ("被信号 %d 杀死"):format(sig))
  end
  if run.code ~= nil and run.code ~= 0 then
    return ("[退出码 %d]"):format(run.code)
  end
  return nil
end

--- 跑一次 curl：cookie 读写都走同一个 jar（见 lg.jar 的注释）
---
--- **不用 -L**。洛谷的 302/307 是 CDN 亲和 cookie（C3VK）的挑战，正常的响应链是
--- 302 → 200 一跸完事；但 cookie 不被接受时它会**一直 302 回同一页**，-L 会一路跟到
--- `curl: (47) Maximum redirects followed`。所以这里只发一跸，重试交给 get/post。
---@param args string[]
---@param cb fun(r: {status: integer, body: string, err: string?})
---@param out? string 把响应体存到这个文件（图片这种二进制用），不再读成文本
local function curl(args, cb, out)
  local body_file = out or vim.fn.tempname()
  local cmd = {
    "curl",
    "-sS",
    "--compressed",
    "-A",
    lg.ua,
    "-b",
    lg.jar,
    "-c",
    lg.jar, -- 关键：把服务端下发的新 __client_id 写回 jar
    "-o",
    body_file,
    "-w",
    "%{http_code}",
  }
  vim.list_extend(cmd, args)

  vim.system(cmd, { text = true, timeout = 60000 }, function(res)
    vim.schedule(function()
      local body = ""
      if not out then
        body = table.concat(vim.fn.readfile(body_file, "b"), "\n")
        os.remove(body_file)
      end
      if res.code ~= 0 then
        cb({ status = 0, body = body, err = vim.trim(res.stderr or "") })
        return
      end
      cb({ status = tonumber((res.stdout or ""):match("%d+")) or 0, body = body })
    end)
  end)
end

--- 是不是 CDN 挑战（洛谷返回 302/307 让人带上 C3VK 再来）
---@param r {status: integer}
local function is_challenge(r)
  return r.status == 302 or r.status == 307
end

--- GET 一个页面；碰到挑战就重试一次（重试时 jar 里已经有刚下发的 C3VK 了）
---@param url string
---@param cb fun(r: {status: integer, body: string, err: string?})
---@param out? string
local function get(url, cb, out)
  curl({ url }, function(r)
    if r.err == nil and is_challenge(r) then
      curl({ url }, cb, out)
      return
    end
    cb(r)
  end, out)
end


--- 拿题面里的 csrf token（洛谷的 POST 必须带，且和当前 cookie 会话绑定）
---@param code string
---@param cb fun(token: string?, err: string?)
local function csrf(code, cb)
  get(lg.site .. "/problem/" .. code, function(r)
    if r.err then
      return cb(nil, "网络请求失败：" .. r.err)
    end
    if is_challenge(r) then
      return cb(nil, "洛谷一直把你重定向回题面（HTTP " .. r.status .. "）：cookie 已经不被接受了，"
        .. "用 <leader>lc 重新粘一次")
    end
    local token = r.body:match('csrf%-token"%s*content="([^"]+)"')
    if not token then
      return cb(nil, ("题面里没有 csrf token（HTTP %d）：可能是网络代理插了一手，或者 cookie 失效了"):format(r.status))
    end
    cb(token)
  end)
end

--- POST 一个 JSON 请求；和 get 一样，碰到 CDN 挑战就重试一次
---@param url string
---@param token string csrf token
---@param code string 题号（拼 Referer）
---@param payload string json 文件路径
---@param cb fun(r: {status: integer, body: string, err: string?})
local function post(url, token, code, payload, cb)
  local args = {
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
    "-H",
    "X-Csrf-Token: " .. token,
    "-H",
    "Referer: " .. lg.site .. "/problem/" .. code,
    "--data-binary",
    "@" .. payload,
    url,
  }
  curl(args, function(r)
    if r.err == nil and is_challenge(r) then
      curl(args, cb)
      return
    end
    cb(r)
  end)
end

--- 解析 JSON 响应（解不开就当空表，别让一个坏响应把整个流程炸掉）
---@param r {body: string}
---@return table
local function json(r)
  local ok, data = pcall(vim.json.decode, r.body)
  if ok and type(data) == "table" then
    return data
  end
  return {}
end

--- 把洛谷的返回翻译成人话
---@param r {status: integer, body: string, err: string?}
---@return string msg, integer level
local function explain(r)
  if r.err then
    return "curl 失败：" .. r.err, vim.log.levels.ERROR
  end
  local data = json(r)
  local etype = tostring(data.errorType or "")

  if etype:match("Captcha") then
    return "洛谷要验证码（" .. etype .. "）：这张图没输对，或者已经过期，再交一次重试", vim.log.levels.WARN
  end
  -- 注意：验证码错误也是 403，所以必须先按 errorType 分流，不能只看状态码
  if etype:match("UserNotLoggedIn") then
    return table.concat({
      "洛谷说“用户尚未登录”（HTTP 403）：cookie 真的失效了。用 <leader>lc 重新粘一次。",
      "__client_id 是 30 天滑动有效期，正常用着会自动续期（每次提交都写回 jar）；",
      "只有在别的设备/浏览器重新登录（旧值被顶掉）、点过“退出登录”、",
      "或者超过 30 天没用过，才会掉。",
    }, "\n"), vim.log.levels.ERROR
  end
  if is_challenge(r) then
    return ("洛谷的 CDN 一直把你重定向（HTTP %d）：cookie 已经不被接受了，用 <leader>lc 重新粘一次")
      :format(r.status), vim.log.levels.ERROR
  end
  if r.status == 429 then
    return "提交太频繁（HTTP 429），等几分钟再交", vim.log.levels.WARN
  end
  if r.status == 401 then
    return "csrf / cookie 不匹配（HTTP 401）：再试一次，还不行就重新登录", vim.log.levels.WARN
  end
  if data.errorCode == 403 then
    return "提交被拒（HTTP 403）：cookie 失效了，用 <leader>lc 重新粘一次", vim.log.levels.ERROR
  end
  return ("提交失败（HTTP %d）%s"):format(
    r.status,
    data.errorMessage and ("：" .. tostring(data.errorMessage)) or "，看 luogu://submit 窗口"
  ), vim.log.levels.ERROR
end

--- 取一张验证码图片（90x35 的 jpeg，和当前 cookie 会话绑定，输一次就作废）
---
--- 洛谷从 2025-05 起给提交接口加了验证码（站务帖里明说的“非官方工具提交变难”）；
--- 大多数人是**图片验证码**（/api/verify/captcha 返回 jpeg），少部分地区和网络会被升级成
--- Cloudflare 交互式验证（errorData.interactive，那个脚本没法过）。
---@param cb fun(path: string?, err: string?)
local function fetch_captcha(cb)
  local dest = vim.fs.normalize(vim.fn.stdpath("cache") .. "/captcha.jpg")
  vim.fn.mkdir(vim.fn.fnamemodify(dest, ":h"), "p")
  os.remove(dest)
  local url = ("%s/api/verify/captcha?_t=%d%d"):format(lg.site, os.time(), math.random(0, 999))
  get(url, function(r)
    if r.err then
      return cb(nil, "取验证码失败：" .. r.err)
    end
    if r.status ~= 200 then
      return cb(nil, ("取验证码失败（HTTP %d）"):format(r.status))
    end
    if vim.uv.fs_stat(dest) == nil then
      return cb(nil, "验证码图片没存下来：" .. dest)
    end
    cb(dest)
  end, dest)
end

--- 把验证码图片打开给用户看，再让他输进 nvim
---@param cb fun(answer: string?)
local function ask_captcha(cb)
  fetch_captcha(function(path, err)
    if not path then
      notify(err, vim.log.levels.WARN)
      return cb(nil)
    end
    local ok, res = pcall(vim.ui.open, path)
    if not ok or res == nil then
      notify("打不开图片查看器，验证码图片在：\n" .. path, vim.log.levels.WARN)
    end
    vim.ui.input({ prompt = "输入验证码: " }, function(answer)
      answer = vim.trim(answer or "")
      cb(answer ~= "" and answer or nil)
    end)
  end)
end

--- 一次真实的 POST（captcha 可选）
---@param code string
---@param file string
---@param captcha? string
---@param cb fun(r: {status: integer, body: string, err: string?})
local function submit_request(code, file, captcha, cb)
  csrf(code, function(token, err)
    if not token then
      cb({ status = 0, body = "", err = err })
      return
    end
    -- body 写临时文件再用 --data-binary @file：
    -- JSON 交给 vim.json.encode 生成，不用像上游 CLI 那样手工替换 \n \" \t
    -- （手写的转义碰上反斜杠/中文就会把提交内容弄成语法错误 → 白白 CE）
    local payload = vim.fn.tempname()
    local body = {
      enableO2 = 1,
      lang = lg.lang,
      code = table.concat(vim.fn.readfile(file), "\n"),
    }
    if captcha then
      body.captcha = captcha
    end
    vim.fn.writefile({ vim.json.encode(body) }, payload)

    post(lg.site .. "/fe/api/problem/submit/" .. code, token, code, payload, function(r)
      os.remove(payload)
      cb(r)
    end)
  end)
end

--- 提交当前文件
---@param code? string
function M.submit(code)
  code = resolve_code(code)
  if not code then
    notify("这个文件名里没有题号。把文件命名成 P1001.cpp，或者 :Luogu submit P1001", vim.log.levels.WARN)
    return
  end

  local file = source_file()
  if not file then
    notify("先打开解答目录里的题目文件（或停在同一道题的 .in 上也行）", vim.log.levels.WARN)
    return
  end

  local cookies = lg.seed_jar()
  if not cookies.__client_id then
    notify("还没登录洛谷。用 <leader>lc（:Luogu cookie）粘贴 Cookie，或者 <leader>lL 交互式登录", vim.log.levels.WARN)
    return
  end
  local before = cookies.__client_id

  write_source(file) -- 提交的一定是磁盘上的内容
  notify(("提交 %s …"):format(code))

  local tries = 3
  local attempt
  attempt = function(captcha)
    submit_request(code, file, captcha, function(r)
      if r.err then
        notify("提交失败：" .. r.err, vim.log.levels.ERROR)
        return
      end

      local lines = {
        ("%s   HTTP %d%s"):format(os.date("%H:%M:%S"), r.status, captcha and ("   captcha=" .. captcha) or ""),
        "",
        "POST " .. lg.site .. "/fe/api/problem/submit/" .. code,
      }
      vim.list_extend(lines, vim.split(r.body, "\n"))
      local after = lg.jar_cookies().__client_id
      if after and after ~= before then
        vim.list_extend(lines, { "", "[cookie 已续期并写入 " .. lg.jar .. "]" })
      end
      M.show("luogu://submit", lines)

      local rid = r.body:match('"rid"%s*:%s*(%d+)')
      if rid then
        local url = "https://www.luogu.com.cn/record/" .. rid
        pcall(vim.fn.setreg, "+", url)
        notify("已提交，评测记录：" .. url)
        return
      end

      local data = json(r)
      local etype = tostring(data.errorType or "")
      if etype:match("Captcha") then
        -- Cloudflare 交互式验证（Turnstile）：要浏览器里跑 JS，脚本过不了
        if type(data.errorData) == "table" and data.errorData.interactive then
          local src = table.concat(vim.fn.readfile(file), "\n")
          pcall(vim.fn.setreg, "+", src)
          notify("洛谷这次要 Cloudflare 交互式验证码（Turnstile），脚本过不了：\n"
            .. "代码已放进 + 寄存器，浏览器里粘贴提交吧", vim.log.levels.WARN)
          open_url(lg.site .. "/problem/" .. code)
          return
        end
        if tries <= 0 then
          notify("验证码连错 3 次，先停一下（也可以去浏览器提交）", vim.log.levels.ERROR)
          return
        end
        tries = tries - 1
        notify("洛谷要验证码，看图后输进来（还剩 " .. tries .. " 次机会）")
        ask_captcha(function(answer)
          if answer then
            attempt(answer)
          end
        end)
        return
      end

      local msg, level = explain(r)
      notify(msg, level)
    end)
  end
  attempt(nil)
end

--- 交互式登录：上游 CLI 用 scanf 读 _uid 和 __client_id，所以必须给它一个真终端
function M.login()
  local exe = M.cli()
  if not exe then
    return
  end
  vim.fn.mkdir(lg.cli_dir, "p")
  vim.cmd("tabnew")
  vim.cmd("terminal " .. vim.fn.shellescape(exe) .. " login")
  vim.cmd("startinsert")
  notify("按提示输入 _uid 和 __client_id（浏览器 F12 → Application/Storage → Cookie 里抄），"
    .. "输完 :q 关掉这个终端")
end

--- 直接把浏览器里的整条 Cookie 粘进来（比交互式登录省事，也不用终端）
---@param cookie? string
function M.cookie(cookie)
  if not cookie or cookie == "" then
    cookie = vim.fn.input("粘贴整条 Cookie（含 __client_id=… 和 _uid=…）: ")
  end

  -- 整条 Cookie 拆成 key=value，**不再用 [%w]+**：__client_id 里真出现 - / _ / = 的话，
  -- 按字母数字截断就会存下一个残缺的值 —— 提交时表现为“用户尚未登录”，
  -- 看起来就像 cookie 立刻过期了。
  local cookies = {}
  for pair in cookie:gmatch("[^;]+") do
    local k, v = pair:match("^%s*([^=]+)=(.*)$")
    if k then
      cookies[vim.trim(k)] = vim.trim(v)
    end
  end
  if not cookies.__client_id then
    notify("这段 Cookie 里没有 __client_id。要粘**整条** Cookie（F12 → Network → 任意请求 → Request Headers → Cookie），"
      .. "不是只粘其中某一项", vim.log.levels.WARN)
    return
  end

  lg.jar_set(cookies)
  -- 上游 CLI 的 login 命令还在读写这两个文件，一起写着（纯兼容，提交已经不用它了）
  vim.fn.writefile({ cookies.__client_id }, lg.cli_dir .. "/cli.txt")
  if cookies._uid and cookies._uid ~= "" then
    vim.fn.writefile({ cookies._uid }, lg.cli_dir .. "/uid.txt")
  end
  notify(("cookie 已写入 %s（%d 项）\n提交时洛谷会重新下发 __client_id，会自动续期，不用再手动换")
    :format(lg.jar, vim.tbl_count(cookies)), vim.log.levels.INFO)
end

--- 重新编上游的 C 版 LuoguCLI
function M.build()
  notify("正在编译 LuoguCLI …")
  local ok, msg = lg.build_cli()
  if ok then
    notify("编好了：" .. tostring(msg))
  else
    notify("编译失败：\n" .. tostring(msg), vim.log.levels.ERROR)
  end
end

--- 主菜单
function M.menu()
  vim.ui.select({
    { label = "新建题目", fn = M.new },
    { label = "打开题目", fn = M.files },
    { label = "题面（浏览器）", fn = M.open },
    { label = "题解（浏览器）", fn = M.solution },
    { label = "输入数据（P1001.in）", fn = M.input },
    { label = "本地运行", fn = M.run },
    { label = "提交", fn = M.submit },
    { label = "登录", fn = M.login },
    { label = "粘贴 Cookie 登录", fn = M.cookie },
    { label = "重新编译 LuoguCLI", fn = M.build },
  }, {
    prompt = "洛谷",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      choice.fn()
    end
  end)
end

local subcommands = {
  new = M.new,
  open = M.open,
  solution = M.solution,
  run = M.run,
  submit = M.submit,
  login = M.login,
  cookie = M.cookie,
  build = M.build,
  files = M.files,
  input = M.input,
}

function M.setup_command()
  vim.api.nvim_create_user_command("Luogu", function(args)
    local sub = args.fargs[1]
    if not sub then
      M.menu()
      return
    end
    local fn = subcommands[sub]
    if not fn then
      notify("未知子命令：" .. sub .. "（可用：new/open/solution/input/run/submit/login/cookie/files/build）",
        vim.log.levels.WARN)
      return
    end
    -- 从第 2 个参数起全部拼回去：:Luogu cookie 的 Cookie 串里带空格/分号
    local arg = args.fargs[2] and table.concat(args.fargs, " ", 2) or nil
    fn(arg)
  end, {
    nargs = "*",
    desc = "洛谷：new/open/solution/input/run/submit/login/cookie/files/build",
    complete = function()
      return vim.tbl_keys(subcommands)
    end,
  })
end

return M
