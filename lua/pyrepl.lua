local M = {}
local curl = require('plenary.curl')

M.config = {
  url = 'http://localhost:5000/execute',
  show_result = true,  -- Toggle to show/hide results
  timeout = 10000      -- Timeout in milliseconds
}

function M.setup(opts)
  M.config = vim.tbl_extend('force', M.config, opts or {})
end

function M.send_to_repl(code)
  local response = curl.post(M.config.url, {
    body = vim.fn.json_encode({code = code}),
    headers = {
      content_type = 'application/json',
    },
    timeout = M.config.timeout
  })

  if response.status ~= 200 then
    vim.notify("Error sending code to REPL: " .. (response.body or "Unknown error"), vim.log.levels.ERROR)
    return
  end

  local ok, result = pcall(vim.fn.json_decode, response.body)
  if not ok then
    vim.notify("Failed to parse REPL response", vim.log.levels.ERROR)
    return
  end

  if M.config.show_result and result and result.output then
    -- Create a floating window to show the result
    M.show_result(result.output)
  end
  
  return result
end

function M.show_result(output)
  -- Create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer content
  local lines = vim.split(output, '\n')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Calculate dimensions
  local width = math.min(#(lines[1] or ""), 80)
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.min(width, 80)
  local height = math.min(#lines, 15)
  
  -- Calculate position
  local win_width = vim.api.nvim_get_option("columns")
  local win_height = vim.api.nvim_get_option("lines")
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)
  
  -- Set window options
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded"
  }
  
  -- Open the window
  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  
  -- Close on any key press
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
end

function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos('v'))
  local _, erow, ecol = unpack(vim.fn.getpos('.'))

  if vim.fn.mode() == 'V' then
    -- Line-wise visual mode
    if srow > erow then
      return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
    else
      return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    end
  end

  if vim.fn.mode() == 'v' then
    -- Character-wise visual mode
    if srow < erow or (srow == erow and scol <= ecol) then
      return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
    else
      return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
    end
  end
  
  if vim.fn.mode() == '\22' then
    -- Block-wise visual mode
    local lines = {}
    if srow > erow then
      srow, erow = erow, srow
    end
    if scol > ecol then
      scol, ecol = ecol, scol
    end
    for i = srow, erow do
      table.insert(lines, vim.api.nvim_buf_get_text(0, i - 1, scol - 1, i - 1, ecol, {})[1])
    end
    return lines
  end
  
  return {}
end

function M.run_selected_lines()
  local code = M.get_visual_selection()
  if type(code) == "table" then
    code = table.concat(code, "\n")
  end
  
  if code and code ~= "" then
    M.send_to_repl(code)
  else
    vim.notify("No code selected", vim.log.levels.WARN)
  end
end

return M
