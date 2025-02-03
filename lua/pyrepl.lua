local M = {}
local curl = require('plenary.curl')

M.config = {
  url = 'http://localhost:5001/execute'
}

function M.setup(opts)
  M.config = vim.tbl_extend('force', M.config, opts or {})
end

function M.send_to_repl(code)
  print("Sending code to REPL: " .. code)  -- Debug log
  local success, response = pcall(function()
    return curl.post(M.config.url, {
      body = vim.fn.json_encode({code = code}),
      headers = {
        content_type = 'application/json',
      },
    })
  end)

  if not success then
    vim.api.nvim_err_writeln("Failed to connect to REPL server")
    return
  end

  print("Response status: " .. response.status)  -- Debug log

  if response.status ~= 200 then
    vim.api.nvim_err_writeln("Error: " .. response.status .. " - " .. response.body)
    return
  end

  local result = vim.fn.json_decode(response.body)
  if not result then
    vim.api.nvim_err_writeln("Failed to decode response")
    return
  end

  print("Result from REPL: " .. vim.inspect(result))  -- Debug log for result
end

function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow = erow, srow
    scol, ecol = ecol, scol
  end

  if vim.fn.mode() == 'V' then
    return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
  elseif vim.fn.mode() == 'v' then
    return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
  end
  return ''  -- Return an empty string if no selection
end

function M.run_selected_lines()
  local code = M.get_visual_selection()
  if code ~= '' then
    M.send_to_repl(code)
  else
    vim.api.nvim_err_writeln("No valid code selected")
  end
end

return M
