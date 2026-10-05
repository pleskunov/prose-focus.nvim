# prose-focus.nvim

Keep the sentence or paragraph under the cursor at its normal appearance and
dim the surrounding prose. 

Pure Lua; no runtime dependencies beyond Neovim.

Targets Neovim 0.11+ and current stable releases, using public APIs.

## Install without a plugin manager

In the Neovim instance where you write, find its configuration directory:

```vim
:lua print(vim.fn.stdpath('config'))
```

Extract this repository into:

```text
<config>/pack/prose/start/prose-focus.nvim/
```

The file `lua/prose_focus/init.lua` must be directly below that directory.
Add this to your `init.lua`:

```lua
vim.cmd.packadd('prose-focus.nvim')

require('prose_focus').setup({
  mode = 'paragraph', -- or 'sentence'
  dim = 0.60,        -- 0 = normal foreground; 1 = background
})

vim.keymap.set('n', '<leader>uf', '<cmd>ProseFocus toggle<cr>',
  { desc = 'Toggle prose focus' })
```

The explicit `packadd` makes the package available while `init.lua` is running.
If a plugin manager already loads this directory, call `setup` without `packadd`.
No mappings are installed automatically. Nothing is enabled until `setup` or
one of the public control functions is called.

For a new unnamed buffer, use `:setfiletype text`. The default allowlist ignores
buffers without a prose filetype. The plugin never changes your filetype.

## Controls

```vim
:ProseFocus
:ProseFocus toggle
:ProseFocus enable
:ProseFocus disable
:ProseFocus sentence
:ProseFocus paragraph
```

Changing mode preserves the enabled/disabled state. Lua equivalents:

```lua
local focus = require('prose_focus')
focus.toggle()
focus.enable()
focus.disable()
focus.set_mode('sentence')
focus.refresh()
```

## Configuration

This is the complete default configuration. Each `setup` starts from these
defaults, replaces previous configuration, and recreates its own autocmd group.
Unknown options and invalid values produce an error.

```lua
require('prose_focus').setup({
  enabled = true,
  mode = 'paragraph',
  filetypes = { 'text', 'markdown', 'typst', 'rst', 'asciidoc', 'org' },
  dim = 0.60,
  highlight = false,
  priority = 200,
  active_only = false,
  suspend_in_visual = true,
  max_paragraph_lines = 2000,
  max_paragraph_bytes = 262144,
})
```

| Option | Meaning |
| --- | --- |
| `enabled` | Initial global state. |
| `mode` | `paragraph` or `sentence`. |
| `filetypes` | Exact filetype allowlist, replaced as a whole. `{}` permits every normal buffer; it does not detect prose. |
| `dim` | Fraction of the distance from `Normal` foreground toward its background. Applies only to automatic RGB mixing. |
| `highlight` | `false` for automatic dimming, or an existing highlight group name such as `Comment`. |
| `priority` | Extmark highlight priority, an integer from 0 to 65535. Adjust if other decorations compete. |
| `active_only` | If true, apply focus only in the current window. Other windows retain their usual appearance. |
| `suspend_in_visual` | Temporarily remove dimming in Visual/Select mode, so selections remain clear. Applies to all windows. |
| `max_paragraph_lines` | Maximum paragraph size to scan. |
| `max_paragraph_bytes` | Maximum paragraph bytes, including inter-line newlines, to scan. |

Special buffers and floating windows are always excluded. With the default
`active_only = false`, each eligible split has its own focus, even when two
splits show the same buffer at different cursor positions.

## Colors

With `termguicolors` enabled and explicit `Normal` foreground/background colors,
the plugin derives `ProseFocusDim` from the current theme:

```text
dimmed foreground = foreground + dim * (background - foreground)
```

This is ordinary RGB-channel interpolation. It supplies no fixed color palette,
changes no existing highlight group, and leaves the focused text untouched.
Outside the focus, syntax foregrounds/styles are intentionally replaced with a
uniform dim foreground. The default `dim = 0.60` works in both light and dark
themes. Choosing `1` may make text effectively invisible.

