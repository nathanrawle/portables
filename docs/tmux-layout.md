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

Reshaping requires tmux 3.8 or newer and `jq`. The helper reads and writes native
version-2 JSON layouts. Pane IDs, indices and running programs survive; layout
application uses tmux's pane indices because embedded pane IDs are ignored by
the native parser. Malformed layouts, unsupported versions and snapshots that
do not match the current pane indices are rejected before changing the window.

Floating panes can coexist with tiled panes. Reshaping moves only the tiled
tree and preserves floating positions, dimensions and stacking. With a floating
pane active, Shift+arrow instead moves it by five cells. Directly invoking the
helper on a floating pane reports `reshape-pane: use move-pane to move a floating pane`.

The moved pane stays focused; successful movement reveals a zoomed window's new
layout. Each successful move finishes with two local equalization passes, like
two presses of prefix+E. A pass starts at the pane's nearest split group and
walks outward until a group's allocation changes. This equalizes nearby groups,
rather than every group recursively, while reserving the space each branch needs.
A failed layout application restores the original JSON layout, focus, zoom and
origin hint, including floating geometry and stacking.

Prefix+E and the tiled Ctrl+`.` height toggle also use this helper. tmux 3.8's
native `select-layout -E` skips nested containers when counting siblings and can
leave panes extending beyond the window; the helper includes those containers
when distributing space. Single-pane and boundary no-ops preserve zoom.

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

See [tmux 3.8 features](tmux-features.md) for floating terminals, sizing shortcuts,
copy mode, clipboard behavior and the other additions since 3.6b.
