local api = vim.api
local scope = require('prose_focus.scope')
local highlight = require('prose_focus.highlight')
local M = {}


local defaults = {
  enabled = true,
  mode = 'paragraph',
  filetypes = { 'text', 'markdown', 'typst', 'rst', 'asciidoc', 'org' },
  dim = 0.60,
  highlight = false, -- e.g. 'Comment'; bypasses automatic color mixing
  priority = 200,
  active_only = false,
  suspend_in_visual = true,
  max_paragraph_lines = 2000,
  max_paragraph_bytes = 262144,
}


local ns = api.nvim_create_namespace('prose_focus')
local config, group, dim_group
local windows, allowed = {}, {}
local pending, force_pending = false, false
local previous_suspended, previous_current


local function integer(value, minimum, maximum)
  return type(value) == 'number' and value % 1 == 0
    and value >= minimum and value <= maximum
end


local function validate(opts)
  assert(type(opts) == 'table',
    'prose_focus: options must be a table'
  )

  for key in pairs(opts) do
    assert(defaults[key] ~= nil,
      'prose_focus: unknown option ' .. tostring(key)
    )
  end

  local c = vim.tbl_extend('force', vim.deepcopy(defaults), opts)

  assert(c.mode == 'sentence' or c.mode == 'paragraph',
    'prose_focus: invalid mode'
  )

  for _, key in ipairs({ 'enabled', 'active_only', 'suspend_in_visual' }) do
    assert(type(c[key]) == 'boolean',
      'prose_focus: ' .. key .. ' must be boolean'
    )
  end

  assert(type(c.dim) == 'number' and c.dim >= 0 and c.dim <= 1,
    'prose_focus: dim must be between 0 and 1')

  assert(c.highlight == false or (type(c.highlight) == 'string' and c.highlight ~= ''),
    'prose_focus: highlight must be false or a group name')

  assert(integer(c.priority, 0, 65535),
    'prose_focus: invalid priority'
  )

  for _, key in ipairs({ 'max_paragraph_lines', 'max_paragraph_bytes' }) do
    assert(integer(c[key], 1, 2147483647),
      'prose_focus: invalid ' .. key
    )
  end

  assert(type(c.filetypes) == 'table' and vim.islist(c.filetypes),
    'prose_focus: filetypes must be a list (empty means all normal buffers)'
  )

  for _, ft in ipairs(c.filetypes) do
    assert(type(ft) == 'string',
      'prose_focus: filetypes must contain strings'
    )
  end

  return c
end


local function suspended()
  if not config.suspend_in_visual then
    return false
  end

  local mode = api.nvim_get_mode().mode:sub(1, 1)

  return mode == 'v' or mode == 'V' or mode == '\022' or mode == 's' or mode == 'S' or mode == '\019'
end


