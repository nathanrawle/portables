# Reshaping tmux panes

Press Ctrl+Shift+arrow, without a prefix, to move the active pane through the
window's split structure:

| Key | Direction |
| --- | --- |
| Ctrl+Shift+Left/Right | Move through columns |
| Ctrl+Shift+Up/Down | Move through rows |

With pane 4 active, repeated Ctrl+Shift+Left produces this sequence:

```text
124 → 122 → 122 → 142 → 12 → 412
134   134   143   143   43   413
```

Repeated Ctrl+Shift+Right traverses those layouts in reverse. These diagrams show
which regions each pane occupies; widths and heights follow tmux's sizing
rules. Up/Down use the same transitions with rows and columns exchanged.

Each press makes one structural transition:

- Enter a neighbouring region on the side the active pane came from.
- Cross an adjacent sibling within that region.
- Expand out of the region when there is no further sibling in that direction.

Horizontal entry uses the neighbouring region's bottom branch; vertical entry
uses its right branch. Entering a single full-height pane creates a lower
split, while entering a single full-width pane creates a right split.
Movement follows the current split structure, without saved movement history.
Equivalent nested containers with the same orientation are treated as one group.

Touching a window edge does not prevent expansion. Movement stops when the
pane is already outside every relevant split group at that edge. Further
presses leave the layout and zoom state unchanged. Single-pane windows also
stay unchanged.

Pane IDs and running programs survive. The moved pane stays focused; successful
movement reveals a zoomed window's new layout. Each successful move finishes
with `select-layout -E` twice on the moved pane, like two presses of prefix+E.
This equalises nearby groups, rather than every group recursively. A failed
layout application restores the original pane order, layout, focus and zoom.

Ctrl+These bindings replace the previous Ctrl+Shift+Left/Right pane swaps. The
prefix is Ctrl+backslash. For manual resizing, prefix then Ctrl+arrow adjusts
by one cell, or Alt+arrow by five.
To set a particular width, select the pane and use the tmux command prompt
(prefix then Ctrl+backslash), entering `resize-pane -x 33%`.

To use this checkout, run from its root:

```bash
bash ./symlinks --force .config/tmux/tmux.conf .config/tmux/reshape-pane
```

Then reload with prefix followed by `r`. `relink` instead uses the checkout
identified by `$PORTABLES`. Once the helper is linked to this checkout, edits
to it take effect on the next keypress.
