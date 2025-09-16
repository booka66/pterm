local M = {}

local terminal_tab = nil -- Only one terminal tab allowed
local current_dir = nil
local tmux_session = nil

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
  local tabs = vim.api.nvim_list_tabpages()
  for _, tab in ipairs(tabs) do
    local wins = vim.api.nvim_tabpage_list_wins(tab)
    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      local buf_type = vim.api.nvim_buf_get_option(buf, "buftype")
      if buf_type == "terminal" then
        return tab, win, buf
      end
    end
  end
  return nil, nil, nil
end

local function create_terminal_tab(dir)
  dir = dir or get_smart_dir()
  current_dir = dir

  -- Create tmux session
  local session_name = "pterm-session"
  local use_tmux = tmux.is_available()

  if use_tmux then
    if not tmux.session_exists(session_name) then
      if not tmux.create_session(session_name, dir) then
        use_tmux = false
        vim.notify("Failed to create tmux session, using regular terminal", vim.log.levels.WARN)
      end
    end
    tmux_session = session_name
  end

  -- Create new tab
  vim.cmd("tabnew")
  terminal_tab = vim.api.nvim_get_current_tabpage()

  -- Create terminal in the new tab
  local cmd = use_tmux and ("tmux attach-session -t " .. vim.fn.shellescape(session_name)) or nil

  if cmd then
    vim.cmd("terminal " .. cmd)
  else
    vim.cmd("lcd " .. vim.fn.fnameescape(dir))
    vim.cmd("terminal")
  end

  vim.cmd("startinsert")

  -- Set tab name
  vim.api.nvim_set_current_tabpage(terminal_tab)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, "Terminal")
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
  -- Check if terminal tab exists and is valid
  local tab, win, buf = find_terminal_tab()

  if tab then
    terminal_tab = tab
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
  -- Close existing terminal tab if it exists
  if terminal_tab and vim.api.nvim_tabpage_is_valid(terminal_tab) then
    local current_tab = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_tabpage(terminal_tab)
    vim.cmd("tabclose")
    if current_tab ~= terminal_tab and vim.api.nvim_tabpage_is_valid(current_tab) then
      vim.api.nvim_set_current_tabpage(current_tab)
    end
  end

  -- Create new terminal tab
  create_terminal_tab(dir)
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

  if tmux_session and tmux.is_available() then
    -- Send to tmux session
    local cmd = "tmux send-keys -t " .. vim.fn.shellescape(tmux_session) .. " " .. vim.fn.shellescape(line) .. " Enter"
    vim.fn.system(cmd)
  else
    -- Send to regular terminal
    local current_tab = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_tabpage(tab)
    vim.api.nvim_set_current_win(win)

    local job_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")
    vim.api.nvim_chan_send(job_id, line .. "\r")

    vim.api.nvim_set_current_tabpage(current_tab)
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

  if tmux_session and tmux.is_available() then
    -- Send to tmux session
    local cmd = "tmux send-keys -t " .. vim.fn.shellescape(tmux_session) .. " " .. vim.fn.shellescape(text) .. " Enter"
    vim.fn.system(cmd)
  else
    -- Send to regular terminal
    local current_tab = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_tabpage(tab)
    vim.api.nvim_set_current_win(win)

    local job_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")
    vim.api.nvim_chan_send(job_id, text .. "\r")

    vim.api.nvim_set_current_tabpage(current_tab)
  end
end

-- Predefined terminal functions
M.create_git_terminal = function()
  M.close_terminal() -- Close existing terminal first
  create_terminal_tab()

  -- Switch to terminal and send git status
  vim.defer_fn(function()
    if tmux_session and tmux.is_available() then
      local cmd = "tmux send-keys -t " .. vim.fn.shellescape(tmux_session) .. " 'git status' Enter"
      vim.fn.system(cmd)
    else
      local tab, win, buf = find_terminal_tab()
      if buf then
        local job_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")
        vim.api.nvim_chan_send(job_id, "git status\r")
      end
    end
  end, 100)
end

M.create_dev_terminal = function()
  M.close_terminal() -- Close existing terminal first
  create_terminal_tab()

  -- Try to detect and run dev server
  vim.defer_fn(function()
    local cwd = current_dir or get_smart_dir()
    local cmd = nil

    if vim.fn.filereadable(cwd .. "/package.json") == 1 then
      cmd = "npm run dev"
    elseif vim.fn.filereadable(cwd .. "/Cargo.toml") == 1 then
      cmd = "cargo run"
    else
      cmd = "echo 'No dev command detected. Run your dev server manually.'"
    end

    if tmux_session and tmux.is_available() then
      local tmux_cmd = "tmux send-keys -t " .. vim.fn.shellescape(tmux_session) .. " " .. vim.fn.shellescape(cmd) .. " Enter"
      vim.fn.system(tmux_cmd)
    else
      local tab, win, buf = find_terminal_tab()
      if buf then
        local job_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")
        vim.api.nvim_chan_send(job_id, cmd .. "\r")
      end
    end
  end, 100)
end

M.create_test_terminal = function()
  M.close_terminal() -- Close existing terminal first
  create_terminal_tab()

  -- Try to detect and run tests
  vim.defer_fn(function()
    local cwd = current_dir or get_smart_dir()
    local cmd = nil

    if vim.fn.filereadable(cwd .. "/package.json") == 1 then
      cmd = "npm test"
    elseif vim.fn.filereadable(cwd .. "/Cargo.toml") == 1 then
      cmd = "cargo test"
    else
      cmd = "echo 'No test command detected. Run your tests manually.'"
    end

    if tmux_session and tmux.is_available() then
      local tmux_cmd = "tmux send-keys -t " .. vim.fn.shellescape(tmux_session) .. " " .. vim.fn.shellescape(cmd) .. " Enter"
      vim.fn.system(tmux_cmd)
    else
      local tab, win, buf = find_terminal_tab()
      if buf then
        local job_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")
        vim.api.nvim_chan_send(job_id, cmd .. "\r")
      end
    end
  end, 100)
end

M.create_claude_terminal = function()
  M.close_terminal() -- Close existing terminal first
  create_terminal_tab()

  -- Send claude command
  vim.defer_fn(function()
    if tmux_session and tmux.is_available() then
      local cmd = "tmux send-keys -t " .. vim.fn.shellescape(tmux_session) .. " 'claude' Enter"
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

  -- Kill tmux session if it exists
  if tmux_session and tmux.is_available() then
    tmux.kill_session(tmux_session)
    print("Terminal tab and tmux session killed")
  else
    print("Terminal tab killed")
  end

  tmux_session = nil
end

M.terminal_info = function()
  local tab, win, buf = find_terminal_tab()
  if tab then
    local session_info = tmux_session and (" [tmux: " .. tmux_session .. "]") or ""
    print("Terminal tab exists" .. session_info .. " (dir: " .. (current_dir or "unknown") .. ")")
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