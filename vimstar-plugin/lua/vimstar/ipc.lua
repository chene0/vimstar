-- IPC layer — owns the long-running engine job and exposes send/stop helpers.
-- The job is spawned with vim.fn.jobstart; actual serialisation protocol
-- (msgpack, JSON-RPC, etc.) is not yet implemented.

local M = {}

-- Handle returned by vim.fn.jobstart; 0 / -1 means the job is not running.
local _job_id = 0

--- Spawns the external vimstar engine process via vim.fn.jobstart.
--- Should configure stdin/stdout/stderr handlers for the chosen IPC protocol.
--- Called once from vimstar.setup().
function M.start()
  if _job_id > 0 then
    -- Already running — nothing to do.
    return
  end

  -- TODO: replace placeholder with the real engine binary path / invocation
  local cmd = { "echo", "vimstar-engine-placeholder" }

  _job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      -- TODO: deserialise incoming messages from the engine and dispatch them
      _ = data
    end,
    on_stderr = function(_, data, _)
      -- TODO: surface engine stderr as vim.notify warnings / errors
      _ = data
    end,
    on_exit = function(_, exit_code, _)
      -- TODO: handle unexpected engine exit (restart policy, user notification)
      _job_id = 0
      _ = exit_code
    end,
    stdin = "pipe",
    stdout_buffered = false,
    stderr_buffered = false,
  })

  if _job_id == 0 then
    vim.notify("vimstar: engine command not executable", vim.log.levels.ERROR)
  elseif _job_id == -1 then
    vim.notify("vimstar: engine command is invalid", vim.log.levels.ERROR)
  end
end

--- Serialises an event and writes it to the engine's stdin.
--- No serialisation is implemented yet — this is a no-op stub.
---@param event table the sealed mutation event from mutation_logger
function M.send(event)
  if _job_id <= 0 then
    -- Engine not running; drop the event silently for now.
    -- TODO: buffer events and flush once the job is (re)started
    return
  end

  -- TODO: serialise `event` (msgpack / JSON) and call vim.fn.chansend(_job_id, payload)
  _ = event
end

--- Gracefully stops the engine job.
--- Should flush any pending events before closing the channel.
function M.stop()
  if _job_id <= 0 then
    return
  end
  -- TODO: send a shutdown message before closing so the engine can flush state
  vim.fn.jobstop(_job_id)
  _job_id = 0
end

--- Returns true when the engine job is currently running.
---@return boolean
function M.is_running()
  return _job_id > 0
end

return M
