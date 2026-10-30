-- C++ 的 tree-sitter 语法解析器
--
-- Neovim 自带的只有 c / lua / vim / markdown 几个 parser，**没有 cpp**。
-- 上游 nvim-treesitter（main 分支）装 parser 要额外的 `tree-sitter` CLI，而那个 CLI
-- 本机常常没有（brew/npm/cargo 各装一份很烦）；旧 master 分支又要跟着改 API。
--
-- 这里干脆不装 nvim-treesitter：tree-sitter-cpp 的 parser.c + scanner.c 用 cc 编成
-- cpp.so，放进 data 目录的 site/parser/ 下，再把它的 queries（高亮 / 缩进 / 折叠）拷到
-- site/queries/cpp/。注意是 **site** 而不是 data 根目录：nvim 的 runtimepath 里
-- 放的是 stdpath("data")/site（nvim-treesitter 也装在那儿），data 根目录不在 rtp 上，
-- 放错地方的症状就是 "Parser could not be created"。
-- 这样 `vim.treesitter.start(buf, "cpp")` 直接就能用，不需要任何插件。
local M = {}

local data = vim.fs.normalize(vim.fn.stdpath("data"))

M.parser = data .. "/site/parser/cpp.so"
M.queries = data .. "/site/queries/cpp"
local src = data .. "/tree-sitter-cpp"

local building = false

local notify = function(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "luogu" })
end

---@return boolean
function M.ready()
  return vim.uv.fs_stat(M.parser) ~= nil
end

--- 给这个 buffer 开 C++ 高亮（parser 还没编好时安静地什么都不做）
---@param bufnr? integer
function M.start(bufnr)
  if not M.ready() then
    return
  end
  pcall(vim.treesitter.start, bufnr or 0, "cpp")
end

--- 第一次启动时后台编一次 parser；以后就只是 fs_stat 一下
---@param force? boolean
function M.ensure(force)
  if building then
    return
  end
  if M.ready() and not force then
    return
  end
  if vim.fn.executable("cc") == 0 then
    notify("没装 cc，编不了 C++ 语法解析器（不影响编辑，只是没有语法高亮）", vim.log.levels.WARN)
    return
  end
  building = true
  notify("正在准备 C++ 语法解析器（只需一次）…")

  -- 整段丢给 sh：只有一个回调，省得在 fast-event 上下文里层层 vim.schedule
  local script = table.concat({
    "set -e",
    'if [ ! -d "$1" ]; then',
    '  git clone --depth 1 https://github.com/tree-sitter/tree-sitter-cpp "$1" >/dev/null 2>&1',
    "fi",
    'mkdir -p "$(dirname "$2")" "$3"',
    'cc -O2 -shared -fPIC -I "$1/src" -o "$2" "$1/src/parser.c" "$1/src/scanner.c"',
    'cp "$1"/queries/*.scm "$3"/',
  }, "\n")

  vim.system({ "sh", "-c", script, "sh", src, M.parser, M.queries }, { text = true }, function(res)
    vim.schedule(function()
      building = false
      if res.code ~= 0 then
        notify(
          "C++ 语法解析器编译失败（不影响编辑，只是没有高亮）：\n" .. (res.stderr or ""):sub(-800),
          vim.log.levels.WARN
        )
        return
      end
      -- 已经打开的 C++ 文件补上高亮
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "cpp" then
          M.start(b)
        end
      end
      notify("C++ 语法解析器已就绪")
    end)
  end)
end

return M
