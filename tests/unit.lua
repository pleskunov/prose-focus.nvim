local scope = require('prose_focus.scope')
local highlight = require('prose_focus.highlight')
local tests = 0
local function equal(actual, expected)
  if type(expected) == 'table' then
    assert(#actual == #expected, 'different result lengths')
    for i, value in ipairs(expected) do
      assert(actual[i] == value, ('item %d: expected %s, got %s'):format(i, value, actual[i]))
    end
  else
    assert(actual == expected, ('expected %s, got %s'):format(expected, actual))
  end
  tests = tests + 1
end

local function paragraph(lines, row, max_lines, max_bytes)
  return scope.paragraph(function(i) return lines[i + 1] end,
    #lines, row, max_lines or 2000, max_bytes or 262144)
end
local function range(lines, row, col, mode)
  return scope.range(paragraph(lines, row), row, col, mode or 'sentence')
end

equal(range({ 'One. Two! Three?' }, 0, 0), { 0, 0, 0, 5 })
equal(range({ 'One. Two! Three?' }, 0, 3), { 0, 0, 0, 5 })
equal(range({ 'One. Two! Three?' }, 0, 4), { 0, 0, 0, 5 })
equal(range({ 'One. Two! Three?' }, 0, 5), { 0, 5, 0, 10 })
equal(range({ 'One. Two! Three?' }, 0, 10), { 0, 10, 0, 16 })
equal(range({ 'One. Two! Three?' }, 0, 16), { 0, 10, 0, 16 })
equal(range({ 'One. Two! Three?' }, 0, 999), { 0, 10, 0, 16 })
equal(range({ 'A sentence', 'across lines. Next.' }, 1, 3), { 0, 0, 1, 14 })
equal(range({ 'A sentence', 'across lines. Next.' }, 1, 14), { 1, 14, 1, 19 })
equal(range({ 'One.', 'Two.' }, 0, 4), { 0, 0, 1, 0 })
equal(range({ 'One.', 'Two.' }, 1, 0), { 1, 0, 1, 4 })
equal(range({ '"Go!" Then stop.' }, 0, 3), { 0, 0, 0, 6 })
equal(range({ '(Go!) Then stop.' }, 0, 6), { 0, 6, 0, 16 })
equal(range({ 'Go.] Next.' }, 0, 5), { 0, 5, 0, 10 })
equal(range({ "Go.' Next." }, 0, 5), { 0, 5, 0, 10 })
equal(range({ 'One.\tTwo.' }, 0, 5), { 0, 5, 0, 9 })
equal(range({ 'Value 3.14 stays. Next.' }, 0, 10), { 0, 0, 0, 18 })
equal(range({ 'Wait... Next.' }, 0, 8), { 0, 8, 0, 13 })
equal(range({ 'Dr. Smith.' }, 0, 4), { 0, 4, 0, 10 }) -- documented heuristic
equal(range({ 'Été. 猫 sleeps.' }, 0, 7), { 0, 7, 0, #'Été. 猫 sleeps.' })
equal(range({ '🙂. Next.' }, 0, 0), { 0, 0, 0, 6 })
equal(range({ 'é. Next.' }, 0, 5), { 0, 5, 0, #'é. Next.' })
equal(range({ 'No punctuation' }, 0, 5), { 0, 0, 0, 14 })
equal(range({ '  One.   ' }, 0, 8), { 0, 0, 0, 9 })
equal(range({ '' }, 0, 0), { 0, 0, 0, 0 })
equal(range({ 'Above.', ' \t', 'Below.' }, 1, 1), { 1, 0, 1, 2 })
equal(range({ 'Above.', '', 'A', 'B', '', 'Below.' }, 3, 0, 'paragraph'), { 2, 0, 3, 1 })
equal(range({ 'Above.', ' \t', 'Below.' }, 2, 0, 'paragraph'), { 2, 0, 2, 6 })
equal(range({ 'First', 'Second' }, 1, 2, 'paragraph'), { 0, 0, 1, 6 })
local p = paragraph({ 'a', 'b', 'c' }, 1, 2)
equal(p.limited, true)
equal(scope.range(p, 1, 0, 'sentence'), { 1, 0, 1, 1 })
p = paragraph({ 'abc', 'def' }, 0, 20, 6)
equal(p.limited, true)
equal(scope.range(p, 0, 0, 'paragraph'), { 0, 0, 0, 3 })
p = paragraph({ 'abc', 'def' }, 0, 20, 7)
equal(scope.range(p, 0, 0, 'paragraph'), { 0, 0, 1, 3 })
equal(highlight.mix(0xffffff, 0x000000, 0), 0xffffff)
equal(highlight.mix(0xffffff, 0x000000, 1), 0x000000)
equal(highlight.mix(0xffffff, 0x000000, 0.5), 0x808080)
equal(highlight.mix(0x000000, 0xffffff, 0.5), 0x808080)
equal(highlight.mix(0x123456, 0xabcdef, 0), 0x123456)
print(('prose_focus: %d unit assertions passed'):format(tests))
return tests
