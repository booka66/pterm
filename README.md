# pterm - Simple Terminal Tab Management

A minimalist Neovim plugin for managing a single terminal tab with tmux integration.

## Features

- **Single Terminal Tab**: Only one terminal tab at a time (no clutter)
- **Smart Directory Detection**: Automatically starts in git root or current file directory
- **Tmux Integration**: Uses tmux sessions for persistence
- **Predefined Terminals**: Quick shortcuts for git, dev server, tests, and Claude
- **Send Code to Terminal**: Send lines or selections to the terminal

## Key Mappings

### Core Controls
- `<C-\>` - Toggle terminal tab
- `<M-t>` or `<D-t>` - Create new terminal tab (closes existing one)
- `<C-w>`, `<D-w>`, `<M-w>` - Close terminal tab (from terminal mode)

### Terminal Navigation
- `<C-h/j/k/l>` - Window navigation from terminal mode
- `<C-x>` - Exit terminal mode

### Leader Key Commands
- `<leader>ti` - Show terminal info
- `<leader>tg` - Switch to Git terminal session
- `<leader>td` - Switch to Dev terminal session
- `<leader>tt` - Switch to Test terminal session
- `<leader>tc` - Switch to Claude terminal session (runs `claude`)
- `<leader>ts` - Send current line/selection to terminal
- `<leader>tK` - Kill all terminals and tmux sessions

## Installation

Add the plugin directory to your Neovim runtime path or install via your plugin manager.

## Setup

```lua
require("pterm").setup()
```

The plugin will auto-setup on VimEnter if not explicitly called.

## How It Works

Unlike traditional terminal plugins that create multiple floating windows or splits, pterm maintains exactly one terminal tab that connects to different tmux sessions based on the context:

- **Single Terminal Tab**: Only one terminal tab exists, preventing tab clutter
- **Multiple Tmux Sessions**: Each terminal type (git, dev, test, claude) connects to its own persistent tmux session
- **Session Switching**: The same terminal tab seamlessly switches between different tmux sessions
- **Session Persistence**: Tmux sessions persist even when the terminal tab is closed, allowing you to resume work

This approach works similar to how Neogit manages its interface - one dedicated tab that can show different contexts while maintaining state in the background.