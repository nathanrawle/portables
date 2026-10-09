# tmux features since 3.6b

Portables requires stable tmux 3.8 or newer and `jq`. The tmux installation and
configuration hooks report older or prerelease versions instead of silently
accepting them. Packages still come from the machine's existing package manager;
the hook does not download or compile tmux itself.

The feature inventory comes from the upstream
[3.7 and 3.8 changes](https://github.com/tmux/tmux/blob/3.8/CHANGES).
Use the installed `man tmux` for command details.

## Daily shortcuts

The prefix is **Ctrl+backslash**. Press and release it, then press the next key.
Uppercase letters mean Shift plus that letter; Alt means the left Option key in
the configured macOS Ghostty setup.

| Key | Action |
| --- | --- |
| Prefix, `t` | Open the existing modal terminal popup |
| Prefix, `T` | Open a centered floating terminal at 70% width and height |
| Prefix, Alt+`t` | Edit the current pane's title |
| Prefix, `@` | Float a tiled pane or return a floating pane to its tiled position |
| Prefix, `G` | Enter native floating-pane move/resize controls |
| Prefix, Tab | Fuzzy-switch windows |
| Prefix, Shift+Tab | Fuzzy-switch sessions |
| Prefix, `E` | Equalize the nearest split group, walking outward if already equal |
| Prefix, `[` | Enter vi copy mode |
| Prefix, `>` | Open the native pane menu |
| Prefix, `C` | Inspect and edit options, bindings, hooks and environment variables |
| Prefix, `?` | Show annotated key bindings |

Prefix, `g` still opens lazygit, and Ctrl+`f` still opens `taw`. tmux's native
prefix, `*` remains available for its smaller default floating pane.

### Work with floating panes

Unlike a popup, a floating pane stays available when you select another pane.
The `T` terminal starts in the current directory and remains visible above a
zoomed tiled pane. Its title bar provides native controls for floating/tiling,
zooming and closing. The close control asks before killing the pane.

Shift+arrows move the active floating pane by five cells. Mouse dragging can move
and resize it. After prefix, `G`, use:

| Key | Position or size |
| --- | --- |
| Arrows | Snap to the corresponding edge |
| `1` / `2` / `3` / `4` | Snap to top-left / top-right / bottom-left / bottom-right |
| Alt+arrows | Fill the corresponding half of the window |
| Alt+`1` through Alt+`4` | Fill the corresponding quarter |
| `0` | Fill the window |
| `,` / `.` | Open position / position-and-size menus |

The move table handles one operation, then returns to normal keys. Each entry
requires prefix, `G` again. The pane menu also exposes move, resize and tile
actions. The second status row lists all panes and can be clicked to select one.

These commands are useful from the tmux prompt for temporary modal work:

```tmux
new-pane -O -D -C -x 80% -y 80% -c '#{pane_current_path}' lazygit
```

`-O` makes the pane modal, `-D` closes it with Escape or Ctrl+C, and `-C` closes
it when clicked outside. `-K` additionally passes all keys, including the tmux
prefix, to a modal pane. `new-pane -W` waits for the command to exit when used
from a script. Popups remain useful for the existing terminal, lazygit and `taw`
workflows; floating panes do not replace them automatically.

### Resize and reshape

Ctrl+`,` cycles the active pane's content width through 25%, 33%, 50%, 66% and
75% of the window. Ctrl+`=` and Ctrl+`-` grow and shrink its width by 20 cells.
Tiled width adjustment retains its existing edge/neighbor behavior; floating
adjustment changes only the floating pane.

Ctrl+`.` expands height toward 95%. A second press equalizes a tiled stack or
restores a floating pane's previous height. Resizing the expanded pane or its
window invalidates the remembered toggle state. Floating sizing leaves tiled
geometry and zoom underneath it alone.

With a tiled pane active, Shift+arrows retain the structural transitions described
in [tmux layouts](tmux-layout.md), including when floating panes share the window.
Ctrl+Shift+arrows retain pane swapping.

The JSON helper also implements local equalization. Native tmux 3.8 equalization
can overallocate space when a sibling is a nested container. The helper includes
containers in its allocation, reserves branch minimums, and preserves native JSON
pane indices, floating geometry and stacking. Failed application restores the
original layout, focus, zoom and origin hint.

## Copy mode, focus and clipboard

Copy mode explicitly uses vi keys, hybrid line numbers and a subtle cursor-line
highlight. Scrollbars appear while browsing history and hide when idle, overlaying
the content instead of permanently narrowing the pane. Native vi scrolling keeps
the cursor with the text; rectangular selection and Unicode word navigation also
benefit from the newer tmux behavior.

Lowercase `r` refreshes the captured content once. Uppercase `R` toggles automatic
refresh. Automatic refresh starts off, follows output while the cursor is at the
bottom, and pauses during selection. The pane menu can toggle line numbers and
refresh without consuming vi's existing navigation keys. Native tree, client,
buffer and customization pickers expose help with F1 or Ctrl+`h`; Ctrl+`h` retains
cursor-left in vi copy mode.

Hovering over a pane selects it. Selecting a waiting agent acknowledges its prompt
using the existing status behavior; moving the mouse onto one can therefore change
its waiting indicator. Focus events are also forwarded to applications that request
them. Some clients need detaching and reattaching after changing focus reporting;
the tmux sessions and their processes can remain running.

Applications can write the terminal clipboard with OSC 52 and request its current
content through tmux. `get-clipboard request` reads from the most recently used
client rather than returning an unrelated tmux buffer or adding another paste
buffer. This also supports remote applications when the attached terminal permits
clipboard access. Terminal permissions still govern those requests.

## Failures, status and terminal behavior

`remain-on-exit failed-key` keeps failed command output visible until a normal key
is pressed in that pane. Successful exits close normally. Retained failures show
their exit status in the pane row and do not contribute stale waiting/thinking
agent indicators. Agent membership remains available until the retained pane is
closed; respawning and moving panes triggers reconciliation through native events.

The custom orange/blue status palette stays in place. tmux's built-in modes use
terminal ANSI colors, and messages retain an orange fill across the row.
Popups use the terminal's default background to preserve transparency.
New clickable pane ranges and floating title-bar controls work with the existing
two-row status layout.

Ghostty already advertises extended keys, focus, clipboard, progress bars,
synchronized updates and left/right margins. tmux uses the detected capabilities;
Portables does not force unsupported features onto other terminals. OSC 9;4
progress emitted by an application is tracked through `pane_pb_state` and
`pane_pb_progress` and can be forwarded to a supporting terminal. The newer
synchronized-update and redraw fixes benefit applications such as Neovim without
another configuration layer.

## Additional native tools

These additions are available when a workflow needs them; they do not require
another Portables background process.

| Area | Features introduced since 3.6b |
| --- | --- |
| Floating applications | `split-window` can split floating panes; pane swapping works with floats; `new-pane` supports titles, border styles, modal behavior and waiting for exit |
| Native pickers | Fuzzy `switch-mode`; choose commands can hide their containing pane and kill it on exit; floating panes can be sorted by stacking order |
| Customization | Prefix, `C` includes hooks and environment; `e` edits a value; `C` filters changed settings; styles support semantic theme colors, dimming and hyperlinks |
| Inspection | List commands offer sorting; `list-keys`, `show-options` and `show-hooks` support custom formats; `capture-pane -I` includes history timestamps |
| Events | New pane/window/client/group events; OSC 133 command-start, command-finish and shell-prompt events; `set-hook -B` monitors formats; `show-hooks -B` lists monitors; `wait-for -E` waits for events |
| Formats | Option/environment loops, client capability queries, fuzzy matching, time differences, command timing and output-generation variables |
| Animation | `#{A/count:frame,frame,...}` cycles status or border frames; its 100 ms redraw cadence is optional |
| History and prompts | Live copy refresh and scroll-exit controls; `clear-on-attach off` retains earlier terminal scrollback; prompts can avoid freezing panes or appear inside a pane |
| Scripting | Extra `run-shell` arguments, safer command-template quoting, empty-pane flags, new display-panes mode and floating picker hosting |
| Administration | Group-aware session killing, filters for bulk kill commands, user/group server access controls, and individually disabled terminal features |
| Small options | Clock seconds, codepoint-width ranges, additional environment propagation and customizable picker previews |

OSC 133 timing and events depend on the shell/application emitting those sequences.
Agent hooks remain the source of agent lifecycle state; generic shell command
events do not infer whether an agent is waiting for user input.

## Apply and verify

Check the installed version and prerequisites:

```bash
tmux -V
bash ./configure tmux
```

On macOS, upgrade an older Homebrew installation with `brew upgrade tmux`.
On other systems, ensure the selected package source provides stable 3.8 or newer.
An older running server requires a separate migration; upgrading the binary does
not change the version of an existing server. Do not kill active sessions merely
to reload configuration.

After linking this checkout's configuration and helper, use prefix, `r`, or:

```bash
tmux source-file ~/.config/tmux/tmux.conf
tmux show-options -sv get-clipboard
tmux show-options -gv focus-follows-mouse
tmux list-keys -T prefix T
```

Try `T`, select a tiled pane, and move/resize the floating pane. In copy mode, try
`r` and `R`. Test editor copy/paste with disposable text if the terminal permits
clipboard requests. Retained failed panes can also be restarted using the native
pane menu's Respawn action.
