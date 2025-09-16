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
- `<leader>tg` - Git terminal (runs `git status`)
- `<leader>td` - Dev server terminal (auto-detects npm/cargo)
- `<leader>tt` - Test terminal (auto-detects npm/cargo)
- `<leader>tc` - Claude terminal (runs `claude`)
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

Unlike traditional terminal plugins that create multiple floating windows or splits, pterm maintains exactly one terminal tab. When you request a new terminal (via any of the predefined commands), it closes the existing terminal tab and creates a fresh one.

This approach eliminates terminal clutter while providing quick access to common development tasks through the predefined terminal shortcuts.