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
- Pair locally when moving perpendicular to a group of three or more siblings.
- Expand out of smaller containing regions when there is no further sibling in that direction.

When approaching an individual sibling, horizontal movement joins below it,
while vertical movement joins to its right. When entering a group, horizontal
movement chooses its bottom branch and vertical movement chooses its right
branch, inserting the active pane on the side it came from.

For example, with pane 4 active, successive Shift+Left presses now produce:

```text
124 → 122 → 12 → 122 → 142 → 12 → 412
134   134   13   143   143   43   413
            14
```

Perpendicular movement in a group of three or more siblings pairs with the
previous sibling (above or left), falling back to the next sibling when the
active pane is first. The pair forms on the requested side, leaving other
sibling regions outside it. A neighbouring sibling may itself be a group.
Two-child groups retain their existing outward expansion behaviour.

For example, with pane 4 active, two Shift+Up presses stay between panes 1 and 3:

```text
123            1243            143
143 → Up →             → Up → 123
```

Two Shift+Down presses reverse this example. Left/Right use the transposed rule.

An expansion remembers one origin hint on the moved pane: a neighbouring pane
from its former region and the reverse direction. The next successful reshape
can use this hint to choose the branch to enter, rather than the default
bottom/right branch. For example, with pane 4 active:

```text
143            444              143
123 → Up →     123 → Down →      123
```

Left/Right follow the transposed rule. Focus changes and resizing do not affect
a valid hint. A boundary no-op preserves it; another successful entry or local
pairing clears it, and another expansion replaces it. If the origin is killed,
moves to another window, or is no longer reachable from the adjacent region’s
facing edge, movement falls back to the normal structural rule.

Hints do not save layouts or form an undo stack. Opposite-direction presses
still follow the entry-first rules; longer sequences can pass through different
intermediate layouts rather than retracing exactly.
Diagrams show pane regions, while proportions follow tmux's sizing rules.
Equivalent nested containers with the same orientation are treated as one group.

Touching a window edge does not prevent expansion. Movement stops when the
pane is already outside every relevant split group at that edge. Further
presses leave the layout and zoom state unchanged. Single-pane windows also
stay unchanged.

Reshaping supports tiled windows using the legacy checksummed layout format,
validated with tmux 3.6b and 3.7c. JSON layouts emitted by tmux 3.8 release
candidates are unsupported: the helper exits with status 2 and reports
`reshape-pane: tmux JSON layouts are not supported; use a tmux version with legacy layouts`.
Rejection preserves pane order, running processes, layout, focus, zoom and origin
hints. JSON support requires separate work, including reliable failure rollback.

If a window contains
any floating pane, the helper exits with status 2 and reports
`reshape-pane: windows containing floating panes are not supported`, even when
the active pane is tiled. The window, focus, zoom and origin hints stay unchanged.
Remove or move the floating panes out of the window before reshaping it.

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

Reshapes from multiple clients are serialized per window with tmux `wait-for`
locks. The lock covers state capture, movement, origin updates and failure
rollback; reshapes in different windows remain independent.
