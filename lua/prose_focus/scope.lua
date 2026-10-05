-- Pure range calculation.
-- Positions are zero-based byte offsets, end-exclusive.


local M = {}


local function blank(line)
  return line:match('^%s*$') ~= nil
end


local function line_range(row, line)
  return { row, 0, row, #line }
end


-- Read only the current paragraph. `read(row)` returns one buffer line.
-- Limits keep a malformed/generated file from monopolizing the UI thread.
function M.paragraph(reader, count, row, max_lines, max_bytes)
  local current = reader(row)

  if blank(current) then
    return { first = row, last = row, lines = { current }, blank = true }
  end

  local first, last, bytes, lines = row, row, #current, { [row] = current }

  if bytes > max_bytes then
    return { first = row, last = row, lines = { current }, limited = true }
  end

  for _, direction in ipairs({ -1, 1 }) do
    local i = row + direction

    while i >= 0 and i < count do
      local line = reader(i)

      if blank(line) then
        break
      end

      bytes = bytes + #line + 1

      if last - first + 2 > max_lines or bytes > max_bytes then
        return { first = row, last = row, lines = { current }, limited = true }
      end

      lines[i] = line

      first, last = math.min(first, i), math.max(last, i)

      i = i + direction
    end
  end

  local ordered = {}

  for i = first, last do
    ordered[#ordered + 1] = lines[i]
  end

  return { first = first, last = last, lines = ordered }
end


local function position(paragraph, offset)
  for i, line in ipairs(paragraph.lines) do
    if offset <= #line then
      return paragraph.first + i - 1, offset
    end

    offset = offset - #line - 1
  end

  local n = #paragraph.lines

  return paragraph.last, #paragraph.lines[n]
end


-- Prepare once per paragraph/change, not once per cursor movement.
function M.prepare(paragraph)
  if paragraph.blank or paragraph.limited then
    return
  end

  local text = table.concat(paragraph.lines, '\n')
  local starts = { 0 }
  local from = 1

  -- Same basic ASCII punctuation/closing-quote rule as Vim sentences.
  -- Deliberately excludes nroff macros and the 'cpoptions' J exception.
  while true do
    local _, finish = text:find("[.!?][%)%]%\"']*%s+", from)

    if not finish then
      break
    end

    if finish < #text then
      starts[#starts + 1] = finish
    end

    from = finish + 1
  end

  paragraph.starts, paragraph.bytes = starts, #text
end


function M.range(paragraph, row, col, mode)
  if paragraph.blank or paragraph.limited then
    return line_range(row, paragraph.lines[1])
  end

  if mode == 'paragraph' then
    return { paragraph.first, 0, paragraph.last, #paragraph.lines[#paragraph.lines] }
  end

  if not paragraph.starts then
    M.prepare(paragraph)
  end

  local offset = math.min(col, #paragraph.lines[row - paragraph.first + 1])

  for i = 1, row - paragraph.first do
    offset = offset + #paragraph.lines[i] + 1
  end

  -- Whitespace after punctuation belongs to the preceding sentence.
  local starts, lo, hi = paragraph.starts, 1, #paragraph.starts

  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if starts[mid] <= offset then
      lo = mid
    else
      hi = mid - 1
    end
  end

  local start_row, start_col = position(paragraph, starts[lo])
  local end_row, end_col = position(paragraph, starts[lo + 1] or paragraph.bytes)

  return { start_row, start_col, end_row, end_col }
end


return M
