#!/usr/bin/env bash

set -euo pipefail
echo "Starting setup..."

# --- OS and Package Manager Detection ---
export OS="$(uname -s)"
PKG_MANAGER_UPDATE=""
PKG_MANAGER_INSTALL=""
PKG_MANAGER_EXT_INSTALL=""

if [[ -z "$HOME" ]]; then
  HOME="$(realpath ~)"
fi

if [[ -z "${HOST-}" ]]; then
  HOST="$(hostname 2>/dev/null)" || HOST=mystery-host
fi

if [[ $HOST = "mystery-host" ]]; then
  MACHINE=scoobs-van
else
  MACHINE=${HOST%%.*}
fi

export HOME HOST MACHINE

THIS="$(realpath "$0" 2>/dev/null || command -v "$0")"
HERE="$(dirname "$THIS")"
MACHINE_TOOLS="$HERE/machine-tools"
PORTABLE_HOME="$HERE/home"

# bootstrap a .env file for a new machine, or amend an existing one
machine=$(printf '%s' "$MACHINE" | tr '[:upper:]' '[:lower:]')
MACHENV="$PORTABLE_HOME/.$machine.env"
PRTBLS_LN="export PORTABLES=${HERE/#$HOME/"~"}"

if [[ -e "$MACHENV" ]]; then
  if ! fgrep -Eq "$PRTBLS_LN" "$MACHENV"; then
    sed -Ei '' '/^(export )?PORTABLES=/d' "$MACHENV"
    echo "$PRTBLS_LN" >>"$MACHENV"
  fi
else
  echo "$PRTBLS_LN" >"$MACHENV"
fi

. "$MACHENV"

case "$OS" in
Darwin)
  echo "Detected macOS."
  xcode-select -p >/dev/null 2>&1 || xcode-select --install
  SYS_PKG_MANAGER="homebrew"
  PKG_MANAGER_UPDATE="brew update"
  PKG_MANAGER_INSTALL="brew install"
  PKG_MANAGER_EXT_INSTALL="brew tap"
  export HOMEBREW_NO_ENV_HINTS=1
  ;;
Linux)
  echo "Detected Linux."
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "$ID" in
    ubuntu | debian | pop)
      echo "Detected Debian-based distribution ($PRETTY_NAME)."
      SYS_PKG_MANAGER="apt"
      PKG_MANAGER_UPDATE="sudo apt-get update"
      PKG_MANAGER_INSTALL="sudo apt-get install -y"
      ;;
    arch)
      echo "Detected Arch Linux."
      SYS_PKG_MANAGER="pacman"
      PKG_MANAGER_UPDATE="sudo pacman -Syu"
      PKG_MANAGER_INSTALL="sudo pacman -S --noconfirm"
      ;;
    fedora)
      echo "Detected Fedora."
      SYS_PKG_MANAGER="dnf"
      PKG_MANAGER_UPDATE="sudo dnf check-update"
      PKG_MANAGER_INSTALL="sudo dnf install -y"
      ;;
    *)
      echo "Unsupported Linux distribution: $ID" >&2
      exit 1
      ;;
    esac
  else
    echo "Cannot determine Linux distribution. /etc/os-release not found." >&2
    exit 1
  fi
  ;;
*)
  echo "Unsupported operating system: $OS" >&2
  exit 1
  ;;
esac

# Prime the sudo timestamp
if echo "$PKG_MANAGER_INSTALL" | grep -q "sudo"; then
  echo "Requesting sudo access upfront..."
  sudo -v
fi

# --- 1. Collection Phase ---
echo "Collecting package dependencies from machine-tools..."

self_install_scripts=""
syspkgmgr_install_cmds=""
uv_install_cmds=""
pip_install_cmds=""
pipx_install_cmds=""
nvm_install_cmds=""
npm_install_cmds=""

syspkgmgr_tool_scripts=""
uv_tool_scripts=""
pip_tool_scripts=""
pipx_tool_scripts=""
nvm_tool_scripts=""
npm_tool_scripts=""

