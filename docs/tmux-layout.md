# Reshaping tmux panes

Press Shift+arrow, without a prefix, to move the active pane through the
window's split structure:

| Key | Direction |
| --- | --- |
| Shift+Left/Right | Move through columns |
| Shift+Up/Down | Move through rows |

With pane 3 active, two Shift+Up presses enter pane 2 and then expand above it:

```text
12          123          13
13 → Up →   144 → Up →   12
14                      14
```

Two Shift+Down presses reverse this example. Left/Right follow the same rules
with rows and columns exchanged.

Each press makes one structural transition:

- Enter an adjacent pane or group before crossing it.
- Expand out of the containing region when there is no further sibling in that direction.

When approaching an individual sibling, horizontal movement joins below it,
while vertical movement joins to its right. When entering a group, horizontal
movement chooses its bottom branch and vertical movement chooses its right
branch, inserting the active pane on the side it came from.

For example, with pane 4 active, successive Shift+Left presses now produce:

```text
124 → 122 → 12 → 142 → 12 → 412
134   134   13   143   43   413
            14
```

Movement follows the current split structure without saved movement history.
Opposite-direction presses follow the same entry-first rules; longer sequences
can pass through different intermediate layouts rather than retracing exactly.
Diagrams show pane regions, while proportions follow tmux's sizing rules.
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

Ctrl+Shift+Left/Right retains the original pane swaps. The prefix is
Ctrl+backslash. For manual resizing, prefix then Ctrl+arrow adjusts by one cell,
or Alt+arrow by five. To set a particular width, select the pane and use the
tmux command prompt (prefix then Ctrl+backslash), entering `resize-pane -x 33%`.

To use this checkout, run from its root:

```bash
bash ./symlinks --force .config/tmux/tmux.conf .config/tmux/reshape-pane
```

Then reload with prefix followed by `r`. `relink` instead uses the checkout
identified by `$PORTABLES`. Once the helper is linked to this checkout, edits
to it take effect on the next keypress.
