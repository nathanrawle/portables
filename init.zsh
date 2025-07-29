#! /bin/zsh

set +e

# Handle $0 according to the standard:
# https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

: ${HOME:=~}
MACHINE=${${HOST%%.*}:-${(%):-%m}}
HERE=${0:P:h}
PORTS_DIR="$HERE/portables"

# bootstrap a .env file for a new machine, or amend an existing one
ENVFP=$PORTS_DIR/.${MACHINE:l}.env.zsh
PRTBLS_LN="export PORTABLES=${PORTS_DIR/#$HOME/~}"
MYFUNC_LN="export MYFUNCS=~/.fns"

if [[ -e $ENVFP ]]; then
    if ! fgrep -Eq $PRTBLS_LN $ENVFP; then
      sed -Ei '' '/^(export )?PORTABLES=/d' $ENVFP
      print $PRTBLS_LN >> $ENVFP
    fi

    if ! fgrep -Eq $MYFUNC_LN $ENVFP; then
      sed -Ei '' '/^(export )?MYFUNCS=/d' $ENVFP
      print $MYFUNC_LN >> $ENVFP
    fi
else;
    print -l $PRTBLS_LN $MYFUNC_LN > $ENVFP
fi

. $ENVFP

brew --version &> /dev/null \
|| ([ -d /opt/homebrew ] && path+=/opt/homebrew) \
|| ([ -f /usr/local/bin/brew ] && path+=/usr/local/bin) \
&& brew update \
&& brew upgrade \
|| /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew tap | grep -q 'domt4/autoupdate' \
|| brew tap 'domt4/autoupdate' \
&& brew autoupdate status 2> /dev/null | grep -q 'and running.' \
|| brew autoupdate start --upgrade --cleanup --immediate --greedy

pyenv --version &> /dev/null  \
|| [ -f /opt/homebrew/bin/pyenv ] \
|| [ -f /usr/local/bin/pyenv ] \
|| brew install pyenv

zoxide --version &> /dev/null \
|| [ -f /opt/homebrew/bin/zoxide ] \
|| [ -f /usr/local/bin/zoxide ] \
|| brew install zoxide

# make sure omz is installed
omz version &> /dev/null \
|| [ -d ${ZSH:=$HOME/.oh-my-zsh} ] \
|| sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \

# zsh-syntax-highlighting zsh-completions zsh-autosuggestions zsh-autocomplete powerlevel10k
[ -d ${ZSH_CUSTOM:=$ZSH/custom}/plugins/zsh-syntax-highlighting ] \
|| git clone https://www.github.com/zsh-users/zsh-syntax-highlighting \
$ZSH_CUSTOM/plugins/zsh-syntax-highlighting

[ -d $ZSH_CUSTOM/plugins/zsh-completions ] \
|| git clone https://www.github.com/zsh-users/zsh-completions \
$ZSH_CUSTOM/plugins/zsh-completions

[ -d $ZSH_CUSTOM/plugins/zsh-autosuggestions ] \
|| git clone https://www.github.com/zsh-users/zsh-autosuggestions \
$ZSH_CUSTOM/plugins/zsh-autosuggestions

[ -d $ZSH_CUSTOM/plugins/zsh-autocomplete ] \
|| git clone https://www.github.com/marlon-richert/zsh-autocomplete \
$ZSH_CUSTOM/plugins/zsh-autocomplete

[ -d $ZSH_CUSTOM/themes/powerlevel10k ] \
|| git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
$ZSH_CUSTOM/themes/powerlevel10k

rm ${ZSH_CUSTOM}/*(.N) &> /dev/null

"$PORTS_DIR"/fns/relink -q

git config --global --unset-all core.excludesfile
git config --global --add core.excludesfile "$HOME"/.config/git/ignore
git config --global --add core.excludesfile "$PORTS_DIR"/.config/git/ignore

echo 'Success! Now restart your shell…'

exit
