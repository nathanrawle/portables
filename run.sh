#!/bin/sh

set -e
echo "Starting setup..."

# --- OS and Package Manager Detection ---
OS="$(uname -s)"
PKG_MANAGER_INSTALL=""
PKG_MANAGER_UPDATE=""

case "$OS" in
    Darwin)
        echo "Detected macOS."
        PKG_MANAGER_INSTALL="brew install"
        PKG_MANAGER_UPDATE="brew update"

        # On macOS, we rely on Homebrew. Ensure it's installed.
        if ! command -v brew >/dev/null 2>&1; then
            echo "Homebrew not found. Installing..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        ;;
    Linux)
        echo "Detected Linux."
        # Use /etc/os-release to find the distribution
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian|pop)
                    echo "Detected Debian-based distribution ($PRETTY_NAME)."
                    PKG_MANAGER_INSTALL="sudo apt-get install -y"
                    PKG_MANAGER_UPDATE="sudo apt-get update"
                    ;;
                arch)
                    echo "Detected Arch Linux."
                    PKG_MANAGER_INSTALL="sudo pacman -S --noconfirm"
                    PKG_MANAGER_UPDATE="sudo pacman -Syu"
                    ;;
                fedora)
                    echo "Detected Fedora."
                    PKG_MANAGER_INSTALL="sudo dnf install -y"
                    PKG_MANAGER_UPDATE="sudo dnf check-update"
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
MACHINE_TOOLS_DIR="$HERE/devspec/machine-tools"

# Hardcoded order of execution for machine-tools scripts
MACHINE_TOOLS_ORDER="zsh nvm node zoxide starship neovim luarocks lazygit ripgrep fd tree-sitter imagemagick ghostscript tectonic mermaid uv ruff sqlfluff symlink"

# Prime the sudo timestamp
if [ -n "$PKG_MANAGER_INSTALL" ] && echo "$PKG_MANAGER_INSTALL" | grep -q "sudo"; then
    echo "Requesting sudo access upfront..."
    sudo -v
fi

# --- PASS 1: Collect Dependencies ---
echo
echo "Collecting package dependencies from machine-tools..."
all_deps=""

for tool in $MACHINE_TOOLS_ORDER; do
    tool_script="$MACHINE_TOOLS_DIR/$tool.sh"
    if [ -f "$tool_script" ]; then
        if deps_output=$(sh "$tool_script" deps 2>/dev/null); then
            if [ -n "$deps_output" ]; then
                all_deps="$all_deps $deps_output"
            fi
        fi
    else
        echo "Warning: machine-tool script '$tool_script' not found. Skipping." >&2
    fi
done

# --- Install All Dependencies at Once ---
if [ -n "$all_deps" ]; then
    unique_deps=$(printf "%s
" $all_deps | sort -u | xargs)

    echo
    echo "Updating package manager and installing packages: $unique_deps"
    eval "$PKG_MANAGER_UPDATE"
    eval "$PKG_MANAGER_INSTALL $unique_deps"
else
    echo "No package dependencies declared by machine-tools."
fi

# --- PASS 2: Run Configuration Steps ---
echo
echo "Running configuration steps from machine-tools..."
for tool in $MACHINE_TOOLS_ORDER; do
    tool_script="$MACHINE_TOOLS_DIR/$tool.sh"
    if [ -f "$tool_script" ]; then
        echo "--- Configuring $tool ---"
        sh "$tool_script" config
    fi
done

echo
echo 'Setup: Success! Now restart zshell with `exec zsh`…'