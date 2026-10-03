# Reshaping tmux panes

The prefix is Ctrl+backslash. Press it, release it, then press Shift+arrow to
move the active pane one adjacent column or row in that direction:

| Key after prefix | Result |
| --- | --- |
| Shift+Left/Right | Move one column left/right |
| Shift+Up/Down | Move one row up/down |

For example, select D in either layout and press prefix, then Shift+Left:

```text
Three panes                 Four panes
┌─────┬─────┐               ┌─────┬─────┐
│     │  B  │               │  A  │  B  │
│  A  ├─────┤               ├─────┼─────┤
│     │  D  │               │  C  │  D  │
└─────┴─────┘               └─────┴─────┘
        ↓                           ↓
┌─────┬─────┬─────┐         ┌─────┬─────┬─────┐
│     │     │     │         │  A  │     │     │
│  A  │  D  │  B  │         ├─────┤  D  │  B  │
│     │     │     │         │  C  │     │     │
└─────┴─────┴─────┘         └─────┴─────┴─────┘
```

Each invocation moves only toward the adjacent pane. At the window boundary,
pressing outward does nothing: movement never wraps to the opposite edge.
Repeated presses move through adjacent slots one at a time.

For a corner pane moving inward, the helper can promote its perpendicular
neighbour at the existing edge before inserting the active pane beside it.
This produces the full-height middle column illustrated above. Elsewhere,
movement swaps adjacent full-span panes or inserts the active pane beside an
individual neighbour. Moving toward stacked panes may therefore change the
active pane's height; columns of stacked panes are not moved as a group.

Pane IDs and running programs survive. The vacated spaces collapse, retaining
the remaining split structure. The moved pane stays focused; a zoomed window
becomes unzoomed so the new layout is visible. A single-pane window stays
unchanged.

Each successful move finishes with `select-layout -E` twice on the moved pane. In the
examples above, this makes the three columns equal in width, allowing for
cell rounding. It does not recursively equalise every nested group.

Ctrl+Shift+Left/Right still swaps panes between existing slots. For manual
resizing, prefix then Ctrl+arrow adjusts by one cell, or Alt+arrow by five.
To set a particular width, select the pane and use the tmux command prompt
(prefix then Ctrl+backslash), entering `resize-pane -x 33%`.

To use this checkout, run from its root:

```bash
bash ./symlinks --force .config/tmux/tmux.conf .config/tmux/reshape-pane
```

Then reload with prefix followed by `r`. `relink` instead uses the checkout
identified by `$PORTABLES`. Once the helper is linked to this checkout, edits
to it take effect on the next keypress.