For transparent themes with no explicit `Normal` background, or with true color
disabled, `ProseFocusDim` links to `Comment`. A terminal's real background cannot
be inferred reliably. The strength of this fallback depends on your theme; a
theme whose comments are bright will not produce strong dimming. The fallback
also inherits the theme's comment styles.

To use only an existing theme group, without interpolation:

```lua
require('prose_focus').setup({ highlight = 'Comment' })
```

`ColorScheme` updates the generated highlight automatically. After manually
changing `Normal` with `:highlight`, call `require('prose_focus').refresh()`.
Window-specific `winhighlight`/highlight namespaces and `NormalNC` palettes are
not resolved by the automatic mixer; it uses global `Normal`. Choose an explicit
highlight group if another plugin supplies per-window palettes.

## Text rules

- A paragraph is a run of nonblank lines. Empty and whitespace-only lines are
  separators. Soft wrapping does not create a paragraph boundary.
- In sentence mode, `.`, `!`, or `?` ends a sentence when followed by ASCII
  whitespace, possibly after closing `)`, `]`, `"`, or `'`. A paragraph boundary
  always ends a sentence. Final text without punctuation is still a sentence.
- Whitespace after a sentence stays with that sentence. Focus changes on the
  first character of the next sentence, avoiding a separate whitespace focus.
- On a blank separator line, only that line is focused. Surrounding prose dims.
- If a paragraph exceeds either scan limit, the entire cursor line is focused
  in either mode. Increase the limits if your prose contains unusually large
  paragraphs. No notification interrupts writing.

These are deliberately small prose heuristics inspired by Vim sentence rules,
not exact implementations of `is`/`ip`: nroff macros and `'cpoptions'` are ignored.
Abbreviations such as `Dr. Smith` split at the period; decimal points such as
`3.14` do not. Curly closing quotes, CJK punctuation, Markdown document structure,
code fences, and linguistic abbreviation dictionaries are not parsed. Unicode
text is preserved and ranges use byte positions, as Neovim requires.

## Implementation and performance

| File | Responsibility |
| --- | --- |
| `lua/prose_focus/init.lua` | Configuration, commands, autocmds, per-window cache, decoration provider. |
| `lua/prose_focus/scope.lua` | Pure paragraph and sentence boundary calculation. |
| `lua/prose_focus/highlight.lua` | Theme-derived highlight and fallback. |

`nvim_set_decoration_provider` creates at most two ephemeral extmarks per window:
one before the focus and one after. Neovim renders them for that window's redraw;
no persistent marks accumulate in the buffer. There is no per-line decoration
callback, external process, language server, Tree-sitter parser, timer, animation,
or polling loop.

Autocmd updates are merged with `vim.schedule` into the next event-loop turn,
without a debounce delay. Paragraph contents and sentence starts are cached per
window and buffer changedtick. Moving within a cached paragraph reuses that data.
Edits invalidate it. Only the current paragraph is scanned, within the configured
limits; the entire document is never copied or parsed for a cursor update.

Changes to the focus, content, or enabled state trigger `redraw!`. This explicit
invalidation is needed to repaint rows containing the old ephemeral highlight.
Cursor movement inside an unchanged focus does not force that full redraw.
This is a deliberate simplicity tradeoff; screen redraw cost still depends on
your terminal, visible windows, and other plugins. Performance is not benchmarked.

Native text-object selection is interactive; the isolated scope module avoids those side effects. 
To extend sentence rules, edit `scope.prepare` and add examples to `tests/unit.lua`.

Disable with `:ProseFocus disable`. To remove permanently, remove the setup call
and package directory, then restart Neovim. The inactive generated highlight
group can remain harmlessly defined for the rest of the current session.

## Tests

From the repository root:

```sh
nvim --clean --headless -l tests/run.lua
```

The suite covers boundaries, paragraph separators, wrapped logical paragraphs,
UTF-8 byte offsets, whitespace ownership, scan limits, color interpolation, and
Neovim lifecycle/state preservation. It uses only Lua and Neovim.
