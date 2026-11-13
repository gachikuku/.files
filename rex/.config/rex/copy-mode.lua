local snapshot = require("copy-snapshot")
local cache = snapshot.cache
local terminal = "com.superlogical.terminal"
local M = {}

function M.dismiss_if_active(ctx)
  local context = snapshot.for_block(ctx.block_id)
  if not context or context.session ~= ctx.session_id then return { closed = false } end
  local closed, err = rex.session.close_layer{ session_id = ctx.session_id, layer_id = context.layer }
  if not closed then error(err) end
  snapshot.clean(context.directory, context)
  snapshot.restore(context)
  return { closed = true }
end

local function run(argv)
  local result, err = rex.exec(argv, { timeout = 5 })
  if not result then error(err) end
  if not result.ok then error(result.stderr) end
  return result.stdout
end

local function write_atomic(path, content)
  local output = assert(io.open(path .. ".tmp", "wb"))
  local written, err = output:write(content)
  local closed, close_err = output:close()
  assert(written, err)
  assert(closed, close_err)
  assert(os.rename(path .. ".tmp", path))
end

local function rectangle(node, block)
  if not node then return nil end
  if node.block_id == block then return node.rect end
  if node.split then
    return rectangle(node.split.before, block) or rectangle(node.split.after, block)
  end
end

local function already_open(ctx)
  return snapshot.for_block(ctx.block_id) ~= nil
end

local function open_overlay(ctx)
  if not ctx.block_id or not ctx.session_id then
    error("Select a terminal pane to enter copy mode.")
  end
  if already_open(ctx) then
    return { changed = false, reason = "Copy mode is already open." }
  end
  local view, view_err = rex.session.view{ session_id = ctx.session_id }
  if not view then error(view_err) end
  local window, layer, block
  for _, candidate_window in ipairs(view.windows or {}) do
    for _, candidate_layer in ipairs(candidate_window.layers or {}) do
      for _, candidate_block in ipairs(candidate_layer.blocks or {}) do
        if candidate_block.block_id == ctx.block_id then
          window, layer, block = candidate_window, candidate_layer, candidate_block
        end
      end
    end
  end
  if not block or block.creator_name ~= terminal then
    error("Select a terminal pane to enter copy mode.")
  end
  local bounds = window.zoomed_block_id == ctx.block_id and { 0, 0, 1, 1 }
    or rectangle(layer.layout, ctx.block_id)
  if not bounds then error("Could not locate this terminal pane's bounds.") end

  -- mktemp creates the private directory (0700); files remain protected by it.
  -- Avoid changing the long-lived Rex server's process-wide umask.
  local existing = io.open(cache, "r")
  if existing then existing:close()
  else run({ "/bin/mkdir", "-m", "700", "-p", cache }) end
  local directory = run({ "/usr/bin/mktemp", "-d", cache .. "/snapshot-XXXXXXXX" }):gsub("[\r\n]+$", "")
  local context_path = directory .. "/context.json"
  local context = { session = ctx.session_id, source = ctx.block_id,
    window = window.window_id, zoomed = window.zoomed_block_id == ctx.block_id,
    created_at = os.time() }
  local created, output, marker
  local ok, result = pcall(function()
    write_atomic(context_path, rex.json.encode(context))
    output = assert(io.open(directory .. "/scrollback.txt", "wb"))
    local first, format_err = rex.block.call(terminal, "format", {
      session_id = ctx.session_id, block_id = ctx.block_id,
      format = "text", trim = true, unwrap = true, max_bytes = 983040,
    })
    if not first then error(format_err) end
    assert(output:write(first.content))
    local offset = #first.content
    if first.id then
      while not first.eof do
        local chunk, chunk_err = rex.block.call(terminal, "blob_read", {
          session_id = ctx.session_id, block_id = ctx.block_id,
          id = first.id, offset = offset, max_bytes = 983040,
        })
        if not chunk then error(chunk_err) end
        assert(output:write(chunk.data))
        offset = offset + #chunk.data
        if chunk.eof then break end
        if #chunk.data == 0 then error("Scrollback capture stopped making progress.") end
      end
    end
    assert(output:close())
    output = nil
    local layer_err
    created, layer_err = rex.session.new_layer{
      session_id = ctx.session_id, window_id = window.window_id,
      bounds = bounds, focus = true,
      layout = { block = {
        flavor = "com.superlogical.terminal.shell", label = "Copy Mode",
        options = { shell = "none",
          command = { "/run/current-system/sw/bin/nvim", "-u", os.getenv("HOME") .. "/.config/rex/copy-viewer.lua",
            "--noplugin", "-n", "-i", "NONE", "-M", "-R", "--", directory .. "/scrollback.txt" },
          exit = { on_completion = true, quick_exit_threshold_ms = 0 },
        },
      } },
    }
    if not created then error(layer_err) end
    context.overlay = created.block_ids[1]
    context.layer = created.layer_id
    marker = cache .. "/overlay-" .. context.overlay
    -- Publish the marker before completing metadata used by the exit cleanup.
    write_atomic(marker, directory .. "\n")
    write_atomic(context_path, rex.json.encode(context))
    return { changed = true, session_id = ctx.session_id,
      window_id = window.window_id, block_id = context.overlay }
  end)
  if not ok then
    if output then pcall(function() output:close() end) end
    local can_clean = true
    if created then
      -- This is only the overlay this action just created, never the source.
      local close_ok, closed = pcall(function()
        return rex.session.close_layer{ session_id = ctx.session_id, layer_id = created.layer_id }
      end)
      can_clean = close_ok and closed ~= nil
    end
    if can_clean then
      if marker then os.remove(marker); os.remove(marker .. ".tmp") end
      snapshot.clean(directory, context)
    end
    error(result)
  end
  -- The source tab is already displayed; new_layer(focus=true) focuses its pane.
  return result
end

rex.action{
  name = "keyboard_copy_mode",
  title = "Enter Keyboard Copy Mode",
  description = "Move with hjkl, select with v, copy with y, and leave with q or Escape.",
  category = "Pane",
  run = open_overlay,
}

return M
