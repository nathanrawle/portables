# Reshaping tmux panes

The prefix is Ctrl+backslash. Press it, release it, then press Shift+arrow to
pull the active pane to that edge of the window:

| Key after prefix | Result |
| --- | --- |
| Shift+Left | Full-height column on the left |
| Shift+Right | Full-height column on the right |
| Shift+Up | Full-width row at the top |
| Shift+Down | Full-width row at the bottom |

The pane and its running program survive. Its old space collapses, and the
other panes retain their split structure. The moved pane stays focused; a
zoomed window becomes unzoomed so the new layout is visible. A single-pane
window stays unchanged.

Each move initially uses tmux's default half-size split, then runs
`select-layout -E` twice on the moved pane, exactly like pressing prefix+E
twice. This equalises nearby split groups according to tmux's usual behaviour;
it does not recursively equalise every group in the window.

To turn the bottom-right pane of a four-pane grid into a middle column:

1. Select that pane and press prefix, then Shift+Right.
2. Select the pane above its original position and press prefix, then Shift+Right.
3. The original pane is now the full-height middle column. The two E operations
   make the three columns approximately equal in width.

Ctrl+Shift+Left/Right still swaps panes between existing slots. For manual
resizing, prefix then Ctrl+arrow adjusts by one cell, or Alt+arrow by five.
To set a particular width, select the pane and use the tmux command prompt
(prefix then Ctrl+backslash), entering `resize-pane -x 33%`.

After installing the updated configuration, reload it with prefix then `r`.
