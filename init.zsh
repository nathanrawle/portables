#! /bin/zsh

[[ $1 == "-d" || "$DEBUG" == (1|true|yes|on) ]] \
&& echo "[debug] now entering init.zsh" \
&& DEBUG=1 \
|| DEBUG=

set -e

echo "Setting up and initializing all your shell goodies!"
# Handle $0 according to the standard:
# https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

[[ -n "$DEBUG" ]] && echo "[debug] zero is $0"

: "${HOME:=~}"
MACHINE="${${HOST%%.*}:-${(%):-%m}}"
HERE="${0:P:h}"
PORTS_DIR="$HERE/portables"

# bootstrap a .env file for a new machine, or amend an existing one
ENVFP="$PORTS_DIR/.${MACHINE:l}.env.zsh"
PRTBLS_LN="export PORTABLES=${PORTS_DIR/#$HOME/~}"
MYFUNC_LN="export MYFUNCS=~/.fns"

if [[ -e "$ENVFP" ]]; then
    if ! fgrep -Eq "$PRTBLS_LN" "$ENVFP"; then
      sed -Ei '' '/^(export )?PORTABLES=/d' "$ENVFP"
      print "$PRTBLS_LN" >> "$ENVFP"
    fi

    if ! fgrep -Eq "$MYFUNC_LN" "$ENVFP"; then
      sed -Ei '' '/^(export )?MYFUNCS=/d' "$ENVFP"
      print "$MYFUNC_LN" >> "$ENVFP"
    fi
else;
    print -l "$PRTBLS_LN" "$MYFUNC_LN" > "$ENVFP"
fi

. "$ENVFP"

echo "Setup: Homebrew"
brew --version &> /dev/null \
&& echo "✅ already installed." \
|| ([[ -d /opt/homebrew ]] && path+=/opt/homebrew) \
|| ([[ -f /usr/local/bin/brew ]] && path+=/usr/local/bin) \
|| /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
&& brew update \
&& brew upgrade

echo "Setup: Homebrew autoupdate"
brew tap | grep -q 'domt4/autoupdate' \
|| brew tap 'domt4/autoupdate' \
&& brew autoupdate status 2> /dev/null | grep -q 'and running.' \
|| brew autoupdate start --upgrade --cleanup --immediate --greedy

typeset -aU missing

echo "Setup: Homebrew: uv check"
uv --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='uv'

echo "Setup: Homebrew: pyenv check"
pyenv --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='pyenv'

echo "Setup: Homebrew: zoxide check"
zoxide --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='zoxide'

echo "Setup: Homebrew: starship prompt check"
starship --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='starship'

echo "Setup: Homebrew: NeoVim check"
nvim --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='neovim'

echo "Setup: Homebrew: LuaRocks check"
luarocks --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='luarocks'

echo "Setup: Homebrew: LazyGit check"
lazygit --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='lazygit'

echo "Setup: Homebrew: ripgrep check"
rg --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='ripgrep'

echo "Setup: Homebrew: fd check"
fd --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='fd'

echo "Setup: Homebrew: tree-sitter-cli check"
tree-sitter --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='tree-sitter-cli'

echo "Setup: Homebrew: ImageMagick check"
magick --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='imagemagick'

echo "Setup: Homebrew: ghostscript check"
command gs --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='ghostscript'

echo "Setup: Homebrew: tectonic check"
tectonic --version &> /dev/null \
&& echo "✅ already installed." \
|| missing+='tectonic'

echo "Setup: Homebrew: mermaid-cli check"
mmdc -V &> /dev/null \
&& echo "✅ already installed." \
|| missing+='mermaid-cli'

[[ -n $missing ]] \
&& echo "Setup: Homebrew: installing missing packages" \
&& print -l "${missing[@]}" \
&& brew install $missing \
|| echo "Setup: Homebrew: everything already installed; nothing to do!"

echo "Setup: uv"
uv tool upgrade --all

echo "Setup: uv: ruff"
ruff --version \
&& echo "✅ already installed." \
|| uv tool install ruff

echo "Setup: uv: SQLFluff"
sqlfluff --version \
&& echo "✅ already installed." \
|| uv tool install sqlfluff

echo "Setup: Install/Update Node Version Manager"
NVM_SH_PATH="$HOME/.nvm/nvm.sh"
curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
. "$HOME/.nvm/nvm.sh"
echo "Setup: Node.js"
nvm install --lts

echo "Setup: LazyVim"
if [[ -s ~/.config/nvim/lua/config/lazy.lua ]]; then
  echo "✅ already installed."
else
  NVIM_CONF=".config/nvim"
  [[ -d ~"/$NVIM_CONF.bak" ]] \
  && mv {~,"$(mktemp)"}/"$NVIM_CONF.bak"
  mv -f ~/.config/nvim{/*,.bak}
  rm -rf ~/.config/nvim
  git clone https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
fi

# make sure omz is installed
echo "Setup: Oh My Zsh!"
: ${ZSH:="$HOME/.oh-my-zsh"}
ZSH_CLI="${ZSH}/lib/cli.zsh"

[[ -s "${ZSH_CLI}" ]] \
&& . "${ZSH_CLI}" &> /dev/null \
&& omz version &> /dev/null \
&& echo "✅ already installed." \
|| sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# install plugins and themes
echo "Setup: Oh My Zsh plugins and themes"
: ${ZSH_CUSTOM:="${ZSH}/custom"}

# zsh-syntax-highlighting
echo "Setup: zsh-syntax-highlighting"
P_FPATH="${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
[[ -d "${P_FPATH}" ]] \
&& git -C "${P_FPATH}" pull \
|| git clone --depth=1 https://www.github.com/zsh-users/zsh-syntax-highlighting \
"${P_FPATH}"

# zsh-completions
echo "Setup: zsh-completions"
P_FPATH="${ZSH_CUSTOM}/plugins/zsh-completions"
[[ -d "${P_FPATH}" ]] \
&& git -C "${P_FPATH}" pull \
|| git clone --depth=1 https://www.github.com/zsh-users/zsh-completions \
"${P_FPATH}"

# zsh-autosuggestions
echo "Setup: zsh-autosuggestions"
P_FPATH="${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
[[ -d "${P_FPATH}" ]] \
&& git -C "${P_FPATH}" pull \
|| git clone --depth=1 https://www.github.com/zsh-users/zsh-autosuggestions \
"${P_FPATH}"

# zsh-autocomplete
echo "Setup: zsh-autocomplete"
P_FPATH="${ZSH_CUSTOM}/plugins/zsh-autocomplete"
[[ -d "${P_FPATH}" ]] \
&& git -C "${P_FPATH}" pull \
|| git clone --depth=1 https://www.github.com/marlon-richert/zsh-autocomplete \
"${P_FPATH}"

# powerlevel10k
echo "Setup: powerlevel10k"
P_FPATH="${ZSH_CUSTOM}/themes/powerlevel10k"
[[ -d "${P_FPATH}" ]] \
&& git -C "${P_FPATH}" pull \
|| git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
"${P_FPATH}"

rm "${ZSH_CUSTOM}"/*(.N) &> /dev/null

"${PORTS_DIR}/fns/relink" -q

git config --global --unset-all core.excludesfile
git config --global --add core.excludesfile "$HOME"/.config/git/ignore
git config --global --add core.excludesfile "$PORTS_DIR"/.config/git/ignore

echo 'Setup: Success! Now restart zshell with `exec zsh`…'

return
