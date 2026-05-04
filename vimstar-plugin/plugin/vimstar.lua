-- Auto-loaded by Neovim on startup. Bootstraps the plugin and registers
-- top-level user commands. Keep this file thin; all logic lives under lua/.

if vim.g.loaded_vimstar then
  return
end
vim.g.loaded_vimstar = true

local ok, vimstar = pcall(require, "vimstar")
if not ok then
  vim.notify("vimstar: failed to load plugin — " .. vimstar, vim.log.levels.ERROR)
  return
end

-- :Vimstar — opens the engine dashboard
vim.api.nvim_create_user_command("Vimstar", function(opts)
  vimstar.open_dashboard(opts.args)
end, {
  nargs = "?",
  desc = "Open the vimstar engine dashboard",
})
