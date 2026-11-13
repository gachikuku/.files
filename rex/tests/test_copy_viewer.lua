-- Run: nvim --headless -u NONE -l ~/.files/rex/tests/test_copy_viewer.lua
-- Exercises the actual viewer in a separate Neovim process via its RPC API.
local root = vim.env.HOME .. "/.files/rex"
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p", 448)
local snapshot, copied = directory .. "/scrollback.txt", directory .. "/copied.txt"
vim.fn.writefile({ "alpha", "bravo", "literal $(touch forbidden); `echo nope`", string.rep("x", 180), "last" }, snapshot)
local channels, exits, count = {}, {}, 0

local function expect(condition, message)
  assert(condition, message)
  count = count + 1
end
local function start()
  local began = vim.uv.hrtime()
  local channel = vim.fn.jobstart({ vim.v.progpath, "--headless", "--embed", "-u",
    root .. "/.config/rex/copy-viewer.lua", "--noplugin", "-n", "-i", "NONE", "-M", "-R", "--", snapshot },
    { rpc = true, on_exit = function(id, code) exits[id] = code end })
  assert(channel > 0, "could not launch viewer")
  channels[#channels + 1] = channel
  local function request(method, ...) return vim.rpcrequest(channel, method, ...) end
  assert(vim.wait(2000, function()
    return request("nvim_exec_lua", "return vim.v.vim_did_enter == 1", {})
  end, 2), "viewer did not enter")
  local elapsed = (vim.uv.hrtime() - began) / 1e6
  request("nvim_set_var", "rex_copy_command", { "/usr/bin/tee", copied })
  local function keys(value)
    request("nvim_input", value)
    vim.wait(35, function() return false end, 5)
  end
  return channel, request, keys, elapsed
end
local function read_copy()
  local file = io.open(copied, "rb")
  if not file then return nil end
  local value = file:read("*a")
  file:close()
  return value
end
local function copy_equals(value)
  return vim.wait(1000, function() return read_copy() == value end, 5)
end

local ok, failure = xpcall(function()
  local channel, request, keys, elapsed = start()
  expect(request("nvim_win_get_cursor", 0)[1] == 5, "viewer must start at bottom")
  expect(request("nvim_get_option_value", "modifiable", {}) == false, "snapshot must be immutable")
  expect(request("nvim_get_option_value", "loadplugins", {}) == false, "plugins must be disabled")
  expect(request("nvim_get_var", "loaded_python3_provider") == 0, "external providers must be disabled")

  request("nvim_win_set_cursor", 0, { 1, 0 })
  keys("y")
  expect(copy_equals("alpha\n"), "normal y must copy the line with its newline")
  expect(request("nvim_get_mode").mode == "n", "y must keep the viewer open")
  keys("vll<CR>")
  expect(copy_equals("alp"), "visual Enter must copy exact selected characters")
  expect(request("nvim_get_mode").mode == "n", "Enter must keep the viewer open")

  request("nvim_win_set_cursor", 0, { 1, 0 })
  keys("Vjy")
  expect(copy_equals("alpha\nbravo\n"), "linewise selection must preserve its trailing newline")
  request("nvim_win_set_cursor", 0, { 1, 0 })
  keys("<C-v>ljy")
  expect(copy_equals("al\nbr"), "rectangular selection must copy selected columns")

  request("nvim_win_set_cursor", 0, { 3, 0 })
  keys("<CR>")
  expect(copy_equals("literal $(touch forbidden); `echo nope`\n"), "copied text must remain literal")
  expect(vim.uv.fs_stat(directory .. "/forbidden") == nil, "copy must not execute terminal text")

  request("nvim_set_var", "rex_copy_command", { "/usr/bin/false" })
  request("nvim_win_set_cursor", 0, { 1, 0 })
  keys("vly")
  expect(request("nvim_get_mode").mode == "v", "failed copy must restore the visual selection")
  request("nvim_set_var", "rex_copy_command", { "/usr/bin/tee", copied })
  keys("y")
  expect(copy_equals("al"), "failed copy must be retryable")
  keys("v<Esc>")
  expect(request("nvim_get_mode").mode == "n", "visual Escape must cancel without exiting")

  request("nvim_win_set_cursor", 0, { 1, 0 })
  keys("/bravo<CR>")
  expect(request("nvim_win_get_cursor", 0)[1] == 2, "search must work")
  request("nvim_win_set_cursor", 0, { 4, 0 })
  keys("j")
  local cursor = request("nvim_win_get_cursor", 0)
  expect(cursor[1] == 4 and cursor[2] > 0, "j must move by wrapped display lines")
  keys("k")
  expect(request("nvim_win_get_cursor", 0)[2] == 0, "k must reverse display-line movement")

  keys("q")
  expect(vim.wait(1000, function() return exits[channel] == 0 end, 5), "q must exit promptly")
  local second, _, second_keys = start()
  second_keys("<Esc>")
  expect(vim.wait(1000, function() return exits[second] == 0 end, 5), "normal Escape must exit promptly")

  print(string.format("PASS: %d viewer checks; first startup to ready %.1f ms", count, elapsed))
end, debug.traceback)
for _, channel in ipairs(channels) do pcall(vim.fn.jobstop, channel) end
vim.fn.delete(directory, "rf")
if not ok then error(failure) end
