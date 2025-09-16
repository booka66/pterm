# pterm

A powerful terminal management plugin for Neovim that uses zellij for superior terminal session handling, project-aware directory switching, and advanced terminal features.

## Features

- **Smart Directory Detection**: Automatically opens terminals in git root or current file directory
- **Zellij Session Management**: Leverages zellij for robust session persistence and management
- **Named Terminal Management**: Create and manage multiple named terminals (Git, Dev Server, Tests, Claude)
- **Scroll Position Memory**: Remembers terminal scroll positions when switching between terminals
- **Terminal Tab Management**: Cycle through terminals like browser tabs
- **Send Code to Terminal**: Send current line or visual selection to terminal
- **Floating Titles**: Beautiful terminal titles showing terminal names
- **Full Screen Floating**: Distraction-free full-screen floating terminals
- **Session Persistence**: Zellij sessions survive Neovim restarts for true persistence

## Requirements

- Neovim >= 0.8.0
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)
- [zellij](https://github.com/zellij-org/zellij) (will be auto-installed via homebrew if not found)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "~/pterm", -- Local path to your pterm plugin
  dependencies = { "akinsho/toggleterm.nvim" },
  config = function()
    require("pterm").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "~/pterm", -- Local path to your pterm plugin
  requires = { "akinsho/toggleterm.nvim" },
  config = function()
    require("pterm").setup()
  end,
}
```

## Key Mappings

### Terminal Management

| Key               | Mode  | Description                       |
| ----------------- | ----- | --------------------------------- |
| `<M-t>` / `<D-t>` | n,i,t | Create new terminal tab           |
| `<C-Tab>`         | n,i,t | Cycle through terminals           |
| `<C-S-Tab>`       | n,i,t | Cycle backwards through terminals |
| `<C-\>`           | n,i,t | Toggle current terminal           |

### Terminal Control (Terminal Mode)

| Key                         | Mode | Description                  |
| --------------------------- | ---- | ---------------------------- |
| `<C-w>` / `<D-w>` / `<M-w>` | t    | Close current terminal       |
| `<C-h/j/k/l>`               | t    | Navigate to adjacent windows |
| `<C-x>`                     | t    | Exit terminal mode           |

### Quick Terminal Types

| Key          | Mode | Description                                  |
| ------------ | ---- | -------------------------------------------- |
| `<leader>tg` | n    | Git terminal                                 |
| `<leader>td` | n    | Dev server terminal                          |
| `<leader>tt` | n    | Test terminal                                |
| `<leader>tc` | n    | Claude terminal (auto-runs `claude` command) |

### Advanced Features

| Key          | Mode | Description                        |
| ------------ | ---- | ---------------------------------- |
| `<leader>ti` | n    | Show terminal info                 |
| `<leader>tn` | n    | Rename current terminal            |
| `<leader>tK` | n    | Kill all terminals                 |
| `<leader>tp` | n    | Pick terminal (fuzzy finder style) |
| `<leader>tr` | n    | Run project command               |
| `<leader>ts` | n/v  | Send line/selection to terminal   |
| `<leader>tX` | n    | Kill all zellij sessions          |

## Configuration

### Basic Setup

```lua
require("pterm").setup()
```

### Custom Configuration

```lua
require("pterm").setup({
  toggleterm = {
    -- Custom toggleterm options
    size = 25,
    winblend = 5,
    -- ... other toggleterm options
  }
})
```

### ToggleTerm Integration

This plugin is designed to work alongside toggleterm.nvim. Here's a recommended toggleterm configuration:

```lua
{
  "akinsho/toggleterm.nvim",
  version = "*",
  opts = {
    size = 20,
    open_mapping = [[<c-\>]],
    hide_numbers = true,
    shade_terminals = true,
    shading_factor = 2,
    start_in_insert = true,
    insert_mappings = true,
    terminal_mappings = true,
    persist_size = true,
    persist_mode = true,
    direction = "float",
    close_on_exit = true,
    shell = vim.o.shell,
    auto_scroll = false,
    float_opts = {
      border = "none",
      row = 0,
      col = 0,
      width = function() return vim.o.columns end,
      height = function() return vim.o.lines end,
      winblend = 3,
      highlights = {
        border = "FloatBorder",
        background = "Normal",
      },
    },
  },
}
```

## Smart Features

### Directory Detection

The plugin automatically detects the best directory for new terminals:

1. If in a git repository, opens terminal in git root
2. Otherwise, uses current file's directory
3. Falls back to current working directory

### Named Terminals

Create specific terminals for different purposes:

- **Git terminal**: For git operations
- **Dev Server terminal**: For running development servers
- **Test terminal**: For running tests
- **Claude terminal**: Automatically runs the `claude` command

### Session Persistence with Zellij

Unlike tmux-based solutions, pterm uses zellij which provides:
- Better session management and recovery
- Modern terminal multiplexer features
- Superior floating window support
- More intuitive command structure
- Excellent integration with modern terminals

## API

You can also use the plugin programmatically:

```lua
local pterm = require("pterm")

-- Create specific terminal types
pterm.create_git_terminal()
pterm.create_dev_terminal()
pterm.create_test_terminal()
pterm.create_claude_terminal()

-- Terminal management
pterm.new_terminal("Custom Name", "/custom/path")
pterm.toggle_current_terminal()
pterm.close_current_terminal()
pterm.cycle_terminals()

-- Utility functions
pterm.show_terminal_info()
pterm.send_line_to_terminal()
pterm.send_selection_to_terminal()
pterm.rename_terminal()
pterm.kill_all_terminals()
pterm.pick_terminal()
pterm.run_project_command()

-- Zellij session management
pterm.list_zellij_sessions()
pterm.kill_zellij_session("session-name")
pterm.kill_all_zellij_sessions()
```

## Zellij Integration

Pterm leverages zellij's powerful features:

### Session Commands
- Sessions are automatically created with the prefix `pterm-`
- Sessions persist across Neovim restarts
- Background sessions continue running even when not attached

### Direct Zellij Integration
If you want to interact with zellij directly:

```bash
# List all pterm sessions
zellij list-sessions | grep pterm-

# Attach to a specific session
zellij attach pterm-git

# Kill a specific session
zellij delete-session pterm-git
```

## Project Command Runner

Pterm automatically detects project types and offers relevant commands:

### npm/Node.js projects
- `npm run dev`
- `npm run build`
- `npm run test`
- `npm install`

### Rust/Cargo projects
- `cargo run`
- `cargo build`
- `cargo test`
- `cargo check`

### Custom commands
- Always available for any project type

## Migration from smart-terminals

If you're coming from nvim-smart-terminals, pterm provides identical functionality with these improvements:

- **Better session persistence**: Zellij sessions are more robust than tmux
- **Modern architecture**: Built on Rust-based zellij instead of C-based tmux
- **Identical API**: All functions and keybindings work the same way
- **Enhanced reliability**: Better handling of session creation/attachment

## Troubleshooting

### Zellij not found
If you get an error about zellij not being available, install it:

```bash
brew install zellij
# or
cargo install zellij
```

### Session creation fails
If zellij sessions fail to create:
1. Check that zellij is properly installed: `zellij --version`
2. Try creating a session manually: `zellij -s test-session`
3. Check zellij logs: `zellij setup --check`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License