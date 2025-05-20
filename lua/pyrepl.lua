local M = {}
local curl = require('plenary.curl')

M.config = {
  url = 'http://localhost:5000/execute',
  display_results = true,
  result_window_size = 10,
  float_opts = {
    relative = 'editor',
    width = 80,
    height = 20,
    border = 'rounded',
  }
}

function M.setup(opts)
  M.config = vim.tbl_extend('force', M.config, opts or {})
end

function M.create_float_window()
  local width = M.config.float_opts.width
  local height = M.config.float_opts.height
  local bufnr = vim.api.nvim_create_buf(false, true)
  
  local win_opts = vim.tbl_extend('force', M.config.float_opts, {
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
  })
  
  local winid = vim.api.nvim_open_win(bufnr, true, win_opts)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
  
  -- Add keymaps for navigation
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', ':q<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', ':q<CR>', { noremap = true, silent = true })
  
  return bufnr, winid
end

function M.display_result(result)
  if result and M.config.display_results then
    local bufnr, _ = M.create_float_window()
    
    -- Format the result for display
    local display_text = {}
    if type(result) == "table" then
      table.insert(display_text, "Result:")
      
      for k, v in pairs(result) do
        if type(v) == "table" then
          table.insert(display_text, k .. ": " .. vim.inspect(v))
        else
          table.insert(display_text, k .. ": " .. tostring(v))
        end
      end
    else
      table.insert(display_text, "Result: " .. tostring(result))
    end
    
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, display_text)
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  end
end

function M.send_to_repl(code)
  local response = curl.post(M.config.url, {
    body = vim.fn.json_encode({code = code}),
    headers = {
      content_type = 'application/json',
    },
  })
  
  -- Handle the response
  local success, result = pcall(vim.fn.json_decode, response.body)
  
  if success then
    M.display_result(result)
    return result
  else
    vim.api.nvim_err_writeln("Failed to parse response: " .. response.body)
    return nil
  end
end

function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos('v'))
  local _, erow, ecol = unpack(vim.fn.getpos('.'))

  if vim.fn.mode() == 'V' then -- Visual line mode
    if srow > erow then
      return table.concat(vim.api.nvim_buf_get_lines(0, erow - 1, srow, true), '\n')
    else
      return table.concat(vim.api.nvim_buf_get_lines(0, srow - 1, erow, true), '\n')
    end
  end

  if vim.fn.mode() == 'v' then -- Visual character mode
    if srow < erow or (srow == erow and scol <= ecol) then
      return table.concat(vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {}), '\n')
    else
      return table.concat(vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {}), '\n')
    end
  end

  if vim.fn.mode() == '\22' then -- Visual block mode
    local lines = {}
    if srow > erow then
      srow, erow = erow, srow
    end
    if scol > ecol then
      scol, ecol = ecol, scol
    end
    for i = srow, erow do
      local line_length = #vim.api.nvim_buf_get_lines(0, i - 1, i, true)[1]
      table.insert(lines, vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, line_length), i - 1, math.min(ecol, line_length), {})[1])
    end
    return table.concat(lines, '\n')
  end
  
  return nil
end

function M.run_selected_lines()
  local code = M.get_visual_selection()
  if code then
    return M.send_to_repl(code)
  else
    vim.api.nvim_err_writeln('No text selected')
    return nil
  end
end

function M.run_current_line()
  local line = vim.api.nvim_get_current_line()
  if line and line ~= "" then
    return M.send_to_repl(line)
  else
    vim.api.nvim_err_writeln('Current line is empty')
    return nil
  end
end

function M.run_current_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local code = table.concat(lines, '\n')
  if code and code ~= "" then
    return M.send_to_repl(code)
  else
    vim.api.nvim_err_writeln('Buffer is empty')
    return nil
  end
end

-- Setup keymaps
function M.setup_keymaps()
  vim.keymap.set('v', '<leader>r', function()
    M.run_selected_lines()
  end, { desc = 'Run selected code in REPL' })
  
  vim.keymap.set('n', '<leader>rr', function()
    M.run_current_line()
  end, { desc = 'Run current line in REPL' })
  
  vim.keymap.set('n', '<leader>rb', function()
    M.run_current_buffer()
  end, { desc = 'Run entire buffer in REPL' })
end

return M
