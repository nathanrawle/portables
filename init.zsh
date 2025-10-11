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

echo "Setup: pyenv"
pyenv --version &> /dev/null  \
|| brew install pyenv

echo "Setup: zoxide"
zoxide --version &> /dev/null \
|| brew install zoxide

echo "Setup: starship prompt"
starship --version &> /dev/null \
|| brew install starship

# make sure omz is installed
echo "Setup: Oh My Zsh!"
: ${ZSH:="$HOME/.oh-my-zsh"}

[[ -d "${ZSH}" ]] \
|| sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# install plugins and themes
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

exit
