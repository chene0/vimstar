-- Main module. Wires together the TUI invoker, mutation logger, and IPC layer.
-- Called once during plugin load; returns the public API consumed by plugin/.

local tui = require("vimstar.tui")
local mutation_logger = require("vimstar.mutation_logger")
local ipc = require("vimstar.ipc")

local M = {}

--- Called once when the plugin loads.
--- Should initialise IPC, attach buffer hooks, and register the on_key listener.
function M.setup(opts)
  opts = opts or {}

  ipc.start()
  mutation_logger.attach_hooks()
end

--- Entry point for the :Vimstar user command.
--- Delegates to the TUI invoker to create and open the dashboard buffer.
---@param args string optional arguments forwarded from the user command
function M.open_dashboard(args)
  tui.invoke(args)
end

return M
