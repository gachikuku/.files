-- A robust byte counter for visual mode with multi-line support

-- Function to get the actual text in the visual selection
-- This approach uses vim's built-in registers to capture the exact selection
local function get_visual_selection()
  -- Save current register content to restore later
  local reg_save = vim.fn.getreg('a')
  local regtype_save = vim.fn.getregtype('a')
  -- Get current mode to determine if we need to reselect
  local mode = vim.fn.mode()
  local is_visual = mode == 'v' or mode == 'V' or mode == '\22'
  -- If we're in visual mode, yank the selection to register 'a'
  if is_visual then
    -- Use silent operation to avoid screen flashing
    vim.cmd('silent normal! "ay')
    -- Get the selection content
    local selection = vim.fn.getreg('a')
    -- Restore the visual selection
    vim.cmd('normal! gv')
    -- Restore original register content
    vim.fn.setreg('a', reg_save, regtype_save)
    return selection
  else
    -- If not in visual mode, try to use the '< and '> marks
    -- These marks define the last visual selection
    if vim.fn.getpos("'<")[2] ~= 0 and vim.fn.getpos("'>")[2] ~= 0 then
      -- Temporarily enter visual mode to reselect the last selection
      vim.cmd('normal! gv"ay')
      -- Get the selection
      local selection = vim.fn.getreg('a')
      -- Restore original register content
      vim.fn.setreg('a', reg_save, regtype_save)
      return selection
    end
  end
  return ""
end

-- Function to format byte count info with both decimal and hex
local function format_byte_count()
  local mode = vim.fn.mode()
  local count = 0
  -- Check if we're in visual mode
  if mode == 'v' or mode == 'V' or mode == '\22' then
    -- Get the actual selected text
    local selection = get_visual_selection()
    -- Return its byte length
    count = #selection
  else
    return ""
  end
  -- Format byte count with hex representation
  local hex = string.format("0x%X", count)
  return string.format("%d bytes (%s)", count, hex)
end

-- Store the original statusline
vim.g.original_statusline = vim.o.statusline or ""

-- Set up mode detection and statusline changes
vim.api.nvim_create_autocmd("ModeChanged", {
  pattern = "*:[vV\x16]*",  -- When entering visual mode
  callback = function()
    -- Save the current statusline if not already saved
    if not vim.g.original_statusline or vim.g.original_statusline == "" then
      vim.g.original_statusline = vim.o.statusline
    end
    -- Set new statusline that shows byte count on the right
    vim.o.statusline = "%<%f %h%m%r%=%{luaeval('_G.format_byte_count()')} %l,%c%V %P"
    -- Force an initial update
    vim.cmd("redrawstatus")
  end
})

vim.api.nvim_create_autocmd("ModeChanged", {
  pattern = "[vV\x16]*:*",  -- When leaving visual mode
  callback = function()
    -- Restore original statusline
    vim.o.statusline = vim.g.original_statusline
  end
})

-- Set up an autocommand to update the statusline during visual selection changes
vim.api.nvim_create_autocmd({"CursorMoved"}, {
  callback = function()
    local mode = vim.fn.mode()
    if mode == 'v' or mode == 'V' or mode == '\22' then
      vim.cmd("redrawstatus")
    end
  end
})

-- Add a TextChanged event handler to catch more selection changes
vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
  callback = function()
    local mode = vim.fn.mode()
    if mode == 'v' or mode == 'V' or mode == '\22' then
      vim.cmd("redrawstatus")
    end
  end
})

-- Ensure we also update on cursor hold for smoother experience
vim.api.nvim_create_autocmd({"CursorHold", "CursorHoldI"}, {
  callback = function()
    local mode = vim.fn.mode()
    if mode == 'v' or mode == 'V' or mode == '\22' then
      vim.cmd("redrawstatus")
    end
  end
})

-- Optional manual update command that preserves selection
vim.api.nvim_set_keymap('v', '<leader>b', ':<C-u>lua vim.cmd("normal! gv") vim.cmd("redrawstatus")<CR>gv', {noremap = true, silent = true})

-- Make the format_byte_count function available globally for the statusline
_G.format_byte_count = format_byte_count