local function eligible(win, buf, current)
  return (not config.active_only or win == current)   -- Accept all or currently active
    and api.nvim_win_get_config(win).relative == ''   -- Reject floating windows
    and vim.bo[buf].buftype == ''                     -- Reject special buffers (e.g. help/prompt/terminal/plugin)
    and (#config.filetypes == 0 or allowed[vim.bo[buf].filetype])
end


local function same(a, b)
  if not a or not b then
    return a == b
  end

  for i = 1, 4 do
    if a[i] ~= b[i] then
      return false
    end
  end

  return true
end


local function update()
  local changed = force_pending
  force_pending = false

  local current, paused = api.nvim_get_current_win(), suspended()

  if paused ~= previous_suspended or current ~= previous_current then
    changed = true
  end

  previous_suspended, previous_current = paused, current

  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local buf = api.nvim_win_get_buf(win)
    local old = windows[win]

    if not config.enabled or not eligible(win, buf, current) then
      if old then
        windows[win], changed = nil, true
      end
    else
      local cursor = api.nvim_win_get_cursor(win)
      local row, col = cursor[1] - 1, cursor[2]
      local tick = api.nvim_buf_get_changedtick(buf)
      local paragraph = old and old.buf == buf and old.tick == tick and old.paragraph

      if not paragraph or row < paragraph.first or row > paragraph.last then
        paragraph = scope.paragraph(
        function(i)
          return api.nvim_buf_get_lines(buf, i, i + 1, true)[1]
        end,
        api.nvim_buf_line_count(buf),
        row,
        config.max_paragraph_lines,
        config.max_paragraph_bytes
        )
      end

      local range = scope.range(paragraph, row, col, config.mode)

      if not old or old.buf ~= buf or old.tick ~= tick or not same(old.range, range) then
        changed = true
      end

      windows[win] = {
        buf = buf,
        tick = tick,
        paragraph = paragraph,
        range = range
      }
    end
  end
  -- Changing an ephemeral range does not invalidate previously painted rows.
  -- Invalidate the screen only on a scope/content/state change, not every move.
  if changed then
    vim.cmd('redraw!')
  end
end


local function queue(force)
  force_pending = force_pending or force or false

  if pending then
    return
  end

  pending = true

  vim.schedule(function()
    pending = false
    if config then
      update()
    end
  end)
end


local function decorate(_, win, buf)
  local state = windows[win]

  if not state or state.buf ~= buf or state.tick ~= api.nvim_buf_get_changedtick(buf) then
    return false
  end

  local r = state.range

  local function mark(start_row, start_col, end_row, end_col)
    if start_row == end_row and start_col == end_col then
      return
    end

    api.nvim_buf_set_extmark(buf, ns, start_row, start_col, {
      end_row = end_row,
      end_col = end_col,
      hl_group = dim_group,
      priority = config.priority,
      ephemeral = true,
      strict = false
    })
  end

  mark(0, 0, r[1], r[2])
  mark(r[3], r[4], api.nvim_buf_line_count(buf), 0)

  return false
end


function M.setup(opts)
  local next_config = validate(opts or {})
  config = next_config
  windows, allowed = {}, {}

  for _, ft in ipairs(config.filetypes) do
    allowed[ft] = true
  end

  dim_group = highlight.refresh(config)
  group = api.nvim_create_augroup('ProseFocus', { clear = true })

  api.nvim_set_decoration_provider(ns, {
    on_start = function()
      return config.enabled and not suspended()
    end,
    on_win = decorate,
  })

  api.nvim_create_autocmd({
    'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'TextChangedP',
    'BufEnter', 'BufWinEnter', 'WinEnter', 'TabEnter', 'FileType', 'ModeChanged',
  }, { group = group,
      callback = function()
        queue(false)
      end
  })

  api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(event)
      windows[tonumber(event.match)] = nil
    end
  })

  api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(event)
      for win, state in pairs(windows) do
        if state.buf == event.buf then windows[win] = nil end
      end
    end
  })

  local function colors()
    dim_group = highlight.refresh(config)
    queue(true)
  end

  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = colors
  })

  api.nvim_create_autocmd('OptionSet', {
    group = group,
    pattern = { 'termguicolors', 'background' },
    callback = colors
  })

  api.nvim_create_user_command('ProseFocus',
    function(args)
      local action = args.args
      if action == '' or action == 'toggle' then
        M.toggle()
      elseif action == 'enable' then
        M.enable()
      elseif action == 'disable' then
        M.disable()
      else
        M.set_mode(action)
      end
    end,
    { nargs = '?',
      force = true,
      complete = function()
        return { 'toggle', 'enable', 'disable', 'sentence', 'paragraph' }
      end,
      desc = 'Dim prose outside the current sentence or paragraph'
    }
  )

  queue(true)
end


local function ensure_setup()
  if not config then
    M.setup({})
  end
end


function M.enable()
  ensure_setup()
  config.enabled = true
  queue(true)
end


function M.disable()
  ensure_setup()
  config.enabled = false
  queue(true)
end


function M.toggle()
  ensure_setup()
  config.enabled = not config.enabled
  queue(true)
end


function M.set_mode(mode)
  assert(mode == 'sentence' or mode == 'paragraph', 'prose_focus: invalid mode')
  ensure_setup()
  config.mode = mode
  queue(true)
end


function M.refresh()
  ensure_setup()
  dim_group = highlight.refresh(config)
  windows = {}
  queue(true)
end


return M
