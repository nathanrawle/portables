# Reshaping tmux panes

The prefix is Ctrl+backslash. Press it, release it, then press Shift+arrow to
reshape the active pane beside its neighbour:

| Key after prefix | Result |
| --- | --- |
| Shift+Left/Right | Full-height column to the left/right of its former vertical neighbour |
| Shift+Up/Down | Full-width row above/below its former horizontal neighbour |

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

Shift+Right instead places B in the middle and D on the right. Up/Down apply
that same rule to rows. The helper prefers the neighbour above for column
moves, or the neighbour on the left for row moves, falling back to the other
side. It first promotes that neighbour to the nearest window edge, then
inserts the active pane on the requested side. If there is no perpendicular
neighbour, the active pane moves directly to the requested edge.

Pane IDs and running programs survive. The vacated spaces collapse, retaining
the remaining split structure. The moved pane stays focused; a zoomed window
becomes unzoomed so the new layout is visible. A single-pane window stays
unchanged.

Each move finishes with `select-layout -E` twice on the moved pane. In the
examples above, this makes the three columns equal in width, allowing for
cell rounding. It does not recursively equalise every nested group.

Ctrl+Shift+Left/Right still swaps panes between existing slots. For manual
resizing, prefix then Ctrl+arrow adjusts by one cell, or Alt+arrow by five.
To set a particular width, select the pane and use the tmux command prompt
(prefix then Ctrl+backslash), entering `resize-pane -x 33%`.

Link both the configuration and its helper with `relink .config/tmux`, then
reload with prefix followed by `r`.
