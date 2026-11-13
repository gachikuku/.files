-- Snapshot metadata and cleanup shared by the action, exit worker, and watcher.
local M = {}
M.cache = os.getenv("HOME") .. "/.cache/rex-copy-mode"

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

function M.valid_directory(directory)
  if type(directory) ~= "string" then return false end
  local prefix = M.cache .. "/snapshot-"
  return directory:sub(1, #prefix) == prefix
    and directory:sub(#prefix + 1):match("^[%w]+$") ~= nil
end

function M.context(directory)
  if not M.valid_directory(directory) then return nil end
  local raw = read(directory .. "/context.json")
  if not raw then return nil end
  local ok, context = pcall(rex.json.decode, raw)
  if not ok or type(context) ~= "table" then return nil end
  context.directory = directory
  return context
end

function M.for_block(block)
  if type(block) ~= "string" or block:find("[/\\%z\r\n]") then return nil end
  local directory = read(M.cache .. "/overlay-" .. block)
  if not directory then return nil end
  local context = M.context(directory:gsub("[\r\n]+$", ""))
  if context and context.overlay == block then return context end
end

function M.clean(directory, context)
  assert(M.valid_directory(directory), "Refusing to clean an invalid copy snapshot path.")
  context = context or M.context(directory)
  if context and type(context.overlay) == "string" and not context.overlay:find("[/\\%z\r\n]") then
    local marker = M.cache .. "/overlay-" .. context.overlay
    local target = read(marker)
    if target and target:gsub("[\r\n]+$", "") == directory then
      os.remove(marker)
      os.remove(marker .. ".tmp")
    end
  end
  -- Remove only files this implementation creates; never recursively delete.
  for _, name in ipairs({ "scrollback.txt", "context.json", "context.json.tmp" }) do
    os.remove(directory .. "/" .. name)
  end
  os.remove(directory)
end

function M.restore(context)
  -- A user may have switched tabs/panes while copying. Never steal focus back.
  local view = rex.session.view{ session_id = context.session }
  if not view or view.active_window_id ~= context.window then return end
  for _, window in ipairs(view.windows or {}) do
    if window.window_id == context.window
        and (window.focused_block_id == context.overlay or window.focused_block_id == context.source) then
      rex.session.focus_block{ session_id = context.session, block_id = context.source }
      if context.zoomed then
        rex.session.zoom_block{ session_id = context.session, block_id = context.source, zoom = true }
      end
      return
    end
  end
end

function M.closed(block)
  local context = M.for_block(block)
  if context then M.clean(context.directory, context) end
end

function M.sweep()
  local result = rex.exec({ "/usr/bin/find", M.cache, "-mindepth", "1", "-maxdepth", "1",
    "-type", "d", "-name", "snapshot-*", "-print" }, { timeout = 5 })
  if not result or not result.ok then return end
  local sessions = {}
  for directory in result.stdout:gmatch("[^\r\n]+") do
    local context = M.context(directory)
    if context and context.session and context.overlay then
      if sessions[context.session] == nil then
        local attached, err = rex.session.attach{ session_id = context.session }
        if attached then
          sessions[context.session] = rex.session.list_blocks{ session_id = context.session }
        elseif type(err) == "string" and err:match("%(status=404 code=session_not_found%)$") then
          sessions[context.session] = { blocks = {} }
        else sessions[context.session] = false end
      end
      local listed = sessions[context.session]
      if listed then
        local found = false
        for _, block in ipairs(listed.blocks or {}) do
          if block.block_id == context.overlay then found = true; break end
        end
        if not found then M.clean(directory, context) end
      end
    elseif context and context.created_at and os.time() - context.created_at > 60 then
      M.clean(directory, context)
    end
  end
end

return M
