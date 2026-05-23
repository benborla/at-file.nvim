-- at-file.nvim: @-triggered fuzzy file-path completion source for blink.cmp.

local M = {}
M.__index = M

local defaults = {
  -- Single character that opens the file picker dropdown.
  trigger = "@",
  -- "relative": replace `@query` with the project-relative path.
  -- "absolute": replace with the absolute path.
  -- "prefixed": replace with `@<relative-path>` (keeps the trigger char).
  insert_format = "relative",
  -- "auto": LazyVim root → git root → cwd.
  -- "git":  git root → cwd.
  -- "cwd":  always Neovim's cwd.
  -- function(bufnr): return your own root string.
  root = "auto",
  -- Cap the number of file entries to bound memory on huge repos.
  max_entries = 10000,
  -- File list cache lifetime, ms. Cache is also cleared on BufWritePost/DirChanged.
  cache_ttl_ms = 5000,
  -- Optional override: function(root) -> string[] of paths (relative or absolute).
  -- If nil, falls back to fd → rg → git ls-files.
  enumerator = nil,
}

local cache = nil

local function resolve_root(opts, bufnr)
  if type(opts.root) == "function" then
    local ok, r = pcall(opts.root, bufnr)
    if ok and type(r) == "string" and r ~= "" then return r end
  end
  if opts.root == "cwd" then return vim.fn.getcwd() end
  if opts.root == "auto" then
    local ok, lazy = pcall(require, "lazyvim.util")
    if ok and lazy and type(lazy.root) == "function" then
      local ok2, r = pcall(lazy.root)
      if ok2 and type(r) == "string" and r ~= "" then return r end
    end
  end
  return vim.fs.root(bufnr or 0, { ".git" }) or vim.fn.getcwd()
end

local function builtin_enumerator(root)
  local commands = {
    { "fd",  { "--type", "f", "--hidden", "--exclude", ".git", "--color", "never", ".", root } },
    { "rg",  { "--files", "--hidden", "--glob", "!.git", root } },
    { "git", { "-C", root, "ls-files", "--cached", "--others", "--exclude-standard" } },
  }
  for _, spec in ipairs(commands) do
    if vim.fn.executable(spec[1]) == 1 then
      local argv = { spec[1] }
      vim.list_extend(argv, spec[2])
      local out = vim.fn.systemlist(argv)
      if vim.v.shell_error == 0 and #out > 0 then return out end
    end
  end
  return {}
end

local function to_relative(files, root)
  local prefix = root:sub(-1) == "/" and root or (root .. "/")
  local rel = {}
  for _, f in ipairs(files) do
    local r = f
    if r:sub(1, #prefix) == prefix then r = r:sub(#prefix + 1) end
    if r ~= "" then rel[#rel + 1] = r end
  end
  return rel
end

local function get_files(opts, root)
  local now = vim.uv.hrtime()
  local ttl_ns = opts.cache_ttl_ms * 1e6
  if cache and cache.root == root and now < cache.expires_at then
    return cache.items
  end

  local raw
  if type(opts.enumerator) == "function" then
    raw = opts.enumerator(root) or {}
  else
    raw = builtin_enumerator(root)
  end
  local files = to_relative(raw, root)

  if #files > opts.max_entries then
    local trimmed = {}
    for i = 1, opts.max_entries do trimmed[i] = files[i] end
    files = trimmed
  end

  cache = { root = root, items = files, expires_at = now + ttl_ns }
  return files
end

local group = vim.api.nvim_create_augroup("AtFileCache", { clear = true })
vim.api.nvim_create_autocmd({ "BufWritePost", "DirChanged" }, {
  group = group,
  callback = function() cache = nil end,
})

function M.new(opts)
  return setmetatable({
    opts = vim.tbl_deep_extend("force", defaults, opts or {}),
  }, M)
end

function M:get_trigger_characters()
  return { self.opts.trigger }
end

function M:enabled()
  local bt = vim.bo.buftype
  return bt ~= "prompt" and bt ~= "terminal" and bt ~= "nofile"
end

function M:get_completions(ctx, callback)
  local trigger = self.opts.trigger
  local trigger_esc = vim.pesc(trigger)
  local line = ctx.line or ""
  local cursor_col = ctx.cursor[2]
  local row0 = ctx.cursor[1] - 1

  local before = line:sub(1, cursor_col)
  local at_idx = before:find(trigger_esc .. "[^%s" .. trigger_esc .. "]*$")
  if not at_idx then
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return function() end
  end

  local at_col0 = at_idx - 1
  local root = resolve_root(self.opts, ctx.bufnr)
  local files = get_files(self.opts, root)

  local range = {
    start = { line = row0, character = at_col0 },
    ["end"] = { line = row0, character = cursor_col },
  }

  local CompletionItemKind = vim.lsp.protocol.CompletionItemKind
  local fmt = self.opts.insert_format
  local abs_prefix = root:sub(-1) == "/" and root or (root .. "/")

  local items = {}
  for i, rel in ipairs(files) do
    local insert
    if fmt == "absolute" then
      insert = abs_prefix .. rel
    elseif fmt == "prefixed" then
      insert = trigger .. rel
    else
      insert = rel
    end
    items[i] = {
      label = rel,
      kind = CompletionItemKind.File,
      filterText = rel,
      insertText = insert,
      textEdit = { newText = insert, range = range },
    }
  end

  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
  return function() end
end

return M
