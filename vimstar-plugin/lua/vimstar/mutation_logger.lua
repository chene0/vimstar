-- Mutation Logger — observes keystrokes and buffer changetick events to
-- group raw input into sealed mutation events, then emits them over IPC.
--
-- State machine (per buffer):
--   on_key      → append_keystroke → [sequence buffer grows]
--   changetick  → did undotree block count increase?
--                   yes → seal_sequence → emit_sequence → reset_sequence
--                   no  → no_op

local ipc = require("vimstar.ipc")

local M = {}

-- Per-buffer state: maps bufnr → { sequence: string[], undo_seq: integer }
local _state = {}

-- ---------------------------------------------------------------------------
-- Forward declarations
-- ---------------------------------------------------------------------------

local get_buf_state
local append_keystroke
local did_undotree_increase
local seal_sequence
local emit_sequence
local reset_sequence
local no_op
local esc_prefix
local is_ignorable
local is_esc
local on_key_handler
local on_buf_changed
local on_changedtick
local on_lines

-- ---------------------------------------------------------------------------
-- Flow handlers
-- ---------------------------------------------------------------------------

--- Returns (or initialises) the mutable logger state for a buffer.
---@param bufnr integer
---@return table state { sequence: string[], undo_seq: integer }
get_buf_state = function(bufnr)
	if not _state[bufnr] then
		local tree = vim.api.nvim_buf_call(bufnr, vim.fn.undotree)
		_state[bufnr] = {
			sequence = {},
			undo_seq = tree.seq_last,
		}
	end
	return _state[bufnr]
end

--- Appends the raw keystroke to the current sequence buffer for the active buffer.
--- Called on every vim.on_key event.
--- Should filter out non-printable / irrelevant keys before appending.
---@param key string raw key string as received from vim.on_key
append_keystroke = function(key)
	if is_ignorable(key) then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local state = get_buf_state(bufnr)

	if is_esc(key) then
		-- esc = mode boundary: seal whatever was in flight
		local event = seal_sequence(bufnr)

		if event then
			emit_sequence(event)
			reset_sequence(bufnr)
		end
		return
	end

	table.insert(state.sequence, key)
end

