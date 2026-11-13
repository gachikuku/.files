-- Retained-tab operations. The caller holds closed-tabs.lock for this whole run.
-- All Rex operations share one connection; this module never launches a terminal
-- program again, except for disposable placeholders used to rebuild its layout.
local M = { retention_seconds = 24 * 60 * 60 }
local flavor = "com.superlogical.terminal.shell"

local function ids(node, result)
  result = result or {}
  if not node then return result end
  if node.block_id then result[#result + 1] = node.block_id
  elseif node.split then
    ids(node.split.before, result)
    ids(node.split.after, result)
  end
  return result
end

local function entry_ids(entry)
  local result = {}
  for _, layer in ipairs(entry.window.layers or {}) do
    for _, id in ipairs(ids(layer.layout)) do result[id] = true end
  end
  return result
end

local function sorted_keys(t)
  local result = {}
  for key in pairs(t) do result[#result + 1] = key end
  table.sort(result)
  return result
end

local function remove(history, entry)
  for index, candidate in ipairs(history) do
    if candidate == entry then table.remove(history, index); return end
  end
end

local function surviving(node, available)
  if not node then return nil end
  if node.block_id then return available[node.block_id] and node or nil end
  local split = node.split
  local before, after = surviving(split.before, available), surviving(split.after, available)
  if not before or not after then return before or after end
  return { split = { direction = split.direction, ratio = split.ratio,
    before = before, after = after } }
end

local function placeholder(node, prefix)
  if node.block_id then
    return { block = { flavor = flavor, label = prefix .. node.block_id,
      options = { shell = "none", command = { "/bin/cat" } } } }
  end
  local s = node.split
  return { split = { direction = s.direction, ratio = s.ratio,
    before = placeholder(s.before, prefix), after = placeholder(s.after, prefix) } }
end

local function default_token()
  local file = assert(io.open("/dev/urandom", "rb"))
  local bytes = file:read(16)
  file:close()
  assert(bytes and #bytes == 16, "Could not create restoration identifier.")
  return (bytes:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end

function M.new(options)
  options = options or {}
  local save = assert(options.save, "A state writer is required.")
  local now = options.now or os.time
  local token = options.token or default_token
  local attached = {}
  local api = options.api or function(session, method, args)
    args = args or {}
    if session then
      if not attached[session] then
        local joined, join_err = rex.call("session.attach", { session_id = session })
        if not joined then error(join_err, 0) end
        attached[session] = true
      end
      args.session_id = session
    end
    local result, err = rex.call(method, args)
    if not result then error(err or (method .. " failed"), 0) end
    return result
  end
  local engine = {}

  local function blocks(session)
    local result = {}
    for _, item in ipairs(api(session, "session.list_blocks", {}).blocks or {}) do
      result[item.block_id] = item
    end
    return result
  end

  local function history_for(state, session)
    if not state.sessions[session] then state.sessions[session] = {} end
    return state.sessions[session]
  end

  function engine.expire(state, instant, session_only)
    instant = instant or now()
    local cutoff = instant - M.retention_seconds
    local result = { expired_tabs = 0, closed_terminals = 0, errors = {} }
    local due = {}
    for session, history in pairs(state.sessions) do
      if not session_only or session == session_only then
        for _, entry in ipairs(history) do
          if (entry.closed_at or instant) <= cutoff then
            due[session] = due[session] or {}
            table.insert(due[session], entry)
          end
        end
      end
    end
    if not next(due) then return result end
    -- A failed server query leaves every journal untouched for the next sweep.
    local live = {}
    for _, item in ipairs(api(nil, "session.list", {}).sessions or {}) do
      live[item.session_id] = true
    end
    for _, session in ipairs(sorted_keys(due)) do
      local entries, history = due[session], state.sessions[session]
      if not live[session] then
        result.expired_tabs = result.expired_tabs + #entries
        state.sessions[session] = nil
        save(state)
      else
        local protected = {}
        for _, entry in ipairs(history) do
          if (entry.closed_at or instant) > cutoff then
            for id in pairs(entry_ids(entry)) do protected[id] = true end
          end
        end
        for _, entry in ipairs(entries) do
          local failed = false
          for _, id in ipairs(sorted_keys(entry_ids(entry))) do
            if not protected[id] then
              local ok, err = pcall(function()
                local item = blocks(session)[id]
                if item and item.placement == "detached" then
                  api(session, "block.close", { block_id = id, keep_last = true })
                  result.closed_terminals = result.closed_terminals + 1
                end
              end)
              if not ok then
                local message = tostring(err)
                if not message:match("%(status=404 code=not_found%)$")
                    and not message:match("%(status=404 code=session_not_found%)$") then
                  failed = true
                  table.insert(result.errors, message)
                end
              end
            end
          end
          if not failed and not entry.restoring then
            remove(history, entry)
            result.expired_tabs = result.expired_tabs + 1
            save(state)
          end
          -- Partial restores keep their visible panes and recovery plans.
        end
        if #history == 0 then state.sessions[session] = nil; save(state) end
      end
    end
    return result
  end

  function engine.close(state, session, block)
    local view = api(session, "session.view", {})
    local window, index
    for i, candidate in ipairs(view.windows or {}) do
      if candidate.window_id == view.active_window_id and not window then
        window, index = candidate, i - 1
      end
      for _, layer in ipairs(candidate.layers or {}) do
        for _, item in ipairs(layer.blocks or {}) do
          if item.block_id == block then window, index = candidate, i - 1 end
        end
      end
    end
    if not window then return { changed = false, reason = "No tab is selected." } end
    if not window.layers[1] or not window.layers[1].layout then
      error("This tab has no tiled pane to retain.", 0)
    end
    local history, entry = history_for(state, session)
    for _, candidate in ipairs(history) do
      if candidate.window.window_id == window.window_id and not candidate.restoring then
        entry = candidate; break
      end
    end
    if not entry then
      entry = { window = window, index = index, closed_at = now() }
      table.insert(history, entry)
      save(state) -- Record every original before any terminal is detached.
    end
    if #(view.windows or {}) == 1 then
      api(session, "session.new_window", { focus = false, window_label = "New Tab",
        layout = { block = { flavor = flavor } } })
    end
    local current = blocks(session)
    for _, layer in ipairs(entry.window.layers or {}) do
      for _, id in ipairs(ids(layer.layout)) do
        local item = current[id]
        if item and item.window_id == window.window_id then
          api(session, "session.detach_block", { block_id = id })
        end
      end
    end
    view = api(session, "session.view", {})
    return { changed = true, session_id = session, window_id = view.active_window_id,
      retained = #history }
  end

  local function find_placeholders(session, prefix)
    for _, window in ipairs(api(session, "session.view", {}).windows or {}) do
      for _, layer in ipairs(window.layers or {}) do
        local found = {}
        for _, item in ipairs(layer.blocks or {}) do
          if (item.label or ""):sub(1, #prefix) == prefix then
            -- Match by original ID, not position: a partial layout may have
            -- lost or reordered a placeholder between creation and journaling.
            found[item.label:sub(#prefix + 1)] = item.block_id
          end
        end
        if next(found) then
          return { window_id = window.window_id, layer_id = layer.layer_id, by_original = found }
        end
      end
    end
  end

  local function pair_placeholders(plan, made)
    local pairs = {}
    local originals = ids(plan.layout)
    for i, id in ipairs(originals) do
      local target = made.by_original and made.by_original[id] or (made.block_ids or {})[i]
      if not target then error("A restoration placeholder disappeared; retained pane is safe.", 0) end
      table.insert(pairs, { id, target })
    end
    return pairs
  end

  function engine.reopen(state, session)
    local history = history_for(state, session)
    local entry, original, restoring, available
    while #history > 0 do
      entry = history[#history]
      original, restoring = entry.window, entry.restoring
      local current = blocks(session)
      if restoring and restoring.window_id then
        local exists = false
        for _, w in ipairs(api(session, "session.view", {}).windows or {}) do
          if w.window_id == restoring.window_id then exists = true end
        end
        if not exists then entry.restoring = nil; restoring = nil; save(state) end
      end
      available = {}
      for id in pairs(entry_ids(entry)) do
        local item = current[id]
        if item and (item.placement == "detached" or item.window_id == original.window_id
            or (restoring and item.window_id == restoring.window_id)) then available[id] = true end
      end
      if next(available) then break end
      table.remove(history); save(state)
    end
    if #history == 0 then return { changed = false, reason = "No closed tabs remain in this session." } end
    if not restoring then
      local plans = {}
      for _, layer in ipairs(original.layers or {}) do
        local layout = surviving(layer.layout, available)
        if layout then table.insert(plans, { source = layer, layout = layout }) end
      end
      restoring = { token = token(), layers = {}, plans = plans }
      entry.restoring = restoring
      save(state)
    end
    if not restoring.window_id then
      local first = restoring.plans[1]
      local prefix = "rex-reopen-" .. restoring.token .. "-0-"
      local made = find_placeholders(session, prefix)
      if not made then
        made = api(session, "session.new_window", { focus = false,
          window_label = original.label or "Reopened Tab", layout = placeholder(first.layout, prefix) })
      end
      restoring.window_id = made.window_id
      table.insert(restoring.layers, { pairs = pair_placeholders(first, made) })
      save(state)
    end
    local target = restoring.window_id
    for i = #restoring.layers + 1, #restoring.plans do
      local plan = restoring.plans[i]
      local prefix = "rex-reopen-" .. restoring.token .. "-" .. (i - 1) .. "-"
      local made = find_placeholders(session, prefix)
      if not made then
        made = api(session, "session.new_layer", { window_id = target, focus = false,
          bounds = plan.source.bounds, layout = placeholder(plan.layout, prefix) })
      end
      if made.window_id and made.window_id ~= target then
        error("A restoration placeholder was moved elsewhere; leaving it intact.", 0)
      end
      table.insert(restoring.layers, { pairs = pair_placeholders(plan, made), layer_id = made.layer_id })
      save(state)
    end
    for _, layer in ipairs(restoring.layers) do
      for _, pair in ipairs(layer.pairs) do
        local retained, anchor_id = pair[1], pair[2]
        local current = blocks(session)
        local item, anchor = current[retained], current[anchor_id]
        if item and anchor then
          if anchor.window_id ~= target then
            error("A restoration placeholder was moved elsewhere; leaving it intact.", 0)
          end
          if item.window_id ~= target then
            if item.placement ~= "detached" and item.window_id ~= original.window_id then
              error("A retained pane was moved elsewhere; leaving it intact.", 0)
            end
            api(session, "session.move_block", { block_id = retained, anchor_block_id = anchor_id, side = "after" })
          end
          api(session, "block.close", { block_id = anchor_id })
        elseif anchor then
          if anchor.window_id ~= target then error("A restoration placeholder moved elsewhere.", 0) end
          api(session, "block.close", { block_id = anchor_id })
        elseif item and item.window_id ~= target then
          error("A restoration placeholder disappeared; retained pane is safe.", 0)
        end
      end
    end
    local view = api(session, "session.view", {})
    local target_view, others = nil, {}
    for _, window in ipairs(view.windows or {}) do
      if window.window_id == target then target_view = window else table.insert(others, window.window_id) end
    end
    if not target_view then
      table.remove(history); save(state)
      return { changed = false, reason = "The retained programs have exited." }
    end
    local placed, live_layers, first_block = {}, {}, nil
    for _, layer in ipairs(target_view.layers or {}) do
      live_layers[layer.layer_id] = true
      for _, item in ipairs(layer.blocks or {}) do
        placed[item.block_id] = true
        first_block = first_block or item.block_id
      end
    end
    for i, layer in ipairs(restoring.layers) do
      if layer.layer_id and live_layers[layer.layer_id] and restoring.plans[i].source.state == "minimized" then
        api(session, "session.set_layer_state", { layer_id = layer.layer_id, state = "minimized" })
      end
    end
    local focus = placed[original.focused_block_id] and original.focused_block_id or first_block
    if focus then api(session, "session.focus_block", { block_id = focus }) end
    if original.zoomed_block_id and placed[original.zoomed_block_id] then
      api(session, "session.zoom_block", { block_id = original.zoomed_block_id, zoom = true })
    end
    api(session, "session.move_window", { window_id = target, before_window_id = others[(entry.index or 0) + 1] })
    table.remove(history); save(state)
    return { changed = true, session_id = session, window_id = target, remaining = #history }
  end
  return engine
end

-- Preserve empty JSON arrays in the existing journal format.
local array_fields = { layers = true, plans = true, pairs = true, blocks = true,
  bounds = true, rect = true, block_ids = true }
local function encode(value, field, array_hint)
  if type(value) ~= "table" then return assert(rex.json.encode(value)) end
  local count, array = 0, true
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then array = false end
  end
  if count == 0 then return (array_hint or array_fields[field]) and "[]" or "{}" end
  if array and #value == count then
    local parts = {}
    for i, item in ipairs(value) do parts[i] = encode(item) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local parts = {}
  for _, key in ipairs(sorted_keys(value)) do
    parts[#parts + 1] = assert(rex.json.encode(key)) .. ":" .. encode(value[key], key, field == "sessions")
  end
  return "{" .. table.concat(parts, ",") .. "}"
end
M.encode_state = encode

function M.read_state(path)
  local file, err = io.open(path, "r")
  if not file then
    if tostring(err):find("[Nn]o such file") then return { version = 1, sessions = {} } end
    error(err, 0)
  end
  local contents = file:read("*a")
  file:close()
  local state, decode_err = rex.json.decode(contents)
  if not state then error(decode_err, 0) end
  assert(state.version == 1 and type(state.sessions) == "table", "Unrecognized closed-tab state; leaving it intact.")
  return state
end

function M.write_state(path, state)
  local temporary = path .. ".tmp"
  local output = assert(io.open(temporary, "w"))
  local mode, err = rex.exec({ "/bin/chmod", "600", temporary }, { timeout = 2 })
  if not mode or not mode.ok then output:close(); error(err or mode.stderr, 0) end
  assert(output:write(encode(state)))
  assert(output:flush())
  assert(output:close())
  assert(os.rename(temporary, path))
end

return M
