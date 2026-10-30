-- 自动括号闭合。
--
-- 这份洛谷配置是完全独立的（不引 LazyVim），所以 LazyVim 自带的 mini.pairs
-- 在这里并不存在 —— 不装的话敲 `(` 不会自动补出 `()`。
-- OI 写代码时 `{}` 里回车自动展开成两行、跳过已存在的右括号，都挺省事。
-- 想去掉某类行为就改 opts，详见 :h MiniPairs.config。
return {
  {
    "echasnovski/mini.pairs",
    event = { "BufReadPre", "BufNewFile" },
    opts = {},
  },
}
