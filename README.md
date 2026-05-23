# at-file.nvim

A [blink.cmp](https://github.com/Saghen/blink.cmp) completion source that brings Cursor / ChatGPT-style **`@`-mention file picking** to Neovim's native completion popup.

Type `@` in insert mode → the dropdown lists files in your project. Keep typing to fuzzy-narrow. Accept → the `@query` is replaced with the file's relative path.

## Features

- Native completion popup (no overlay window, no mode switch).
- Project-aware root detection (LazyVim → git → cwd).
- Fast: file list cached and auto-invalidated on `BufWritePost` / `DirChanged`.
- Configurable trigger char, insert format, and root strategy.
- Uses `fd` → `rg` → `git ls-files` (whichever exists), so `.gitignore` is respected for free.

## Requirements

- Neovim 0.10+
- [blink.cmp](https://github.com/Saghen/blink.cmp)
- One of: [`fd`](https://github.com/sharkdp/fd), [`ripgrep`](https://github.com/BurntSushi/ripgrep), or `git`

## Installation

### lazy.nvim

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
          score_offset = 100, -- rank above LSP/buffer when @ is typed
          opts = {
            -- override any default here, e.g.:
            -- trigger = "@",
            -- insert_format = "relative",
            -- root = "auto",
          },
        },
      },
    },
  },
}
```

## Configuration

All options below are passed under `providers.at_file.opts`. Defaults shown:

| Option          | Type                                  | Default      | Description |
|-----------------|---------------------------------------|--------------|-------------|
| `trigger`       | `string`                              | `"@"`        | Single character that opens the dropdown. |
| `insert_format` | `"relative" \| "absolute" \| "prefixed"` | `"relative"` | What gets inserted on accept. `prefixed` keeps the trigger char (e.g. `@lua/foo.lua`). |
| `root`          | `"auto" \| "git" \| "cwd" \| fun(bufnr): string` | `"auto"`     | How to find the search root. `auto` tries LazyVim → git → cwd. |
| `max_entries`   | `number`                              | `10000`      | Cap on returned file count. |
| `cache_ttl_ms`  | `number`                              | `5000`       | File-list cache lifetime. Also cleared on `BufWritePost` and `DirChanged`. |
| `enumerator`    | `nil \| fun(root): string[]`          | `nil`        | Override the file listing. Return paths (relative or absolute — both are handled). |

### Examples

**Use `#` instead of `@`:**

```lua
opts = { trigger = "#" }
```

**Keep the trigger char in the buffer** (e.g. for AI prompt files):

```lua
opts = { insert_format = "prefixed" }
```

**Custom enumerator** (e.g. project files only, no node_modules):

```lua
opts = {
  enumerator = function(root)
    return vim.fn.systemlist({
      "fd", "--type", "f", "--exclude", "node_modules", "--exclude", ".git", ".", root,
    })
  end,
}
```

## How it works

The source registers `@` as a blink.cmp trigger character. On each keystroke after `@`, it walks back from the cursor to find the most recent unbroken `@<query>` segment, then returns completion items whose `textEdit` replaces that exact range with the chosen file path. blink.cmp's built-in fuzzy matcher does the filtering — no extra dependency.

## License

MIT
