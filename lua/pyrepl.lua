local M = {}
local curl = require('plenary.curl')

-- Default configuration
M.config = {
  url = 'http://localhost:5000/execute',
  show_response = true,  -- Whether to display REPL response in a float window
  float_opts = {         -- Options for the float window
    width = 80,
    height = 20,
    border = 'rounded',
  }
}

-- Setup function to merge user config with defaults
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

-- Creates a floating window to show REPL output
function M.show_output_in_float(output)
  if not M.config.show_response then return end
  
  local buf = vim.api.nvim_create_buf(false, true)
  local width = M.config.float_opts.width
  local height = M.config.float_opts.height
  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = M.config.float_opts.border,
    title = " REPL Output ",
  }
  
  -- Set buffer content
  if type(output) == "table" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, "\n"))
  end
  
  -- Set buffer filetype for syntax highlighting
  vim.api.nvim_buf_set_option(buf, 'filetype', 'python')
  
  -- Create window and set up autoclose
  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
  
  vim.api.nvim_create_autocmd({"BufLeave"}, {
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
    once = true,
  })
  
  return win
end

-- Send code to Python REPL
function M.send_to_repl(code)
  vim.notify("Sending code to REPL...", vim.log.levels.INFO)
  
  local response = curl.post(M.config.url, {
    body = vim.fn.json_encode({code = code}),
    headers = {
      content_type = 'application/json',
    },
    timeout = 10000,  -- 10 second timeout
  })

  if response.status ~= 200 then
    vim.notify("REPL request failed: " .. (response.body or "Unknown error"), vim.log.levels.ERROR)
    return
  end

  local success, result = pcall(vim.fn.json_decode, response.body)
  if not success then
    vim.notify("Failed to parse REPL response", vim.log.levels.ERROR)
    return
  end
  
  if result.output then
    M.show_output_in_float(result.output)
  elseif result.error then
    vim.notify("REPL error: " .. result.error, vim.log.levels.ERROR)
  end
  
  return result
end

-- Get visual selection
function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos('v'))
  local _, erow, ecol = unpack(vim.fn.getpos('.'))
  local lines = {}

  if vim.fn.mode() == 'V' then
    if srow > erow then
      lines = vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
    else
      lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    end
  elseif vim.fn.mode() == 'v' then
    if srow < erow or (srow == erow and scol <= ecol) then
      lines = vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
    else
      lines = vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
    end
  else
    return nil
  end
  
  return lines
end

-- Run selected lines in REPL
function M.run_selected_lines()
  local code = M.get_visual_selection()
  if not code or #code == 0 then
    vim.notify("No code selected", vim.log.levels.WARN)
    return
  end
  
  M.send_to_repl(table.concat(code, "\n"))
end

-- Run current buffer in REPL
function M.run_current_buffer()
  local code = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  M.send_to_repl(table.concat(code, "\n"))
end

-- Run current line in REPL
function M.run_current_line()
  local line = vim.api.nvim_get_current_line()
  M.send_to_repl(line)
end

return M
