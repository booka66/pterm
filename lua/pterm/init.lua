local M = {}

local term_count = 0
local terminals = {}
local current_term = 1
local terminal_names = {}
local terminal_scroll_positions = {}
local terminal_buffers = {} -- Store terminal buffer content for persistence

-- Abduco utility functions
local abduco = {}

function abduco.is_available()
  return vim.fn.executable("abduco") == 1
end

function abduco.session_exists(session_name)
  if not abduco.is_available() then return false end
  -- abduco -l format: "  Day Date Time session-name"
  -- We need to match the session name at the end of the line
  local result = vim.fn.system("abduco -l 2>/dev/null | grep -q " .. vim.fn.shellescape("\\s" .. session_name .. "$"))
  return vim.v.shell_error == 0
end

function abduco.create_session(session_name, start_dir)
  if not abduco.is_available() then return false end
  -- abduco doesn't support setting working directory directly, we'll handle it in the shell command
  return true
end

function abduco.kill_session(session_name)
  if not abduco.is_available() then return false end
  -- Find and kill the session
  local pid_output = vim.fn.system("abduco -l 2>/dev/null | grep " .. vim.fn.shellescape("^" .. session_name .. " ") .. " | awk '{print $2}'")
  if vim.v.shell_error == 0 and pid_output ~= "" then
    local pid = vim.fn.trim(pid_output)
    vim.fn.system("kill " .. pid .. " 2>/dev/null")
    return vim.v.shell_error == 0
  end
  return false
end

function abduco.list_sessions()
  if not abduco.is_available() then return {} end
  local output = vim.fn.system("abduco -l 2>/dev/null | awk '/^  [A-Z]/ {print $NF}'")
  if vim.v.shell_error ~= 0 then return {} end
  local sessions = {}
  for session in output:gmatch("[^\r\n]+") do
    if session ~= "" then
      table.insert(sessions, session)
    end
  end
  return sessions
end

function abduco.attach_session(session_name, start_dir)
  if not abduco.is_available() then return false end
  if start_dir then
    -- Create a shell command that changes directory before attaching
    return "cd " .. vim.fn.shellescape(start_dir) .. " && abduco -a " .. vim.fn.shellescape(session_name)
  else
    return "abduco -a " .. vim.fn.shellescape(session_name)
  end
end

function abduco.create_and_attach_session(session_name, start_dir)
  if not abduco.is_available() then return false end

  -- Use dvtm if available for better terminal management and scrollback
  local cmd_to_run
  if vim.fn.executable("dvtm") == 1 then
    cmd_to_run = "dvtm"
  else
    cmd_to_run = vim.o.shell
  end

  if start_dir then
    -- Create session with command that starts in the right directory
    return "cd " .. vim.fn.shellescape(start_dir) .. " && abduco -c " .. vim.fn.shellescape(session_name) .. " " .. cmd_to_run
  else
    return "abduco -c " .. vim.fn.shellescape(session_name) .. " " .. cmd_to_run
  end
end

local function save_terminal_state(term)
  if term.window and vim.api.nvim_win_is_valid(term.window) then
    pcall(function()
      local cursor_pos = vim.api.nvim_win_get_cursor(term.window)
      local view = vim.api.nvim_win_call(term.window, function()
        return vim.fn.winsaveview()
      end)

      -- Save buffer content
      local buf = vim.api.nvim_win_get_buf(term.window)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      terminal_scroll_positions[term.count] = {
        cursor = cursor_pos,
        view = view,
      }

      -- Store buffer content for session persistence
      if term.abduco_session then
        terminal_buffers[term.abduco_session] = {
          lines = lines,
          cursor = cursor_pos,
          view = view,
        }
      end
    end)
  end
end

-- Alias for backward compatibility
local function save_scroll_position(term)
  save_terminal_state(term)
end

