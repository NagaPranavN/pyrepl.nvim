local M = {}
local curl = require('plenary.curl')
local Job = require('plenary.job')

M.config = {
  url = 'http://localhost:5000/execute',
  timeout = 10000,         -- Timeout in milliseconds
  show_output = true,      -- Whether to show output in a split
  output_buffer = nil,     -- Buffer to show output in
  enable_streaming = false -- Enable streaming response
}

-- Setup function with user config
function M.setup(opts)
  M.config = vim.tbl_extend('force', M.config, opts or {})
  
  -- Create output buffer if show_output is true
  if M.config.show_output and not M.config.output_buffer then
    vim.cmd('botright new')
    vim.cmd('setlocal buftype=nofile')
    vim.cmd('setlocal bufhidden=hide')
    vim.cmd('setlocal noswapfile')
    vim.cmd('setlocal nobuflisted')
    vim.cmd('setlocal nowrap')
    vim.cmd('file REPL-Output')
    M.config.output_buffer = vim.api.nvim_get_current_buf()
    vim.cmd('wincmd p') -- Go back to previous window
  end
end

-- Handle response display
function M.display_output(result)
  if not M.config.show_output then
    return
  end
  
  -- Ensure buffer exists
  if not M.config.output_buffer or not vim.api.nvim_buf_is_valid(M.config.output_buffer) then
    M.setup({show_output = true})
  end
  
  local output
  if type(result) == "table" then
    if result.error then
      output = "ERROR: " .. result.error
    elseif result.output then
      output = result.output
    else
      output = vim.inspect(result)
    end
  else
    output = tostring(result or "No output")
  end
  
  -- Split output into lines
  local lines = vim.split(output, "\n")
  
  -- Append to buffer
  vim.api.nvim_buf_set_lines(
    M.config.output_buffer,
    -1,
    -1,
    false,
    lines
  )
  
  -- Scroll to bottom
  local output_windows = vim.fn.win_findbuf(M.config.output_buffer)
  for _, win in ipairs(output_windows) do
    vim.api.nvim_win_set_cursor(win, {vim.api.nvim_buf_line_count(M.config.output_buffer), 0})
  end
end

-- Send code to REPL with better error handling
function M.send_to_repl(code)
  if type(code) == "table" then
    code = table.concat(code, "\n")
  end
  
  if M.config.enable_streaming then
    return M.stream_to_repl(code)
  end
  
  local response = curl.post(M.config.url, {
    body = vim.fn.json_encode({code = code}),
    headers = {
      content_type = 'application/json',
    },
    timeout = M.config.timeout
  })
  
  local result
  local success, decoded = pcall(vim.fn.json_decode, response.body)
  
  if success then
    result = decoded
  else
    result = {
      error = "Failed to decode response: " .. (response.body or "empty response"),
    }
  end
  
  M.display_output(result)
  return result
end

-- Stream to REPL for live updates
function M.stream_to_repl(code)
  local args = {
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-d', vim.fn.json_encode({code = code, stream = true}),
    M.config.url
  }
  
  local current_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, data)
      if data and #data > 0 then
        local success, json = pcall(vim.fn.json_decode, data)
        if success and json then
          M.display_output(json)
        end
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        M.display_output({error = data})
      end
    end,
    on_exit = function(_, _)
      M.display_output({output = "Execution complete"})
    end,
  }
  
  current_job:start()
  return current_job
end

-- Get visual selection with better handling
function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos('v'))
  local _, erow, ecol = unpack(vim.fn.getpos('.'))
  
  -- Handle line-wise visual mode
  if vim.fn.mode() == 'V' then
    if srow > erow then
      srow, erow = erow, srow
    end
    return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
  end
  
  -- Handle character-wise visual mode
  if vim.fn.mode() == 'v' then
    -- Normalize positions if selection is backwards
    if srow > erow or (srow == erow and scol > ecol) then
      srow, erow, scol, ecol = erow, srow, ecol, scol
    end
    
    if srow == erow then
      -- Single line selection
      local line = vim.api.nvim_buf_get_lines(0, srow - 1, srow, true)[1]
      return {line:sub(scol, ecol)}
    else
      -- Multi-line selection
      local lines = {}
      
      -- First line (partial)
      local first_line = vim.api.nvim_buf_get_lines(0, srow - 1, srow, true)[1]
      table.insert(lines, first_line:sub(scol))
      
      -- Middle lines (full)
      if erow - srow > 1 then
        local middle_lines = vim.api.nvim_buf_get_lines(0, srow, erow - 1, true)
        for _, line in ipairs(middle_lines) do
          table.insert(lines, line)
        end
      end
      
      -- Last line (partial)
      local last_line = vim.api.nvim_buf_get_lines(0, erow - 1, erow, true)[1]
      table.insert(lines, last_line:sub(1, ecol))
      
      return lines
    end
  end
  
  -- Handle block-wise visual mode
  if vim.fn.mode() == '\22' then -- ^V (block visual)
    local lines = {}
    if srow > erow then
      srow, erow = erow, srow
    end
    if scol > ecol then
      scol, ecol = ecol, scol
    end
    
    for i = srow, erow do
      local line = vim.api.nvim_buf_get_lines(0, i - 1, i, true)[1]
      if #line >= scol then
        local segment = line:sub(scol, math.min(ecol, #line))
        table.insert(lines, segment)
      else
        table.insert(lines, "")
      end
    end
    
    return lines
  end
  
  return {}
end

-- Run selected lines with visual feedback
function M.run_selected_lines()
  local code = M.get_visual_selection()
  
  if #code == 0 then
    vim.api.nvim_err_writeln("No text selected!")
    return
  end
  
  -- Visual feedback - flash selection
  vim.cmd([[normal! `<v`>]])
  vim.cmd([[redraw]])
  vim.defer_fn(function()
    vim.cmd([[normal! esc]])
    vim.defer_fn(function()
      M.send_to_repl(code)
    end, 100)
  end, 100)
end

-- Run current line
function M.run_current_line()
  local line = vim.api.nvim_get_current_line()
  return M.send_to_repl(line)
end

-- Run entire buffer
function M.run_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return M.send_to_repl(lines)
end

-- Clear output buffer
function M.clear_output()
  if M.config.output_buffer and vim.api.nvim_buf_is_valid(M.config.output_buffer) then
    vim.api.nvim_buf_set_lines(M.config.output_buffer, 0, -1, false, {})
  end
end

-- Toggle output window
function M.toggle_output_window()
  if not M.config.output_buffer or not vim.api.nvim_buf_is_valid(M.config.output_buffer) then
    M.setup({show_output = true})
    return
  end
  
  local output_windows = vim.fn.win_findbuf(M.config.output_buffer)
  if #output_windows > 0 then
    -- Window exists, close it
    for _, win in ipairs(output_windows) do
      vim.api.nvim_win_close(win, false)
    end
  else
    -- Window doesn't exist, open it
    vim.cmd('botright split')
    vim.api.nvim_win_set_buf(0, M.config.output_buffer)
    vim.cmd('wincmd p') -- Go back to previous window
  end
end

return M
