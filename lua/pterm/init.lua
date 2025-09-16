local M = {}

local terminal_buf = nil -- Track the terminal buffer
local original_win_config = {} -- Store original window layout
local current_tmux_session = nil
local is_terminal_visible = false

-- Tmux utility functions
local tmux = {}

function tmux.is_available()
  return vim.fn.executable("tmux") == 1
end

function tmux.session_exists(session_name)
  if not tmux.is_available() then return false end
  local result = vim.fn.system("tmux has-session -t " .. vim.fn.shellescape(session_name) .. " 2>/dev/null")
  return vim.v.shell_error == 0
end

function tmux.create_session(session_name, start_dir)
  if not tmux.is_available() then return false end
  local cmd = "tmux new-session -d -s " .. vim.fn.shellescape(session_name)
  if start_dir then
    cmd = cmd .. " -c " .. vim.fn.shellescape(start_dir)
  end
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

function tmux.kill_session(session_name)
  if not tmux.is_available() then return false end
  vim.fn.system("tmux kill-session -t " .. vim.fn.shellescape(session_name) .. " 2>/dev/null")
  return vim.v.shell_error == 0
end

function tmux.list_sessions()
  if not tmux.is_available() then return {} end
  local output = vim.fn.system("tmux list-sessions -F '#{session_name}' 2>/dev/null")
  if vim.v.shell_error ~= 0 then return {} end
  local sessions = {}
  for session in output:gmatch("[^\r\n]+") do
    table.insert(sessions, session)
  end
  return sessions
end

local function get_smart_dir()
  local current_file = vim.fn.expand("%:p")
  if current_file ~= "" then
    local dir = vim.fn.fnamemodify(current_file, ":h")
    if vim.fn.isdirectory(dir) == 1 then
      local git_root =
        vim.fn.system("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")
      if vim.v.shell_error == 0 then
        git_root = vim.fn.trim(git_root)
        if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
          return git_root
        end
      end
      return dir
    end
  end
  local cwd = vim.fn.getcwd()
  if vim.fn.isdirectory(cwd) == 1 then
    return cwd
  end
  return vim.fn.expand("~")
end

local function save_window_layout()
  original_win_config = {
    wins = {},
    current_win = vim.api.nvim_get_current_win()
  }

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    original_win_config.wins[win] = {
      buf = buf,
      width = vim.api.nvim_win_get_width(win),
      height = vim.api.nvim_win_get_height(win),
      row = vim.api.nvim_win_get_position(win)[1],
      col = vim.api.nvim_win_get_position(win)[2]
    }
  end
end

local function hide_terminal()
  if not is_terminal_visible then return end

  is_terminal_visible = false

  -- Close all windows except original ones
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if terminal_buf and buf == terminal_buf then
      vim.api.nvim_win_close(win, false)
      break
    end
  end

  -- Restore focus to original window if it still exists
  if original_win_config.current_win and vim.api.nvim_win_is_valid(original_win_config.current_win) then
    vim.api.nvim_set_current_win(original_win_config.current_win)
  end
end

local function show_terminal()
  if is_terminal_visible then return end

  save_window_layout()
  is_terminal_visible = true

  -- Create terminal buffer if it doesn't exist
  if not terminal_buf or not vim.api.nvim_buf_is_valid(terminal_buf) then
    create_terminal_buffer()
  end

  -- Hide all current windows by creating a single fullscreen window
  vim.cmd("only") -- Close all other windows

  -- Create new window for terminal
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, terminal_buf)
  vim.cmd("startinsert")
end

local function create_terminal_buffer(session_name)
  session_name = session_name or "pterm-default"
  local dir = get_smart_dir()

  -- Create tmux session if it doesn't exist
  if tmux.is_available() then
    if not tmux.session_exists(session_name) then
      if not tmux.create_session(session_name, dir) then
        vim.notify("Failed to create tmux session, using regular terminal", vim.log.levels.WARN)
        session_name = nil
      end
    end
    current_tmux_session = session_name
  end

  -- Create terminal buffer
  terminal_buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(terminal_buf, "buftype", "terminal")
  vim.api.nvim_buf_set_option(terminal_buf, "bufhidden", "hide")

  -- Start terminal
  local cmd = session_name and ("tmux attach-session -t " .. vim.fn.shellescape(session_name)) or vim.o.shell

  vim.api.nvim_call_function("termopen", {cmd, {}})

  return terminal_buf
