# git.nvim

> [!WARNING]
> This plugin is under active development. Its API, configuration, and
> behavior may change without notice.

A native Neovim commit and branch navigator implemented in Lua 5.1. Browse
history, inspect commits, switch branches, or move to a selected commit without
leaving Neovim.

## Features

- Asynchronous commit and branch loading with `vim.system()`
- Two-pane commit list and automatically colorized details/diff preview
- Color-highlighted additions, deletions, changed files, and diff hunks
- Local and remote branch navigation
- Safe detached HEAD checkout for selected commits
- Branch creation from a selected commit
- Return to the branch active before navigation
- Dirty-worktree protection
- File-specific history with `--follow`
- No dependencies other than Git

## Requirements

- Neovim 0.10 or later
- Git 2.23 or later

## Installation

### lazy.nvim

```lua
{
  "ue555/git.nvim",
  config = function()
    require("git_history").setup()
  end,
}
```

### nvpm

```json
"ue555/git.nvim"
```

## Configuration

```lua
require("git_history").setup({
  default_view = "commits",
  window = {
    width = 0.9,
    height = 0.85,
    list_width = 0.42,
    border = "rounded",
  },
  log = {
    max_count = 100,
  },
  checkout = {
    confirm = true,
    allow_dirty = false,
  },
  branch = {
    show_remote = true,
    allow_dirty = false,
    allow_delete = true,
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:GitHistory [directory]` | Browse repository commits |
| `:GitHistoryFile` | Browse commits for the current file |
| `:GitBranches [directory]` | Browse local and remote branches |
| `:GitCheckout {hash}` | Switch to a detached commit |
| `:GitSwitch {branch}` | Switch to a branch |
| `:GitNewBranch {name}` | Create and switch to a branch |
| `:GitHistoryBack` | Return to the original branch |
| `:GitHistoryRefresh` | Reload repository state |
| `:GitHistoryClose` | Close the interface |

## Mappings

| Key | Action |
|---|---|
| `1` / `2` | Commit view / branch view |
| `Tab` | Toggle views |
| `Enter` | Show commit details or switch branch |
| `l` / `h` | Move to Details / return to the list |
| `d` | Show commit diff |
| `f` | Show changed files |
| `c` | Switch to selected commit |
| `n` | Create a branch from the selection |
| `D` | Delete selected local branch |
| `P` | Fetch and prune remotes |
| `B` | Return to the original branch |
| `r` | Refresh |
| `q` / `Esc` | Close |

The plugin never runs `git reset --hard`, automatically stashes changes, or
deletes untracked files. Navigation is rejected while the worktree is dirty
unless explicitly enabled in configuration.

Without a directory argument, `:GitHistory` and `:GitBranches` use the
directory of the current file, falling back to Neovim's working directory.

## License

MIT
