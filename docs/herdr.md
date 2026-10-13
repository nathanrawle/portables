# Herdr

The config at `home/.config/herdr/config.toml` adapts the tmux shortcuts in this
repository for Herdr 0.9.3. It keeps Tokyo Night, the top tab bar, pane frames and
gaps, tab naming prompts, and disabled notification delivery.

## Concepts and first use

| tmux concept | Herdr equivalent |
| --- | --- |
| Session used for a project | Workspace |
| Window | Tab |
| Pane | Pane |
| Server and client | Persistent server and attached client |

Herdr also has named sessions, which are separate server namespaces. Usually one
Herdr session with several project workspaces is enough.

From an ordinary terminal, change into a project and run `herdr`. If already
inside a Herdr pane, use the current workspace rather than launching a nested
instance. Run an agent in a pane to have Herdr detect it and show its state.

Click panes and tabs to focus them, drag split borders to resize, and right-click
for menus. Drag-select text to copy it. Prefix+D detaches without stopping pane
processes; run `herdr` from an ordinary terminal to reattach.

## Install and reload

From the intended Portables checkout:

```bash
LINK_CONFLICT_MODE=backup bash ./symlinks .config/herdr
herdr config check
herdr server reload-config
```

The link is `~/.config/herdr/config.toml`. The backup mode preserves an existing
local file under a unique `.bak.*` name. Files are linked individually, leaving
Herdr's local logs and runtime files in place.

Herdr honors `$XDG_CONFIG_HOME/herdr/config.toml`, falling back to
`~/.config/herdr/config.toml`. It also supports `HERDR_CONFIG_PATH` as an explicit
file override. Run `herdr --help` to see the resolved path. Portables' symlink
script mirrors `home/` into `$HOME`; with a custom `XDG_CONFIG_HOME`, link this
config into that directory separately.

Prefix+R reloads config in an attached app, including its client settings and
server config. Startup-only settings need a fresh client; no server stop is
needed for these keybindings.

## Shortcuts

The prefix is **Ctrl+backslash**: press and release it, then press the action key.
Letters below are lowercase unless Shift is specified. Alt is the left Option
key in the repository's macOS Ghostty setup. Prefix+? shows active shortcuts.

| Action | Keys |
| --- | --- |
| Create tab | Prefix+C |
| Previous / next tab | Ctrl+Alt+Left / Right; Prefix+P / N |
| Move tab backward / forward | Ctrl+Shift+Alt+Left / Right |
| Select tab 1–9 | Prefix+1–9 |
| Rename tab | Prefix+comma; Prefix+Shift+T |
| Close tab | Ctrl+Q; Prefix+&; Prefix+Shift+X |
| Previous / next agent | Ctrl+Alt+H / O |
| Select agents 1–4 | Ctrl+Alt+J / K / L / semicolon (colon also selects 4) |
| Create workspace | Ctrl+Alt+N; Prefix+Shift+N |
| Rename workspace | Prefix+$; Prefix+Shift+W |
| Workspace navigation | Ctrl+F; Prefix+W |
| Previous / next workspace | Ctrl+Alt+Up / Down |
| Searchable navigator | Ctrl+Enter |
| Focus pane left / down / up / right | Ctrl+arrows; Prefix+H / J / K / L |
| Swap pane left / down / up / right | Ctrl+Shift+arrows; Prefix+Shift+H / J / K / L |
| Previous / next pane | Ctrl+H / O; Prefix+Shift+Tab / Tab |
| Rename pane | Prefix+Alt+T; Prefix+Shift+P |
| Split right | Prefix+semicolon |
| Split down | Prefix+quote; Prefix+minus |
| Close pane / zoom | Prefix+X / Z |
| Copy mode | Prefix+[ |
| Resize toward an edge | Prefix+Alt+arrows |
| Resize mode | Prefix+Shift+R |
| Reload config | Prefix+R |
| Detach | Prefix+D |
| Lazygit popup | Prefix+G |
| Scratch shell popup | Prefix+T |
| Launch Codex / Claude / Gemini | Prefix+Ctrl+X / C / G |

Other Herdr defaults remain available, including Prefix+S for settings,
Prefix+B to toggle the sidebar, and Prefix+O to open a notification target.
Copy mode already supports Vim movement, `v` to select, and `y` to copy.

## Differences from tmux

- Ctrl+Alt+H/O and J/K/L/semicolon navigate agents rather than tabs. Tab cycling
  stays on Ctrl+Alt+Left/Right.
- Numbered agent jumps select the first four detected agents on the server
  executing the command, in its normal grouped order across workspaces. They use
  Herdr's CLI and the existing `jq`. A missing entry leaves focus unchanged.
  Custom filtered views, priority sorting, and combined remote-machine lists can
  differ from this order; the native previous/next-agent shortcuts follow the UI.
- Ctrl+Shift+arrows swap by direction rather than tmux's previous/next pane order.
- Prefix+minus splits the focused pane downward, rather than making a full-width
  split. New terminals follow the source working directory.
- Agent launch shortcuts create temporary zoomed command panes that close when
  the agent exits. The scratch shell and lazygit are modal popups; exit the
  command to close them. Codex retains the tmux launch's `--no-daemon` flag.
- Floating-pane layouts, width/height presets, indexed pane selection, and
  last-tab/workspace toggles are not recreated in this first config.

Direct shortcuts depend on the outer terminal delivering the chord. If one does
nothing, check the terminal's own bindings and use the retained prefix shortcut
where available.

See the upstream [concepts](https://herdr.dev/docs/concepts/),
[keyboard guide](https://herdr.dev/docs/keyboard/), and
[configuration reference](https://herdr.dev/docs/config-reference/).
