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

--- 当前文件是不是能编译/提交的源码（.cpp / .c …）
---@param file string
---@return boolean
local function is_source(file)
  return vim.tbl_contains({ "c", "cc", "cpp", "cxx", "c++" }, vim.fn.fnamemodify(file, ":e"))
end

--- 有没有登录过（上游 CLI 把 __client_id 存在 cli.txt 里，空/不存在就是没登录）
---@return boolean
function M.logged_in()
  local f = io.open(lg.cli_dir .. "/cli.txt", "r")
  if not f then
    return false
  end
  local content = f:read("*a") or ""
  f:close()
  return content:match("%S") ~= nil
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

--- 本地编译 + 运行（有同名 .in 文件就从它读输入）
function M.run()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" or not lg.is_solution(file) then
    notify("先打开解答目录里的题目文件（:Luogu new P1001 / :Luogu files）", vim.log.levels.WARN)
    return
  end
  if not is_source(file) then
    notify("只能编译运行源码（.cpp / .c），当前文件是 ." .. vim.fn.fnamemodify(file, ":e"), vim.log.levels.WARN)
    return
  end
  vim.cmd.write()

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

      -- 输入：P1001.in 存在就喂给它，否则空输入（程序里的 scanf 立刻拿到 EOF）。
      -- 注意：vim.system 的 stdin 只支持 string / string[] / true，**不支持文件描述符**
      -- （nvim 0.12 把非法值直接忽略，症状就是程序读不到输入、一直卡到超时），
      -- 所以有 .in 文件时走 sh 重定向：大文件也不用整个读进内存，退出码还是程序自己的。
      local run_cmd, run_opts
      if vim.fn.filereadable(infile) == 1 then
        run_cmd = { "sh", "-c", vim.fn.shellescape(exe) .. " < " .. vim.fn.shellescape(infile) }
        run_opts = { text = true, timeout = lg.run_timeout }
      else
        run_cmd = { exe }
        run_opts = { text = true, stdin = "", timeout = lg.run_timeout }
      end

      vim.system(run_cmd, run_opts, function(run)
        vim.schedule(function()
          local lines = vim.split((run.stdout or "") .. (run.stderr or ""), "\n")
          if run.code == nil then
            lines[#lines + 1] = ("[超时，%.1f 秒后被杀]"):format(lg.run_timeout / 1000)
          elseif run.code ~= 0 then
            lines[#lines + 1] = ("[退出码 %d]"):format(run.code)
          end
          M.show("luogu://run", lines)
        end)
      end)

      if build_out ~= "" then
        notify("编译通过，但有警告：\n" .. build_out:sub(1, 400), vim.log.levels.WARN)
      end
    end)
  end)
end

--- 提交当前文件
---@param code? string
function M.submit(code)
  local exe = M.cli()
  if not exe then
    return
  end

  code = resolve_code(code)
  if not code then
    notify("这个文件名里没有题号。把文件命名成 P1001.cpp，或者 :Luogu submit P1001", vim.log.levels.WARN)
    return
  end

  local file = vim.api.nvim_buf_get_name(0)
  if file == "" or not lg.is_solution(file) then
    notify("先打开解答目录里的题目文件", vim.log.levels.WARN)
    return
  end
  if not is_source(file) then
    notify("只能提交源码（.cpp / .c），当前文件是 ." .. vim.fn.fnamemodify(file, ":e"), vim.log.levels.WARN)
    return
  end
  if not M.logged_in() then
    notify("还没登录洛谷。用 <leader>lL（:Luogu login）或者 <leader>lc（:Luogu cookie）先登录", vim.log.levels.WARN)
    return
  end
  vim.cmd.write() -- 提交的一定是磁盘上的内容

  notify(("提交 %s …"):format(code))
  vim.system({ exe, "submit", code, file }, { text = true }, function(out)
    local text = (out.stdout or "") .. (out.stderr or "")
    vim.schedule(function()
      local rid = text:match('"rid"%s*:%s*(%d+)')
      M.show("luogu://submit", vim.split(text, "\n"))
      if rid then
        local url = "https://www.luogu.com.cn/record/" .. rid
        pcall(vim.fn.setreg, "+", url)
        notify("已提交，评测记录：" .. url)
      elseif text:match("401") or text:match("Unauthorized") or text:match("307") then
        notify("提交失败：cookie 失效了，用 <leader>lL（:Luogu login）重新登录", vim.log.levels.ERROR)
      else
        notify("提交失败，看 luogu://submit 窗口里的原始响应", vim.log.levels.ERROR)
      end
    end)
  end)
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
  local client_id = cookie:match("__client_id=([%w]+)")
  local uid = cookie:match("_uid=([%w]+)")
  if not (client_id and uid) then
    notify("没从这段 Cookie 里解析出 __client_id / _uid，检查一下粘贴内容", vim.log.levels.WARN)
    return
  end
  vim.fn.mkdir(lg.cli_dir, "p")
  vim.fn.writefile({ client_id }, lg.cli_dir .. "/cli.txt")
  vim.fn.writefile({ uid }, lg.cli_dir .. "/uid.txt")
  notify("cookie 已写入 " .. lg.cli_dir)
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
