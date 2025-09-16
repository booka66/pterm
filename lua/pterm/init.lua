local M = {}

local terminal_tab = nil -- Only one terminal tab allowed
local terminal_buf = nil -- Track the terminal buffer
local current_tmux_session = nil

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

local function find_terminal_tab()
  if terminal_tab and vim.api.nvim_tabpage_is_valid(terminal_tab) then
    local wins = vim.api.nvim_tabpage_list_wins(terminal_tab)
    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      if terminal_buf and buf == terminal_buf and vim.api.nvim_buf_is_valid(buf) then
        return terminal_tab, win, buf
      end
    end
  end
  return nil, nil, nil
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
  local tab, win, buf = find_terminal_tab()
  if tab and buf then
    current_tmux_session = session_name
    local job_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")

    -- Detach from current session and attach to new one
    vim.api.nvim_chan_send(job_id, "\003") -- Send Ctrl-C to interrupt
    vim.defer_fn(function()
      local attach_cmd = "tmux attach-session -t " .. vim.fn.shellescape(session_name) .. "\r"
      vim.api.nvim_chan_send(job_id, attach_cmd)
    end, 50)

    return true
  else
    -- Create new terminal tab
    return create_terminal_tab(session_name)
  end
end

local function create_terminal_tab(session_name)
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

  -- Create new tab
  vim.cmd("tabnew")
  terminal_tab = vim.api.nvim_get_current_tabpage()

  -- Create terminal in the new tab
  local cmd = session_name and ("tmux attach-session -t " .. vim.fn.shellescape(session_name)) or nil

  if cmd then
    vim.cmd("terminal " .. cmd)
  else
    vim.cmd("lcd " .. vim.fn.fnameescape(dir))
    vim.cmd("terminal")
  end

  terminal_buf = vim.api.nvim_get_current_buf()
  vim.cmd("startinsert")
  return true
end

local function switch_to_terminal_tab()
  if terminal_tab and vim.api.nvim_tabpage_is_valid(terminal_tab) then
    vim.api.nvim_set_current_tabpage(terminal_tab)
    vim.cmd("startinsert")
    return true
  end
  return false
end

M.toggle_terminal = function()
  local tab, win, buf = find_terminal_tab()

  if tab then
    local current_tab = vim.api.nvim_get_current_tabpage()

    if current_tab == tab then
      -- We're in the terminal tab, switch back to previous tab
      vim.cmd("tabprevious")
    else
      -- Switch to terminal tab
      vim.api.nvim_set_current_tabpage(tab)
      if win then
        vim.api.nvim_set_current_win(win)
      end
      vim.cmd("startinsert")
    end
  else
    -- No terminal tab exists, create one
    create_terminal_tab()
  end
end

M.new_terminal = function(name, dir)
  local session_name = name or "pterm-default"

  local tab, win, buf = find_terminal_tab()
  if tab then
    -- Switch to existing session
    switch_to_session(session_name)
    -- Switch to the terminal tab
    vim.api.nvim_set_current_tabpage(terminal_tab)
    if win then
      vim.api.nvim_set_current_win(win)
    end
    vim.cmd("startinsert")
  else
    -- Create new terminal tab
    create_terminal_tab(session_name)
  end
end

M.close_terminal = function()
  if terminal_tab and vim.api.nvim_tabpage_is_valid(terminal_tab) then
    local current_tab = vim.api.nvim_get_current_tabpage()
    if current_tab == terminal_tab then
      -- We're in the terminal tab
      if vim.fn.tabpagenr('$') > 1 then
        vim.cmd("tabclose")
      else
        vim.cmd("enew") -- Don't close if it's the only tab
      end
    else
      -- Close terminal tab from another tab
      vim.api.nvim_set_current_tabpage(terminal_tab)
      vim.cmd("tabclose")
      vim.api.nvim_set_current_tabpage(current_tab)
    end
    terminal_tab = nil
    terminal_buf = nil
    current_tmux_session = nil
  end
end

M.send_line_to_terminal = function()
  local tab, win, buf = find_terminal_tab()
  if not tab then
    create_terminal_tab()
    tab, win, buf = find_terminal_tab()
  end

  if not tab then return end

  local line = vim.fn.getline(".")

  if current_tmux_session and tmux.is_available() then
    -- Send to tmux session
    local cmd = "tmux send-keys -t " .. vim.fn.shellescape(current_tmux_session) .. " " .. vim.fn.shellescape(line) .. " Enter"
    vim.fn.system(cmd)
  else
    -- Send to regular terminal
    local current_tab_page = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_tabpage(tab)
    vim.api.nvim_set_current_win(win)

    local job_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")
    vim.api.nvim_chan_send(job_id, line .. "\r")

    vim.api.nvim_set_current_tabpage(current_tab_page)
  end
end

M.send_selection_to_terminal = function()
  local tab, win, buf = find_terminal_tab()
  if not tab then
    create_terminal_tab()
    tab, win, buf = find_terminal_tab()
  end

  if not tab then return end

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
    local current_tab_page = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_tabpage(tab)
    vim.api.nvim_set_current_win(win)

    local job_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")
    vim.api.nvim_chan_send(job_id, text .. "\r")

    vim.api.nvim_set_current_tabpage(current_tab_page)
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
  local tab, win, buf = find_terminal_tab()
  if tab then
    local session_info = current_tmux_session and (" [tmux: " .. current_tmux_session .. "]") or ""
    local dir = get_smart_dir()
    print("Terminal tab exists" .. session_info .. " (dir: " .. dir .. ")")
  else
    print("No terminal tab")
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