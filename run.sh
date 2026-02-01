#!/bin/sh

set -e
echo "Starting setup..."

# --- OS and Package Manager Detection ---
export OS="$(uname -s)"
PKG_MANAGER_UPDATE=""
PKG_MANAGER_INSTALL=""
PKG_MANAGER_EXT_INSTALL=""

case "$OS" in
    Darwin)
        echo "Detected macOS."
        SYS_PKG_MANAGER="homebrew"
        PKG_MANAGER_UPDATE="brew update"
        PKG_MANAGER_INSTALL="brew install"
        PKG_MANAGER_EXT_INSTALL="brew tap"
        ;;
    Linux)
        echo "Detected Linux."
        # Use /etc/os-release to find the distribution
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian|pop)
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

HERE="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
MACHINE_TOOLS="$HERE/devspec/machine-tools"

# Prime the sudo timestamp
if [ -n "$PKG_MANAGER_INSTALL" ] && echo "$PKG_MANAGER_INSTALL" | grep -q "sudo"; then
    echo "Requesting sudo access upfront..."
    sudo -v
fi

echo "Collecting package dependencies from machine-tools..."

for tool_script in $MACHINE_TOOLS/*; do
    tool=$(basename -s .sh $tool_script)
    install_cmd="$(sh "$tool_script" install)"

    case "$install_cmd" in
      "") continue ;;
      self-install)
        self_installs="${self_installs:+$self_installs }$tool_script"
        ;;
      syspkgmgr*)
        syspkgmgr_install_cmds="${syspkgmgr_install_cmds:+$syspkgmgr_install_cmds }${install_cmd#syspkgmgr:}"
        syspkgmgr_tool_scripts="${syspkgmgr_tool_scripts:+$syspkgmgr_tool_scripts }$tool_script"
        ;;
      uv*)
        uv_install_cmds="${uv_install_cmds:+$uv_install_cmds }${install_cmd#uv:}"
        uv_tool_scripts="${uv_tool_scripts:+$uv_tool_scripts }$tool_script"
        ;;
      pip*)
        pip_install_cmds="${pip_install_cmds:+$pip_install_cmds }${install_cmd#pip:}"
        pip_tool_scripts="${pip_tool_scripts:+$pip_tool_scripts }$tool_script"
        ;;
      pipx*)
        pipx_install_cmds="${pipx_install_cmds:+$pipx_install_cmds }${install_cmd#pipx:}"
        pipx_tool_scripts="${pipx_tool_scripts:+$pipx_tool_scripts }$tool_script"
        ;;
      nvm*)
        nvm_install_cmds="${nvm_install_cmds:+$nvm_install_cmds }${install_cmd#nvm:}"
        nvm_tool_scripts="${nvm_tool_scripts:+$nvm_tool_scripts }$tool_script"
        ;;
      npm*)
        npm_install_cmds="${npm_install_cmds:+$npm_install_cmds }${install_cmd#npm:}"
        npm_tool_scripts="${npm_tool_scripts:+$npm_tool_scripts }$tool_script"
        ;;
      *) echo "install command not recognised: $install_cmd" ;;
    esac
done

# self-install things that have their own installers
if [ -n "$self_list" ]; then
    install_list=$(printf "%s\n" $self_list | sort -u | xargs)
    echo "Installing self-installers: $install_list"
    for tool_script in $self_list; do
      eval $tool_script self-install
      eval $tool_script config
    done
    unset install_list
fi

# make sure uv is installed if it has any dependents
ensure_uv_installed=0
if [ -n "$uv_list" ] && [ ! "$syspkgmgr_list" = *" uv "* ]; then
  if [ "$OS" = Darwin ]; then
    syspkgmgr_list="${syspkgmgr_list:+$syspkgmgr_list }uv"
  else
    ensure_uv_installed=1
  fi
fi

# make sure pipx is installed if it has any dependents
if [ -n "$pipx_list" ] && [ ! "$syspkgmgr_list" = *" pipx "* ]; then
  syspkgmgr_list="${syspkgmgr_list:+$syspkgmgr_list }pipx"
fi

# System Package Manager
if [ -n "$syspkgmgr_list" ]; then
    install_list=$(printf "%s\n" $syspkgmgr_list | sort -u | xargs)
    for install_cmd in $install_list; do
      case $install_cmd in
        *":"*) ext_tools="${ext_tools:+$ext_tools }$tool" ;;
        *) core_tools="${core_tools:+$core_tools }$tool" ;;
      esac
    done

    echo "Updating $SYS_PKG_MANAGER and installing packages: $unique_deps"
    eval "$PKG_MANAGER_UPDATE"
    eval "$PKG_MANAGER_INSTALL $core_tools"

    if [ -n "$ext_tools" ]; then
      for ext_tool in $ext_tools; do
        ext_tool=${ext_tool#*:}
        eval "$PKG_MANAGER_EXT_INSTALL $ext_tool"
      done
    fi

    for tool_script in $syspkgmgr_tool_scripts; do
      eval $tool_script config
    done
    unset install_list
fi

if [ $ensure_uv_installed -gt 0 ] && ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

if [ -n "$uv_list" ]; then
    install_list=$(printf "%s\n" $uv_list | sort -u | xargs)
    echo "Updating uv and installing packages: $install_list"
    uv self update
    uv tool install $install_list

    for tool_script in $uv_tool_scripts; do
      eval $tool_script config
    done
    unset install_list
fi

if [ -n "$pip_list" ]; then
    install_list=$(printf "%s\n" $pip_list | sort -u | xargs)
    echo "Updating user local pip and installing packages: $install_list"
    . $HOME/.python/bin/activate
    pip install -U pip
    pip install --user $install_list

    for tool_script in $pip_tool_scripts; do
      eval $tool_script config
    done
    unset install_list
fi

if [ -n "$pipx_list" ]; then
    install_list=$(printf "%s\n" $pipx_list | sort -u | xargs)
    echo "Updating user local pipx and installing packages: $install_list"
    pipx install --user $install_list

    for tool_script in $pipx_tool_scripts; do
      eval $tool_script config
    done
    unset install_list
fi

if [ -n "$nvm_list" ]; then
    install_list=$(printf "%s\n" $nvm_list | sort -u | xargs | tr ':' ' ')
    nvm install $install_list

    for tool_script in $nvm_tool_scripts; do
      eval $tool_script config
    done
    unset install_list
fi

if [ -n "$npm_list" ]; then
    install_list=$(printf "%s\n" $npm_list | sort -u | xargs)
    npm install -g $install_list

    for tool_script in $npm_tool_scripts; do
      eval $tool_script config
    done
    unset install_list
fi

echo "Devspec run complete"

# exec $SHELL