end

local function switch_to_session(session_name)
  if not tmux.is_available() then
    vim.notify("tmux not available", vim.log.levels.ERROR)
    return false
  end

  if not tmux.session_exists(session_name) then
    local dir = get_smart_dir()
    if not tmux.create_session(session_name, dir) then
      vim.notify("Failed to create tmux session: " .. session_name, vim.log.levels.ERROR)
      return false
    end
  end

  -- If we have an existing terminal, send the attach command
  if terminal_buf and vim.api.nvim_buf_is_valid(terminal_buf) then
    current_tmux_session = session_name
    local job_id = vim.api.nvim_buf_get_var(terminal_buf, "terminal_job_id")

    -- Detach from current session and attach to new one
    vim.api.nvim_chan_send(job_id, "\003") -- Send Ctrl-C to interrupt
    vim.defer_fn(function()
      local attach_cmd = "tmux attach-session -t " .. vim.fn.shellescape(session_name) .. "\r"
      vim.api.nvim_chan_send(job_id, attach_cmd)
    end, 50)

    return true
  else
    -- Create new terminal buffer
    create_terminal_buffer(session_name)
    return true
  end
end

M.toggle_terminal = function()
  if is_terminal_visible then
    hide_terminal()
  else
    show_terminal()
  end
end

M.new_terminal = function(name, dir)
  local session_name = name or "pterm-default"

  -- Switch to or create the session
  switch_to_session(session_name)

  -- Show terminal if not visible
  if not is_terminal_visible then
    show_terminal()
  end
end

M.close_terminal = function()
  if is_terminal_visible then
    hide_terminal()
  end

  -- Optionally destroy terminal buffer completely
  if terminal_buf and vim.api.nvim_buf_is_valid(terminal_buf) then
    vim.api.nvim_buf_delete(terminal_buf, { force = true })
    terminal_buf = nil
    current_tmux_session = nil
  end
end

M.send_line_to_terminal = function()
  if not terminal_buf or not vim.api.nvim_buf_is_valid(terminal_buf) then
    show_terminal()
  end

  local line = vim.fn.getline(".")

  if current_tmux_session and tmux.is_available() then
    -- Send to tmux session
    local cmd = "tmux send-keys -t " .. vim.fn.shellescape(current_tmux_session) .. " " .. vim.fn.shellescape(line) .. " Enter"
    vim.fn.system(cmd)
  else
    -- Send to regular terminal
    local job_id = vim.api.nvim_buf_get_var(terminal_buf, "terminal_job_id")
    vim.api.nvim_chan_send(job_id, line .. "\r")
  end
end

M.send_selection_to_terminal = function()
  if not terminal_buf or not vim.api.nvim_buf_is_valid(terminal_buf) then
    show_terminal()
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.fn.getline(start_pos[2], end_pos[2])

  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_pos[3], end_pos[3])
  else
    lines[1] = string.sub(lines[1], start_pos[3])
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  end

  local text = table.concat(lines, "\n")

  if current_tmux_session and tmux.is_available() then
    -- Send to tmux session
    local cmd = "tmux send-keys -t " .. vim.fn.shellescape(current_tmux_session) .. " " .. vim.fn.shellescape(text) .. " Enter"
    vim.fn.system(cmd)
  else
    -- Send to regular terminal
    local job_id = vim.api.nvim_buf_get_var(terminal_buf, "terminal_job_id")
    vim.api.nvim_chan_send(job_id, text .. "\r")
  end
end

-- Predefined terminal functions
M.create_git_terminal = function()
  M.new_terminal("pterm-git")
end

