-- TUI Invoker — responsible for materialising the engine dashboard inside Neovim.
-- Flow: create_buffer → open_buffer → open_dashboard_terminal

local M = {}

--- Creates a new scratch buffer for the vimstar dashboard.
--- Should configure buffer-local options (buftype=nofile, unlisted, etc.) and
--- store the buffer handle for subsequent steps.
---@return integer bufnr the newly created buffer handle
local function create_buffer()
  -- TODO: create a named scratch buffer with appropriate buffer-local options
  local bufnr = vim.api.nvim_create_buf(false, true)
  return bufnr
end

--- Opens the given buffer in a new split/window according to user preferences.
--- Should handle layout options (vertical split, floating window, tab, etc.).
---@param bufnr integer buffer handle returned by create_buffer
---@return integer winnr the window that now displays the buffer
local function open_buffer(bufnr)
  -- TODO: decide on window layout and open bufnr inside it
  vim.api.nvim_set_current_buf(bufnr)
  local winnr = vim.api.nvim_get_current_win()
  return winnr
end

--- Spawns the external engine dashboard process inside a :terminal buffer.
--- Should call vim.fn.termopen (or vim.api.nvim_open_term) with the engine
--- binary, forwarding any relevant arguments.
---@param bufnr integer buffer that will host the terminal channel
---@param args  string  optional CLI arguments for the dashboard binary
local function open_dashboard_terminal(bufnr, args)
  -- TODO: replace the placeholder command with the real engine dashboard binary
  local cmd = "echo 'vimstar dashboard placeholder'"
  if args and args ~= "" then
    cmd = cmd .. " " .. args
  end
  vim.fn.termopen(cmd, {
    on_exit = function(_, exit_code, _)
      -- TODO: handle clean/unclean dashboard exit
      _ = exit_code
    end,
  })
end

--- Public entry point.  Orchestrates the three-step TUI creation sequence.
---@param args string forwarded from the :Vimstar user command
function M.invoke(args)
  local bufnr = create_buffer()
  open_buffer(bufnr)
  open_dashboard_terminal(bufnr, args)
end

return M