local function restore_terminal_state(term, session_name)
  -- First check if we have saved buffer content for this session
  if session_name and terminal_buffers[session_name] then
    vim.defer_fn(function()
      if term.window and vim.api.nvim_win_is_valid(term.window) then
        pcall(function()
          local saved_state = terminal_buffers[session_name]
          local buf = vim.api.nvim_win_get_buf(term.window)

          -- Create a temporary buffer with saved content
          local temp_buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, saved_state.lines)

          -- Show the saved content first
          vim.api.nvim_win_set_buf(term.window, temp_buf)

          -- Restore cursor position
          if saved_state.cursor then
            local line_count = #saved_state.lines
            local row, col = saved_state.cursor[1], saved_state.cursor[2]

            if row > line_count then row = line_count end
            if row < 1 then row = 1 end

            pcall(vim.api.nvim_win_set_cursor, term.window, {row, col})
          end

          -- Restore view
          if saved_state.view then
            vim.api.nvim_win_call(term.window, function()
              vim.fn.winrestview(saved_state.view)
            end)
          end

          -- After a short delay, switch back to the actual terminal buffer
          vim.defer_fn(function()
            if vim.api.nvim_buf_is_valid(buf) then
              vim.api.nvim_win_set_buf(term.window, buf)
              vim.cmd("startinsert")
            end
            -- Clean up temp buffer
            if vim.api.nvim_buf_is_valid(temp_buf) then
              vim.api.nvim_buf_delete(temp_buf, { force = true })
            end
          end, 1000) -- Show saved content for 1 second
        end)
      end
    end, 200)
  else
    -- Fallback to regular scroll position restore
    restore_scroll_position(term)
  end
end

local function restore_scroll_position(term)
  if term.window and vim.api.nvim_win_is_valid(term.window) and terminal_scroll_positions[term.count] then
    pcall(function()
      local saved_pos = terminal_scroll_positions[term.count]
      vim.api.nvim_win_call(term.window, function()
        vim.fn.winrestview(saved_pos.view)
      end)
      vim.defer_fn(function()
        if term.window and vim.api.nvim_win_is_valid(term.window) then
          local buf = vim.api.nvim_win_get_buf(term.window)
          local line_count = vim.api.nvim_buf_line_count(buf)
          local row, col = saved_pos.cursor[1], saved_pos.cursor[2]

          -- Ensure cursor position is within buffer bounds
          if row > line_count then
            row = line_count
          end
          if row < 1 then
            row = 1
          end

          pcall(vim.api.nvim_win_set_cursor, term.window, {row, col})
        end
      end, 50)
    end)
  end
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

local function find_terminal_by_name(name)
  for i, term in ipairs(terminals) do
    if terminal_names[term.count] == name then
      return i, term
    end
  end
  return nil, nil
end

local function create_title_window(term, terminal_name)
  if term.window and vim.api.nvim_win_is_valid(term.window) then
    vim.schedule(function()
      pcall(function()
        if not term.window or not vim.api.nvim_win_is_valid(term.window) then
          return
        end

        local title_text = "── " .. terminal_name .. " ──"
        local win_width = vim.api.nvim_win_get_width(term.window)
        local centered_title = string.rep(" ", math.max(0, math.floor((win_width - string.len(title_text)) / 2))) .. title_text

        local title_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, { centered_title })

        local title_win = vim.api.nvim_open_win(title_buf, false, {
          relative = "win",
          win = term.window,
          width = win_width,
          height = 1,
          row = 0,
          col = 0,
          style = "minimal",
          border = "none",
          zindex = 1000,
        })

        vim.api.nvim_win_set_option(title_win, "winblend", 0)
        vim.api.nvim_win_set_option(title_win, "winhighlight", "Normal:Title")

        term.title_win = title_win
        term.title_buf = title_buf

        restore_terminal_state(term, term.abduco_session)
      end)
    end)
  end
end

