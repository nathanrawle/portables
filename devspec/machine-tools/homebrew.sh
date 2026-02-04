case "$1" in
  install) echo self-install ;;
  self-install)
    if ! command -v brew >/dev/null 2>&1; then
      echo "Homebrew not found. Installing..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    ;;
esac