for tool_script in "$MACHINE_TOOLS"/*.sh; do
  install_cmds="$(sh "$tool_script" install)"
  for install_cmd in $install_cmds; do
    case "$install_cmd" in
    "") continue ;;
    self-install)
      self_install_scripts="${self_install_scripts:+$self_install_scripts$'\n'}$tool_script"
      ;;
    syspkgmgr:*)
      syspkgmgr_install_cmds="${syspkgmgr_install_cmds:+$syspkgmgr_install_cmds }${install_cmd#syspkgmgr:}"
      syspkgmgr_tool_scripts="${syspkgmgr_tool_scripts:+$syspkgmgr_tool_scripts$'\n'}$tool_script"
      ;;
    uv:*)
      uv_install_cmds="${uv_install_cmds:+$uv_install_cmds }${install_cmd#uv:}"
      uv_tool_scripts="${uv_tool_scripts:+$uv_tool_scripts$'\n'}$tool_script"
      ;;
    pip:*)
      pip_install_cmds="${pip_install_cmds:+$pip_install_cmds }${install_cmd#pip:}"
      pip_tool_scripts="${pip_tool_scripts:+$pip_tool_scripts$'\n'}$tool_script"
      ;;
    pipx:*)
      pipx_install_cmds="${pipx_install_cmds:+$pipx_install_cmds }${install_cmd#pipx:}"
      pipx_tool_scripts="${pipx_tool_scripts:+$pipx_tool_scripts$'\n'}$tool_script"
      ;;
    nvm:*)
      nvm_install_cmds="${nvm_install_cmds:+$nvm_install_cmds }${install_cmd#nvm:}"
      nvm_tool_scripts="${nvm_tool_scripts:+$nvm_tool_scripts$'\n'}$tool_script"
      ;;
    npm:*)
      npm_install_cmds="${npm_install_cmds:+$npm_install_cmds }${install_cmd#npm:}"
      npm_tool_scripts="${npm_tool_scripts:+$npm_tool_scripts$'\n'}$tool_script"
      ;;
    *) echo "Install command not recognised: $install_cmd" ;;
    esac
  done
done

# --- 2. Execution Phase ---

if [[ -n "$self_install_scripts" ]]; then
  echo "Running self-installers..."
  while IFS= read -r tool_script; do
    sh "$tool_script" self-install
    sh "$tool_script" config
  done <<<"$self_install_scripts"
fi

if [[ -n "$uv_install_cmds" ]] &&
  ! command -v uv >/dev/null 2>&1 &&
  [[ ! " $syspkgmgr_install_cmds " = *" uv "* ]]; then
  if [[ "$OS" = Darwin ]]; then
    syspkgmgr_install_cmds="${syspkgmgr_install_cmds:+$syspkgmgr_install_cmds }uv"
  else
    ensure_uv_installed=1
  fi
fi

if [[ -n "$pipx_install_cmds" ]] && [[ ! " $syspkgmgr_install_cmds " = *" pipx "* ]]; then
  syspkgmgr_install_cmds="${syspkgmgr_install_cmds:+$syspkgmgr_install_cmds }pipx"
fi

if [[ -n "$syspkgmgr_install_cmds" ]]; then
  core_tools=""
  ext_tools=""
  for item in $syspkgmgr_install_cmds; do
    case $item in
    *:*) ext_tools="${ext_tools:+$ext_tools }${item#*:}" ;;
    *) core_tools="${core_tools:+$core_tools }$item" ;;
    esac
  done

  echo "Updating $SYS_PKG_MANAGER..."
  sh -c "$PKG_MANAGER_UPDATE"

  if [[ -n "$core_tools" ]]; then
    echo "Installing system packages: $core_tools"
    sh -c "$PKG_MANAGER_INSTALL $core_tools"
  fi

  if [[ -n "$ext_tools" ]]; then
    echo "Tapping external repositories: $ext_tools"
    for ext_tool in $ext_tools; do
      sh -c "$PKG_MANAGER_EXT_INSTALL $ext_tool"
    done
  fi

  echo "Running system package configurations..."
  while IFS= read -r tool_script; do
    [[ -n "$tool_script" ]] && sh "$tool_script" config
  done <<<"$syspkgmgr_tool_scripts"
fi

if [[ "${ensure_uv_installed:-0}" -gt 0 ]] && ! command -v uv >/dev/null 2>&1; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

if [[ -n "$uv_install_cmds" ]]; then
  [[ "$(command -v uv 2>/dev/null)" = *homebrew* ]] || uv self update

  tools=""
  pythons=""
  for item in $uv_install_cmds; do
    case $item in
    python:*) pythons="${pythons:+$pythons }${item#*:}" ;;
    *) tools="${tools:+$tools }${item#*:}" ;;
    esac
  done

  if [[ -n "$tools" ]]; then
    tools=$(printf "%s\n" $tools | sort -u | xargs)
    echo "Installing uv tools: $tools"
    for tool in $tools; do
      tool=$(echo $tool | tr ':' ' ')
      uv tool install $tool
    done
  fi

  if [[ -n "$pythons" ]]; then
    pythons=$(printf "%s\n" $pythons | sort -u | xargs)
    echo "Installing uv pythons: $pythons"
    for python in $pythons; do
      python=$(echo $python | tr ':' ' ')
      uv python install $python
    done
  fi

  echo "Running uv package configurations..."
  while IFS= read -r tool_script; do
    [[ -n "$tool_script" ]] && sh "$tool_script" config
  done <<<"$uv_tool_scripts"
fi

if [[ -n "$pip_install_cmds" ]]; then
  install_list=$(printf "%s\n" $pip_install_cmds | sort -u | xargs)
  echo "Installing user-local pip packages: $install_list"
  python3 -m pip install -U pip
  python3 -m pip install --user $install_list
  echo "Running pip package configurations..."
  while IFS= read -r tool_script; do
    [[ -n "$tool_script" ]] && sh "$tool_script" config
  done <<<"$pip_tool_scripts"
fi

if [[ -n "$pipx_install_cmds" ]]; then
  install_list=$(printf "%s\n" $pipx_install_cmds | sort -u | xargs)
  echo "Installing user-local pipx packages: $install_list"
  pipx install $install_list
  echo "Running pipx package configurations..."
  while IFS= read -r tool_script; do
    [[ -n "$tool_script" ]] && sh "$tool_script" config
  done <<<"$pipx_tool_scripts"
fi

if [[ -n "$nvm_install_cmds" ]]; then
  install_list=$(printf "%s\n" $nvm_install_cmds | sort -u | xargs)
  echo "Installing node versions with nvm: $install_list"
  export NVM_DIR="$HOME/.nvm"
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  nvm install "$install_list"
  echo "Running nvm package configurations..."
  while IFS= read -r tool_script; do
    [[ -n "$tool_script" ]] && sh "$tool_script" config
  done <<<"$nvm_tool_scripts"
fi

if [[ -n "$npm_install_cmds" ]]; then
  install_list=$(printf "%s\n" $npm_install_cmds | sort -u | xargs)
  echo "Installing global npm packages: $install_list"
  export NVM_DIR="$HOME/.nvm"
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  npm install -g $install_list
  echo "Running npm package configurations..."
  while IFS= read -r tool_script; do
    [[ -n "$tool_script" ]] && sh "$tool_script" config
  done <<<"$npm_tool_scripts"
fi

echo "Devspec run complete."