local function cleanup_title_window(term)
  if term.title_win and vim.api.nvim_win_is_valid(term.title_win) then
    vim.api.nvim_win_close(term.title_win, true)
  end
  if term.title_buf and vim.api.nvim_buf_is_valid(term.title_buf) then
    vim.api.nvim_buf_delete(term.title_buf, { force = true })
  end
end

local function new_terminal(name, dir)
  term_count = term_count + 1
  local terminal_dir = dir or get_smart_dir()
  local terminal_name = name or ("Terminal " .. term_count)

  -- Create abduco session name with consistent naming
  local session_name
  if name then
    local clean_name = name:lower():gsub("[%s%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    session_name = "pterm-" .. clean_name
  else
    session_name = "pterm-term-" .. term_count
  end

  -- Check if we should use abduco or fall back to regular terminal
  local use_abduco = abduco.is_available()

  local Terminal = require("toggleterm.terminal").Terminal
  local cmd = nil

  if use_abduco then
    if abduco.session_exists(session_name) then
      -- Attach to existing session
      cmd = abduco.attach_session(session_name, terminal_dir)
    else
      -- Create new session
      cmd = abduco.create_and_attach_session(session_name, terminal_dir)
    end
  end

  local new_term = Terminal:new({
    count = term_count,
    direction = "float",
    dir = use_abduco and nil or terminal_dir,
    cmd = cmd,
    float_opts = {
      border = "none",
      width = function()
        return vim.o.columns
      end,
      height = function()
        return vim.o.lines
      end,
      row = 0,
      col = 0,
      winblend = 3,
    },
    on_open = function(term)
      vim.cmd("startinsert")
      vim.b.terminal_title = terminal_name
      create_title_window(term, terminal_name)

      -- Restore terminal state if this is an abduco session reconnection
      if use_abduco and abduco.session_exists(session_name) then
        restore_terminal_state(term, session_name)
      end
    end,
    on_close = function(term)
      save_terminal_state(term) -- Use the enhanced save function
      cleanup_title_window(term)
    end,
  })

  -- Store session info
  new_term.abduco_session = use_abduco and session_name or nil
  new_term.use_abduco = use_abduco

  table.insert(terminals, new_term)
  terminal_names[term_count] = terminal_name
  current_term = #terminals
  new_term:toggle()
end

local function create_predefined_terminal(name)
  local idx, term = find_terminal_by_name(name)

  -- Check if abduco session exists even if we don't have a terminal object for it
  local clean_name = name:lower():gsub("[%s%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  local session_name = "pterm-" .. clean_name
  local use_abduco = abduco.is_available()

  if term then
    -- Terminal object exists, toggle it
    current_term = idx
    if term:is_open() then
      save_terminal_state(term)
    end
    term:toggle()
    if term:is_open() then
      vim.cmd("startinsert")
      restore_terminal_state(term, term.abduco_session)
    end
  elseif use_abduco and abduco.session_exists(session_name) then
    -- Abduco session exists but no terminal object, create terminal that attaches to existing session
    new_terminal(name, get_smart_dir())
  else
    -- Create new terminal (and session if using abduco)
    new_terminal(name, get_smart_dir())
  end
end

M.create_git_terminal = function()
  create_predefined_terminal("Git")
end

M.create_dev_terminal = function()
  create_predefined_terminal("Dev Server")
end

M.create_test_terminal = function()
  create_predefined_terminal("Tests")
end

M.create_claude_terminal = function()
  local name = "Claude"
  local idx, term = find_terminal_by_name(name)
  local clean_name = name:lower():gsub("[%s%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  local session_name = "pterm-" .. clean_name
  local use_abduco = abduco.is_available()
  local should_send_command = false

  if term then
    -- Terminal object exists, toggle it
    current_term = idx
    if term:is_open() then
      save_terminal_state(term)
    end
    term:toggle()
    if term:is_open() then
      vim.cmd("startinsert")
      restore_terminal_state(term, term.abduco_session)
    end
  elseif use_abduco and abduco.session_exists(session_name) then
    -- Abduco session exists but no terminal object, create terminal that attaches to existing session
    new_terminal(name, get_smart_dir())
  else
    -- Create new terminal (and session if using abduco)
    should_send_command = true
    new_terminal(name, get_smart_dir())
  end

  -- Send claude command only if we created a brand new terminal/session
  -- Note: abduco doesn't support sending commands like zellij, so we use regular terminal send
  if should_send_command then
    vim.defer_fn(function()
      if #terminals > 0 and terminals[current_term] then
        terminals[current_term]:send("claude")
      end
    end, 100)
  end
end

local function run_in_terminal(cmd, name)
  local Terminal = require("toggleterm.terminal").Terminal
  local command_name = name or ("Running: " .. cmd)
  local runner = Terminal:new({
    cmd = cmd,
    direction = "float",
    float_opts = {
      border = "none",
      width = function()
        return vim.o.columns
      end,
      height = function()
        return vim.o.lines
      end,
      row = 0,
      col = 0,
      winblend = 3,
    },
    close_on_exit = false,
    on_open = function(term)
      vim.cmd("startinsert")
      create_title_window(term, command_name)
    end,
  })
  runner:toggle()
end

M.run_project_command = function()
  local cwd = vim.fn.getcwd()

  if vim.fn.filereadable(cwd .. "/package.json") == 1 then
    vim.ui.select(
      { "npm run dev", "npm run build", "npm run test", "npm install", "Custom command" },
      { prompt = "Select npm command:" },
      function(choice)
        if choice == "Custom command" then
          vim.ui.input({ prompt = "Enter command: " }, function(input)
            if input then
              run_in_terminal(input, "Custom")
            end
          end)
        elseif choice then
          run_in_terminal(choice, "NPM")
        end
      end
    )
  elseif vim.fn.filereadable(cwd .. "/Cargo.toml") == 1 then
    vim.ui.select(
      { "cargo run", "cargo build", "cargo test", "cargo check", "Custom command" },
      { prompt = "Select cargo command:" },
      function(choice)
        if choice == "Custom command" then
          vim.ui.input({ prompt = "Enter command: " }, function(input)
            if input then
              run_in_terminal(input, "Custom")
            end
          end)
        elseif choice then
          run_in_terminal(choice, "Cargo")
        end
      end
    )
  else
    vim.ui.input({ prompt = "Enter command to run: " }, function(input)
      if input then
        run_in_terminal(input, "Project")
      end
    end)
  end
end

local function cycle_terminals()
  if #terminals == 0 then
    new_terminal()
    return
  end

  if terminals[current_term] and terminals[current_term]:is_open() then
    save_terminal_state(terminals[current_term])
    terminals[current_term]:close()
  end

  current_term = current_term % #terminals + 1

  terminals[current_term]:toggle()
  if terminals[current_term]:is_open() then
    vim.cmd("startinsert")
    restore_terminal_state(terminals[current_term], terminals[current_term].abduco_session)
  end
end

local function cycle_backwards()
  if #terminals == 0 then
    new_terminal()
    return
  end

  if terminals[current_term] and terminals[current_term]:is_open() then
    save_terminal_state(terminals[current_term])
    terminals[current_term]:close()
  end

  current_term = current_term - 1
  if current_term < 1 then
    current_term = #terminals
  end

  terminals[current_term]:toggle()
  if terminals[current_term]:is_open() then
    restore_terminal_state(terminals[current_term], terminals[current_term].abduco_session)
  end
end

M.toggle_current_terminal = function()
  if #terminals == 0 then
    new_terminal()
    return
  end

  local term = terminals[current_term]

  if term:is_open() then
    save_scroll_position(term)
  end

  term:toggle()

  if term:is_open() then
    vim.cmd("startinsert")
    restore_scroll_position(term)
  end
end

M.close_current_terminal = function()
  if #terminals == 0 then
    return
  end

  if terminals[current_term] then
    local old_count = terminals[current_term].count
    local session_name = terminals[current_term].abduco_session

    terminals[current_term]:close()

    -- Note: We keep abduco sessions running for persistence
    -- Users can manually kill sessions with :lua require('pterm').kill_abduco_session('session-name')

    table.remove(terminals, current_term)
    if terminal_names[old_count] then
      terminal_names[old_count] = nil
    end
    if terminal_scroll_positions[old_count] then
      terminal_scroll_positions[old_count] = nil
    end

    if #terminals > 0 then
      if current_term > #terminals then
        current_term = #terminals
      end

      terminals[current_term]:toggle()
      if terminals[current_term]:is_open() then
        vim.cmd("startinsert")
        restore_terminal_state(terminals[current_term], terminals[current_term].abduco_session)
      end
    else
      current_term = 1
      term_count = 0
    end
  end
end

M.show_terminal_info = function()
  if #terminals == 0 then
    print("No terminals open")
    return
  end

  local info = "Terminals (" .. #terminals .. "):\n"
  for i, term in ipairs(terminals) do
    local name = terminal_names[term.count] or "Terminal " .. i
    local current_marker = (i == current_term) and " (current)" or ""
    local session_info = ""
    if term.use_abduco and term.abduco_session then
      session_info = " [abduco: " .. term.abduco_session .. "]"
    end
    info = info .. "  " .. i .. ": " .. name .. current_marker .. session_info .. "\n"
  end
  print(info)
end

M.send_line_to_terminal = function()
  if #terminals == 0 then
    new_terminal()
  end

  local line = vim.fn.getline(".")
  local term = terminals[current_term]

  -- Send to terminal (abduco sessions are handled through regular terminal interface)
  term:send(line .. "\r")

  if not term:is_open() then
    term:toggle()
    restore_scroll_position(term)
  end
end

M.send_selection_to_terminal = function()
  if #terminals == 0 then
    new_terminal()
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
  local term = terminals[current_term]

  -- Send to terminal (abduco sessions are handled through regular terminal interface)
  term:send(text .. "\r")

  if not term:is_open() then
    term:toggle()
    restore_scroll_position(term)
  end
end

M.rename_terminal = function()
  if #terminals == 0 then
    print("No terminal to rename")
    return
  end

  vim.ui.input({
    prompt = "New terminal name: ",
    default = terminal_names[terminals[current_term].count] or "",
  }, function(input)
    if input then
      terminal_names[terminals[current_term].count] = input

      local term = terminals[current_term]
      if term and term.window and vim.api.nvim_win_is_valid(term.window) then
        vim.schedule(function()
          pcall(function()
            if not term.window or not vim.api.nvim_win_is_valid(term.window) then
              return
            end

            local title_text = "── " .. input .. " ──"
            local win_width = vim.api.nvim_win_get_width(term.window)
            local centered_title = string.rep(" ", math.max(0, math.floor((win_width - string.len(title_text)) / 2))) .. title_text

            if term.title_win and vim.api.nvim_win_is_valid(term.title_win) and term.title_buf and vim.api.nvim_buf_is_valid(term.title_buf) then
              vim.api.nvim_buf_set_lines(term.title_buf, 0, -1, false, { centered_title })
            end
          end)
        end)
      end

      print("Terminal renamed to: " .. input)
    end
  end)
end

M.kill_all_terminals = function()
  -- Kill all terminal instances
  for _, term in ipairs(terminals) do
    term:shutdown()
  end
  terminals = {}
  terminal_names = {}
  terminal_scroll_positions = {}
  terminal_buffers = {} -- Clear all stored terminal buffers
  current_term = 1
  term_count = 0

  -- Kill all pterm abduco sessions
  if abduco.is_available() then
    local all_sessions = abduco.list_sessions()
    local killed_count = 0

    for _, session in ipairs(all_sessions) do
      if session:match("^pterm%-") then
        if abduco.kill_session(session) then
          -- Clean up stored terminal buffer for this session
          terminal_buffers[session] = nil
          killed_count = killed_count + 1
        end
      end
    end

    if killed_count > 0 then
      print("All terminals and " .. killed_count .. " abduco sessions killed")
    else
      print("All terminals killed (no abduco sessions found)")
    end
  else
    print("All terminals killed")
  end
end

-- Utility function to kill a specific abduco session
M.kill_abduco_session = function(session_name)
  if abduco.is_available() then
    local success = abduco.kill_session(session_name)
    if success then
      -- Clean up stored terminal buffer for this session
      terminal_buffers[session_name] = nil
      print("Killed abduco session: " .. session_name)
    else
      print("Failed to kill abduco session: " .. session_name)
    end
  else
    print("abduco not available")
  end
end

-- Utility function to list all pterm abduco sessions
M.list_abduco_sessions = function()
  if not abduco.is_available() then
    print("abduco not available")
    return
  end

  local all_sessions = abduco.list_sessions()
  local pterm_sessions = {}

  for _, session in ipairs(all_sessions) do
    if session:match("^pterm%-") then
      table.insert(pterm_sessions, session)
    end
  end

  if #pterm_sessions == 0 then
    print("No pterm abduco sessions found")
  else
    print("Pterm abduco sessions:")
    for _, session in ipairs(pterm_sessions) do
      print("  " .. session)
    end
  end
end

-- Kill all pterm abduco sessions
M.kill_all_abduco_sessions = function()
  if not abduco.is_available() then
    print("abduco not available")
    return
  end

  local all_sessions = abduco.list_sessions()
  local killed_count = 0

  for _, session in ipairs(all_sessions) do
    if session:match("^pterm%-") then
      if abduco.kill_session(session) then
        -- Clean up stored terminal buffer for this session
        terminal_buffers[session] = nil
        killed_count = killed_count + 1
      end
    end
  end

  if killed_count > 0 then
    print("Killed " .. killed_count .. " pterm abduco sessions")
  else
    print("No pterm abduco sessions to kill")
  end
end

M.pick_terminal = function()
  if #terminals == 0 then
    print("No terminals available")
    return
  end

  local choices = {}
  for i, _ in ipairs(terminals) do
    local name = terminal_names[terminals[i].count] or ("Terminal " .. i)
    local status = terminals[i]:is_open() and " (open)" or " (closed)"
    table.insert(choices, i .. ": " .. name .. status)
  end

  vim.ui.select(choices, {
    prompt = "Select terminal:",
  }, function(choice)
    if choice then
      local term_num = tonumber(string.match(choice, "^(%d+):"))
      if term_num then
        if terminals[current_term] and terminals[current_term]:is_open() then
          save_terminal_state(terminals[current_term])
        end

        current_term = term_num
        terminals[current_term]:toggle()
        if terminals[current_term]:is_open() then
          vim.cmd("startinsert")
          restore_terminal_state(terminals[current_term], terminals[current_term].abduco_session)
        end
      end
    end
  end)
end

M.new_terminal = new_terminal
M.cycle_terminals = cycle_terminals
M.cycle_backwards = cycle_backwards

M.setup = function(opts)
  opts = opts or {}

  if not pcall(require, "toggleterm") then
    vim.notify("pterm requires toggleterm.nvim to be installed", vim.log.levels.ERROR)
    return
  end

  -- Prevent double setup
  if vim.g.pterm_setup_called then
    return
  end
  vim.g.pterm_setup_called = true

  -- Set up toggleterm with the proper configuration
  local toggleterm_opts = {
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
      width = function()
        return vim.o.columns
      end,
      height = function()
        return vim.o.lines
      end,
      winblend = 3,
      highlights = {
        border = "FloatBorder",
        background = "Normal",
      },
    },
  }

  -- Merge user options with defaults
  if opts.toggleterm then
    toggleterm_opts = vim.tbl_deep_extend("force", toggleterm_opts, opts.toggleterm)
  end

  require("toggleterm").setup(toggleterm_opts)

  local map = vim.keymap.set

  map({ "n", "i", "t" }, "<M-t>", function() new_terminal() end, { desc = "New terminal tab" })
  map({ "n", "i", "t" }, "<D-t>", function() new_terminal() end, { desc = "New terminal tab (Cmd)" })
  map({ "n", "i", "t" }, "<C-Tab>", cycle_terminals, { desc = "Cycle terminal tabs" })
  map({ "n", "i", "t" }, "<C-S-Tab>", cycle_backwards, { desc = "Cycle terminal tabs backwards" })
  map({ "n", "i", "t" }, "<C-\\>", M.toggle_current_terminal, { desc = "Toggle current terminal" })

  map("t", "<C-w>", M.close_current_terminal, { desc = "Close current terminal and switch to next" })
  map("t", "<D-w>", M.close_current_terminal, { desc = "Close current terminal and switch to next" })
  map("t", "<M-w>", M.close_current_terminal, { desc = "Close current terminal and switch to next" })

  -- Fix paste in terminal mode with sanitization
  map("t", "<D-v>", function()
    local clipboard = vim.fn.getreg("+")
    if not clipboard or clipboard == "" then
      return
    end

    -- Strict sanitization - only allow common coding characters
    local sanitized = clipboard
      -- Keep only printable ASCII, common whitespace, and newlines
      -- This removes problematic Unicode separators and control characters
      :gsub("[^\32-\126\9\10\13]", "")
      -- Normalize line endings to Unix style
      :gsub("\r\n", "\n")
      :gsub("\r", "\n")

    -- Limit length for safety (increased from 5000 to 50000 for larger pastes)
    if #sanitized > 50000 then
      sanitized = sanitized:sub(1, 50000)
    end

    if sanitized == "" then
      return
    end

    -- Send to current terminal - use simple, reliable method
    if #terminals > 0 and terminals[current_term] then
      local term = terminals[current_term]

      -- Ensure terminal is open
      if not term:is_open() then
        term:toggle()
        -- Wait a bit for terminal to open
        vim.defer_fn(function()
          if term:is_open() then
            term:send(sanitized)
          end
        end, 100)
      else
        term:send(sanitized)
      end
    end
  end, { desc = "Paste clipboard (sanitized)" })

  map("t", "<C-h>", "<C-\\><C-N><C-w>h", { desc = "Terminal left window nav" })
  map("t", "<C-j>", "<C-\\><C-N><C-w>j", { desc = "Terminal down window nav" })
  map("t", "<C-k>", "<C-\\><C-N><C-w>k", { desc = "Terminal up window nav" })
  map("t", "<C-l>", "<C-\\><C-N><C-w>l", { desc = "Terminal right window nav" })
  map("t", "<C-x>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

  map("n", "<leader>ti", M.show_terminal_info, { desc = "Terminal info" })
  map("n", "<leader>tg", M.create_git_terminal, { desc = "Git terminal" })
  map("n", "<leader>td", M.create_dev_terminal, { desc = "Dev server terminal" })
  map("n", "<leader>tt", M.create_test_terminal, { desc = "Test terminal" })
  map("n", "<leader>tc", M.create_claude_terminal, { desc = "Claude terminal" })
  map("n", "<leader>tr", M.run_project_command, { desc = "Run project command" })
  map("n", "<leader>ts", M.send_line_to_terminal, { desc = "Send line to terminal" })
  map("v", "<leader>ts", M.send_selection_to_terminal, { desc = "Send selection to terminal" })
  map("n", "<leader>tn", M.rename_terminal, { desc = "Rename terminal" })
  map("n", "<leader>tK", M.kill_all_terminals, { desc = "Kill all terminals" })
  map("n", "<leader>tp", M.pick_terminal, { desc = "Pick terminal" })
  map("n", "<leader>tX", M.kill_all_abduco_sessions, { desc = "Kill all abduco sessions" })
end

return M