M.create_dev_terminal = function()
  M.new_terminal("pterm-dev")
end

M.create_test_terminal = function()
  M.new_terminal("pterm-test")
end

M.create_claude_terminal = function()
  M.new_terminal("pterm-claude")

  -- Send claude command
  vim.defer_fn(function()
    if current_tmux_session and tmux.is_available() then
      local cmd = "tmux send-keys -t " .. vim.fn.shellescape(current_tmux_session) .. " 'claude' Enter"
      vim.fn.system(cmd)
    else
      local tab, win, buf = find_terminal_tab()
      if buf then
        local job_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")
        vim.api.nvim_chan_send(job_id, "claude\r")
      end
    end
  end, 100)
end

M.kill_all_terminals = function()
  -- Close terminal tab
  M.close_terminal()

  -- Kill all pterm tmux sessions
  if tmux.is_available() then
    local all_sessions = tmux.list_sessions()
    local killed_count = 0

    for _, session in ipairs(all_sessions) do
      if session:match("^pterm%-") then
        if tmux.kill_session(session) then
          killed_count = killed_count + 1
        end
      end
    end

    if killed_count > 0 then
      print("Terminal tab and " .. killed_count .. " pterm tmux sessions killed")
    else
      print("Terminal tab killed (no pterm tmux sessions found)")
    end
  else
    print("Terminal tab killed")
  end
end

M.terminal_info = function()
  if terminal_buf and vim.api.nvim_buf_is_valid(terminal_buf) then
    local session_info = current_tmux_session and (" [tmux: " .. current_tmux_session .. "]") or ""
    local dir = get_smart_dir()
    local visible = is_terminal_visible and " (visible)" or " (hidden)"
    print("Terminal exists" .. session_info .. visible .. " (dir: " .. dir .. ")")
  else
    print("No terminal")
  end
end

M.setup = function(opts)
  opts = opts or {}

  -- Prevent double setup
  if vim.g.pterm_setup_called then
    return
  end
  vim.g.pterm_setup_called = true

  local map = vim.keymap.set

  -- Core terminal controls
  map({ "n", "i", "t" }, "<C-\\>", M.toggle_terminal, { desc = "Toggle terminal tab" })
  map({ "n", "i", "t" }, "<M-t>", M.new_terminal, { desc = "New terminal tab" })
  map({ "n", "i", "t" }, "<D-t>", M.new_terminal, { desc = "New terminal tab (Cmd)" })

  -- Terminal window navigation
  map("t", "<C-h>", "<C-\\><C-N><C-w>h", { desc = "Terminal left window nav" })
  map("t", "<C-j>", "<C-\\><C-N><C-w>j", { desc = "Terminal down window nav" })
  map("t", "<C-k>", "<C-\\><C-N><C-w>k", { desc = "Terminal up window nav" })
  map("t", "<C-l>", "<C-\\><C-N><C-w>l", { desc = "Terminal right window nav" })
  map("t", "<C-x>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

  -- Close terminal
  map("t", "<C-w>", M.close_terminal, { desc = "Close terminal tab" })
  map("t", "<D-w>", M.close_terminal, { desc = "Close terminal tab" })
  map("t", "<M-w>", M.close_terminal, { desc = "Close terminal tab" })

  -- Terminal management
  map("n", "<leader>ti", M.terminal_info, { desc = "Terminal info" })
  map("n", "<leader>tg", M.create_git_terminal, { desc = "Git terminal" })
  map("n", "<leader>td", M.create_dev_terminal, { desc = "Dev server terminal" })
  map("n", "<leader>tt", M.create_test_terminal, { desc = "Test terminal" })
  map("n", "<leader>tc", M.create_claude_terminal, { desc = "Claude terminal" })
  map("n", "<leader>ts", M.send_line_to_terminal, { desc = "Send line to terminal" })
  map("v", "<leader>ts", M.send_selection_to_terminal, { desc = "Send selection to terminal" })
  map("n", "<leader>tK", M.kill_all_terminals, { desc = "Kill all terminals" })
end

return M