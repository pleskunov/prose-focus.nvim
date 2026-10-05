local M = {}


-- `amount` is the fraction of the distance from foreground to background.
function M.mix(fg, bg, amount)
  local result = 0
  for _, shift in ipairs({ 65536, 256, 1 }) do

    local f = math.floor(fg / shift) % 256
    local b = math.floor(bg / shift) % 256

    result = result + math.floor(f + (b - f) * amount + 0.5) * shift
  end

  return result
end


function M.refresh(config)
  if config.highlight then
    return config.highlight
  end

  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })

  if vim.o.termguicolors and normal.fg and normal.bg then
    local fg, bg = normal.fg, normal.bg

    if normal.reverse then
      fg, bg = bg, fg
    end

    vim.api.nvim_set_hl(0, 'ProseFocusDim', {
      fg = M.mix(fg, bg, config.dim), nocombine = true,
    })
  else
    -- A transparent terminal's actual background is unknown. Never guess it.
    vim.api.nvim_set_hl(0, 'ProseFocusDim', { link = 'Comment' })
  end

  return 'ProseFocusDim'
end


return M