--- Queries the current undo-tree block count for the buffer and compares it
--- against the last recorded value.
--- Returns true when a new undo block has been committed (i.e. a mutation
--- crossed a "save point" in Neovim's undo history).
---@param bufnr integer
---@return boolean increased
did_undotree_increase = function(bufnr)
	local ok, tree = pcall(vim.api.nvim_buf_call, bufnr, function()
		return vim.fn.undotree()
	end)
	if not ok then
		vim.notify("undotree error: " .. tostring(tree), vim.log.levels.WARN)
		return false
	end
	local state = get_buf_state(bufnr)
	local prev = state.undo_seq

	local curr = tree.seq_last
	if curr > prev then
		state.undo_seq = curr
		return true
	end
	return false
end

--- Closes the current keystroke accumulation window and snapshots it as one
--- atomic mutation event.
--- Should copy the sequence buffer into an immutable event structure and
--- annotate it with buffer position, timestamp, etc.
---@param bufnr integer
---@return table|nil event the sealed event, or nil if the sequence was empty
seal_sequence = function(bufnr)
	local state = get_buf_state(bufnr)
	if #state.sequence == 0 then
		return nil
	end
	-- TODO: build a richer event structure (cursor pos, mode, timestamp, …)
	local event = {
		keystrokes = vim.list_slice(state.sequence, 1, #state.sequence),
		bufnr = bufnr,
	}
	return event
end

--- Hands a sealed mutation event off to the IPC layer for serialisation and
--- transmission to the external engine.
---@param event table the event produced by seal_sequence
emit_sequence = function(event)
	-- TODO: serialise event (msgpack / JSON) before passing to ipc.send
	vim.notify(vim.inspect(event), vim.log.levels.DEBUG)
	ipc.send(event)
end

--- Clears the in-progress keystroke buffer after a sequence has been emitted.
---@param bufnr integer
reset_sequence = function(bufnr)
	-- TODO: decide whether to also reset undo_seq here or on the next changetick
	local state = get_buf_state(bufnr)
	state.sequence = {}
end

--- No-op branch taken when a changetick fires but the undo tree has not grown.
--- Kept as an explicit function so future logic (e.g. rate-limiting) has a
--- clear place to live.
no_op = function() end

-- ---------------------------------------------------------------------------
-- Key filtering
-- ---------------------------------------------------------------------------

local ESC = "\27"

esc_prefix = function(stem)
	return ESC .. stem
end

local IGNORE = {
	[esc_prefix("[I")] = true, -- FocusGained
	[esc_prefix("[O")] = true, -- FocusLost
}

is_ignorable = function(key)
	if key == "" then
		return true
	end
	if IGNORE[key] then
		return true
	end
	-- mouse events
	if key:sub(1, 3) == esc_prefix("[<") or key:sub(1, 3) == esc_prefix("[M") then
		return true
	end
	return false
end

is_esc = function(key)
	-- lone esc is exactly one byte
	-- multi-byte sequences start with 0x1b but are longer
	return key == ESC
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

--- vim.on_key callback — fires for every key Neovim processes.
--- Feeds raw input into the current buffer's sequence buffer.
---@param key string
on_key_handler = function(key)
	-- TODO: guard against keys typed in non-normal/insert modes if needed
	append_keystroke(key)
end

--- Shared handler for any buffer change event.
--- Both on_lines and on_changedtick funnel here to keep the undotree check DRY.
---@param bufnr integer
on_buf_changed = function(bufnr)
	if did_undotree_increase(bufnr) then
		local event = seal_sequence(bufnr)
		if event then
			emit_sequence(event)
			reset_sequence(bufnr)
		end
	else
		no_op()
	end
end

--- nvim_buf_attach on_lines callback — fires for actual text mutations
--- (typing, paste, delete, undo/redo that changes content).
---@param _ev      string
---@param bufnr    integer
---@param _tick    integer
---@param _first   integer
---@param _last    integer
---@param _lastold integer
on_lines = function(_ev, bufnr, _tick, _first, _last, _lastold)
	on_buf_changed(bufnr)
end

--- nvim_buf_attach on_changedtick callback — fires for tick increments that
--- have no corresponding on_lines event (e.g. :w, certain undo metadata bumps).
---@param _ev   string
---@param bufnr integer
---@param _tick integer
on_changedtick = function(_ev, bufnr, _tick)
	on_buf_changed(bufnr)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Registers the global on_key listener and attaches changetick hooks to all
--- current and future buffers via BufAdd autocommand.
--- Called once from vimstar.setup().
function M.attach_hooks()
	-- Global keystroke observer
	vim.on_key(on_key_handler, vim.api.nvim_create_namespace("vimstar_on_key"))

	-- Attach changetick watcher to already-loaded buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			M.attach_buf(bufnr)
		end
	end

	-- Attach to buffers opened after plugin load
	vim.api.nvim_create_autocmd("BufAdd", {
		group = vim.api.nvim_create_augroup("vimstar_mutation_logger", { clear = true }),
		callback = function(ev)
			M.attach_buf(ev.buf)
		end,
	})
end

--- Attaches the changetick listener to a single buffer.
--- Idempotent — safe to call multiple times for the same buffer.
---@param bufnr integer
function M.attach_buf(bufnr)
	-- TODO: track which buffers have already been attached to avoid double-attach
	vim.api.nvim_buf_attach(bufnr, false, {
		on_lines = on_lines,
		on_changedtick = on_changedtick,
		on_detach = function(_, detached_bufnr)
			-- TODO: clean up _state[detached_bufnr] to avoid memory leaks
			_ = detached_bufnr
		end,
	})
end

return M
