-- Python REPL integration for Neovim
local M = {}
local curl = require('plenary.curl')

M.config = {
  url = 'http://localhost:5000/execute',
  show_output = true,  -- Show execution output
  split_direction = 'vertical', -- 'vertical' or 'horizontal'
  output_buffer_name = 'PythonOutput',
  timeout = 10000, -- 10 seconds
}

function M.setup(opts)
  M.config = vim.tbl_extend('force', M.config, opts or {})
end

function M.create_output_buffer()
  if M.output_buffer and vim.api.nvim_buf_is_valid(M.output_buffer) then
    return M.output_buffer
  end
  
  -- Create a new buffer
  M.output_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M.output_buffer, M.config.output_buffer_name)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(M.output_buffer, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(M.output_buffer, 'swapfile', false)
  vim.api.nvim_buf_set_option(M.output_buffer, 'filetype', 'python-output')
  
  return M.output_buffer
end

function M.display_output(output)
  if not M.config.show_output then
    return
  end
  
  local buffer = M.create_output_buffer()
  local lines = vim.split(output, '\n')
  
  -- Update buffer contents
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  
  -- Find window with buffer or create new split
  local win_id = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buffer then
      win_id = win
      break
    end
  end
  
  if not win_id then
    -- Create a new split
    local cmd = M.config.split_direction == 'vertical' 
      and 'vsplit' 
      or 'split'
    
    vim.cmd(cmd)
    win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win_id, buffer)
    vim.cmd('wincmd p') -- Go back to previous window
  end
end

function M.send_to_repl(code)
  if type(code) == 'table' then
    code = table.concat(code, '\n')
  end
  
  local response = curl.post(M.config.url, {
    body = vim.fn.json_encode({code = code}),
    headers = {
      content_type = 'application/json',
    },
    timeout = M.config.timeout,
  })

  local success, result = pcall(vim.fn.json_decode, response.body)
  
  if not success then
    vim.notify("Error parsing REPL response: " .. response.body, vim.log.levels.ERROR)
    return
  end
  
  if result.error then
    vim.notify("Python error: " .. result.error, vim.log.levels.ERROR)
    M.display_output(result.error)
  elseif result.output then
    vim.notify("Python executed successfully", vim.log.levels.INFO)
    M.display_output(result.output)
  end
  
  return result
end

function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  if vim.fn.mode() == 'V' then
    if srow > erow then
      return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
    else
      return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    end
  end

  if vim.fn.mode() == 'v' then
    if srow < erow or (srow == erow and scol <= ecol) then
      return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
    else
      return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
    end
  end
  
  -- Get current line if not in visual mode
  if vim.fn.mode() ~= 'v' and vim.fn.mode() ~= 'V' then
    local current_line = vim.api.nvim_get_current_line()
    return {current_line}
  end
  
  return {}
end

function M.run_selected_lines()
  local code = M.get_visual_selection()
  if #code > 0 then
    M.send_to_repl(code)
  else
    vim.notify("No code selected", vim.log.levels.WARN)
  end
end

function M.run_buffer()
  local current_buffer = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, -1, false)
  M.send_to_repl(lines)
end

return M
