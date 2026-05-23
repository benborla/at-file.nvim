# at-file.nvim

Type @ in insert mode to fuzzy-pick and insert a file path

Type `@` in insert mode → the dropdown lists files in your project. Keep typing to fuzzy-narrow. Accept → the `@query` is replaced with the file's path.

![demo](./demo.gif)

---

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Configuration](#configuration)
  - [`trigger`](#trigger)
  - [`insert_format`](#insert_format)
  - [`root`](#root)
  - [`max_entries`](#max_entries)
  - [`cache_ttl_ms`](#cache_ttl_ms)
  - [`enumerator`](#enumerator)
- [Recipes](#recipes)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Local development](#local-development)
- [License](#license)

---

## Features

- **Native UX** — uses blink.cmp's completion popup. No overlay window, no mode switch.
- **Project-aware** — auto-detects the search root (LazyVim → git → cwd).
- **Fast** — file list is cached and auto-invalidated on save / directory change.
- **`.gitignore`-aware** — uses `fd` → `rg` → `git ls-files`, all of which respect ignore files.
- **Configurable** — trigger char, insert format, root strategy, and file source are all overridable.

## Requirements

- **Neovim** 0.10+
- **[blink.cmp](https://github.com/Saghen/blink.cmp)** (any recent version with the standard source API)
- At least one of these on your `$PATH`:
  - [`fd`](https://github.com/sharkdp/fd) (preferred — fastest)
  - [`ripgrep`](https://github.com/BurntSushi/ripgrep)
  - `git` (works only inside git repos)

  The plugin tries them in that order and uses the first one available. If none is found, the dropdown will simply be empty.

## Installation

### lazy.nvim — minimal

```lua
{
  "saghen/blink.cmp",
  dependencies = { "benborla/at-file.nvim" },
  opts = {
    sources = {
      default = { "lsp", "path", "snippets", "buffer", "at_file" },
      providers = {
        at_file = {
          name = "AtFile",
          module = "at-file",
          score_offset = 100,
        },
      },
    },
  },
}
```

### lazy.nvim — with options

```lua
{
  "saghen/blink.cmp",
  dependencies = { "benborla/at-file.nvim" },
  opts = {
    sources = {
      default = { "lsp", "path", "snippets", "buffer", "at_file" },
      providers = {
        at_file = {
          name = "AtFile",
          module = "at-file",
          score_offset = 100,
          opts = {
            trigger       = "@",
            insert_format = "relative",
            root          = "auto",
            max_entries   = 10000,
            cache_ttl_ms  = 5000,
            -- enumerator = nil, -- see below
          },
        },
      },
    },
  },
}
```

### LazyVim

If you're on LazyVim, the snippets above work as-is — drop either one into `lua/plugins/at-file.lua`. LazyVim's blink.cmp defaults will be merged with your override.

### packer / paq / vim-plug

Just install the repo alongside blink.cmp:

```lua
-- packer
use { "saghen/blink.cmp", requires = { "benborla/at-file.nvim" } }
```

Then register the source in your blink.cmp setup the same way as the lazy.nvim examples above.

## Quick start

1. Install per the snippet above and restart Neovim.
2. Verify the source is registered:
   ```
   :lua =require("blink.cmp.config").sources.providers.at_file
   ```
   Should print a table containing `module = "at-file"`.
3. Open any file inside a project, enter insert mode, type `@`. The completion popup should appear with your project files.
4. Type a few characters to fuzzy-filter, press your blink.cmp accept key (default `<CR>` or `<Tab>`), and the `@query` is replaced with the selected file path.

## Configuration

All options go under `providers.at_file.opts` in your blink.cmp config. Every option is optional — defaults are sensible for most projects.

### `trigger`

| Type     | Default |
|----------|---------|
| `string` | `"@"`   |

The single character that opens the file dropdown. When this character is typed in insert mode, blink.cmp invokes the source and the popup appears. As long as the cursor stays on an unbroken `<trigger><query>` segment (no whitespace between trigger and cursor), the popup keeps filtering against what you type.

```lua
opts = { trigger = "#" }  -- use # instead of @
```

Only single characters are supported (this is a blink.cmp constraint). If you change this away from `@`, pick a character that doesn't conflict with what you commonly type (e.g. `:` is a poor choice in many languages).

### `insert_format`

| Type     | Default      | Values                                 |
|----------|--------------|----------------------------------------|
| `string` | `"relative"` | `"relative"` \| `"absolute"` \| `"prefixed"` |

Controls what text gets inserted into the buffer when you accept a completion. The selected file is `lua/config/keymaps.lua` in these examples:

| Value         | What's inserted                                           | Use when… |
|---------------|-----------------------------------------------------------|-----------|
| `"relative"`  | `lua/config/keymaps.lua`                                  | You want a clean path, e.g. in code comments, markdown links, or imports. |
| `"absolute"`  | `/Users/you/myproj/lua/config/keymaps.lua`                | You need a fully-qualified path, e.g. for tooling that doesn't understand project-relative paths. |
| `"prefixed"`  | `@lua/config/keymaps.lua`                                 | You're authoring AI prompts and want the `@` mention to remain in the text. |

The trigger character that you typed (`@query`) is always replaced as a unit — there's no "leftover" `@` regardless of which format you choose.

```lua
opts = { insert_format = "prefixed" }
```

### `root`

| Type                        | Default | Values                                                |
|-----------------------------|---------|-------------------------------------------------------|
| `string` or `function`      | `"auto"`  | `"auto"` \| `"git"` \| `"cwd"` \| `fun(bufnr): string` |

Determines the directory whose files are enumerated and made relative.

| Value     | Resolution order                                          |
|-----------|-----------------------------------------------------------|
| `"auto"`  | LazyVim's `Util.root()` (if LazyVim is installed) → nearest `.git` ancestor → `vim.fn.getcwd()` |
| `"git"`   | Nearest `.git` ancestor → `vim.fn.getcwd()`                |
| `"cwd"`   | Always `vim.fn.getcwd()`                                   |
| function  | Your function is called with the current buffer number and must return a directory string. |

Use a function when you need custom logic — e.g. monorepo packages, or a fixed directory that doesn't depend on the buffer:

```lua
opts = {
  root = function(bufnr)
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path:match("/packages/") then
      return path:match("(.-/packages/[^/]+)/")
    end
    return vim.fn.getcwd()
  end,
}
```

### `max_entries`

| Type     | Default |
|----------|---------|
| `number` | `10000` |

Hard cap on how many files are loaded into the completion list. Protects against runaway memory use in monorepos with hundreds of thousands of files. blink.cmp's fuzzy matcher handles 10k items easily; raise this if you have a huge repo and want everything indexed, or lower it if you want a snappier popup at the cost of recall.

```lua
opts = { max_entries = 50000 }
```

### `cache_ttl_ms`

| Type     | Default |
|----------|---------|
| `number` | `5000`  |

How long (in milliseconds) the file list is cached before being re-enumerated. The cache is **also** invalidated automatically when:

- A buffer is saved (`BufWritePost`)
- Neovim's working directory changes (`DirChanged`)

So in normal use you'll get fresh data whenever you save a new file. The TTL is a safety net for files created outside Neovim (e.g. via `git checkout`, another editor, or a build tool). Lower it for snappier freshness; raise it on slow filesystems or huge repos where enumeration takes noticeable time.

```lua
opts = { cache_ttl_ms = 1000 }  -- refresh every second
```

### `enumerator`

| Type                              | Default |
|-----------------------------------|---------|
| `nil` or `fun(root): string[]`    | `nil`   |

Replaces the built-in `fd`/`rg`/`git` chain entirely. Your function receives the resolved `root` directory and must return a list of file paths. Paths may be either:

- Absolute (anywhere on disk), or
- Relative to the `root` you were given.

Both are normalized to relative paths before being passed to the completion popup.

Use this when you need custom filtering, want to source files from somewhere unusual, or want to combine multiple directories. Examples:

```lua
-- Restrict to a few directories and exclude node_modules
opts = {
  enumerator = function(root)
    return vim.fn.systemlist({
      "fd", "--type", "f",
      "--exclude", "node_modules",
      "--exclude", "dist",
      ".", root,
    })
  end,
}
```

```lua
-- Pull from a fixed scratch directory regardless of root
opts = {
  enumerator = function(_)
    return vim.fn.globpath(vim.fn.expand("~/notes"), "**/*.md", false, true)
  end,
}
```

## Recipes

### `#` mentions for an AI-prompt buffer only

```lua
opts = {
  trigger = "#",
  insert_format = "prefixed",  -- keeps the # in the buffer
}
```

### Project root only — never fall back to cwd

```lua
opts = {
  root = function(bufnr)
    return vim.fs.root(bufnr, { ".git", "pyproject.toml", "package.json" })
      or error("no project root")
  end,
}
```

### Combine with file-type gating

blink.cmp lets you scope a source to filetypes via the provider spec:

```lua
providers = {
  at_file = {
    name = "AtFile",
    module = "at-file",
    enabled = function() return vim.bo.filetype == "markdown" end,
  },
}
```

## How it works

The source registers your `trigger` character as a blink.cmp [trigger character](https://cmp.saghen.dev/configuration/sources.html). When you type it, blink.cmp calls `get_completions(ctx, cb)`. The source:

1. Walks backwards from the cursor to find the most recent unbroken `<trigger><query>` segment on the current line.
2. Resolves the project root (per the `root` option) and grabs a (possibly cached) list of files relative to it.
3. Returns LSP-style completion items whose `textEdit` replaces the entire `<trigger><query>` range with the chosen path.

blink.cmp's built-in Rust fuzzy matcher does the filtering — no extra matcher dependency.

## Troubleshooting

**The popup never appears.**
Check that the source is registered: `:lua =require("blink.cmp.config").sources.providers.at_file`. If that's nil, your blink.cmp `opts` aren't being applied — make sure the spec is loaded (e.g. `:Lazy` shows `at-file.nvim`).

**The popup appears but is empty.**
None of `fd`, `rg`, or `git` were found on `$PATH`, or you're outside a git repo and the chosen root has no files. Run `:lua =vim.fn.executable("fd")` (or `"rg"` / `"git"`) — at least one should return `1`. Or supply an `enumerator` function explicitly.

**Wrong directory is being searched.**
Check what `root` resolves to:
```vim
:lua print(require("at-file").new({ root = "auto" }).opts.root)
```
If `root = "auto"` is picking the wrong directory (e.g. a parent git repo), switch to `"cwd"` or pass a custom function.

**File list is stale.**
The cache invalidates on `BufWritePost` and `DirChanged`. If you create files outside Neovim and want them immediately, drop `cache_ttl_ms` to something small (e.g. `500`) or call `:e` to nudge the autocmd.

**Items appear below LSP / buffer completions.**
Raise `score_offset` in your provider spec (the snippet uses `100`; try `1000` if other sources still win).

## Local development

If you want to hack on the plugin while it's installed:

```lua
{
  "saghen/blink.cmp",
  dependencies = {
    { "benborla/at-file.nvim", dir = vim.fn.expand("~/projects/at-file.nvim") },
  },
  -- ...rest of opts as before
}
```

The `dir = ...` line tells lazy.nvim to use your local checkout instead of cloning from GitHub. Remove it once you're done iterating.

## License

[MIT](./LICENSE) © Ben Borla

## Acknowledgements

- [blink.cmp](https://github.com/Saghen/blink.cmp) for the completion engine and the clean source API.
- [cmp-path](https://github.com/hrsh7th/cmp-path) and blink.cmp's own `path` source for the file-completion patterns this plugin follows.
