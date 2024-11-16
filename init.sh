#! /bin/zsh

# Handle $0 according to the standard:
# https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

: ${HOME:=~}
MACHINE=${HOST/%.*}
HERE=${0:P:h}

# bootstrap a .env file for a new machine, or amend an existing one
ENVFP=$HERE/.${MACHINE:l}.env.zsh
PRTBLS_LN="PORTABLES=${HERE/#$HOME/~}"
MYFUNC_LN="MYFUNCS=~/.fns"

if [[ -e $ENVFP ]]; then
    (
        fgrep -E '^PORTABLES=' $ENVFP &> /dev/null \
        || print $PRTBLS_LN >> $ENVFP
    ) && (
        fgrep -E '^MYFUNCS=' $ENVFP &> /dev/null \
        || print $MYFUNC_LN >> $ENVFP
    )
else;
    print -l $PRTBLS_LN $MYFUNC_LN > $ENVFP
fi

. $ENVFP

brew --version &> /dev/null \
|| [ -d /opt/homebrew ] \
|| [ -f /usr/local/bin/brew ] \
|| /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

pyenv --version &> /dev/null  \
|| [ -f /opt/homebrew/bin/pyenv ] \
|| [ -f /usr/local/bin/pyenv ] \
|| brew install pyenv

zoxide --version &> /dev/null \
|| [ -f /opt/homebrew/bin/zoxide ] \
|| [ -f /usr/local/bin/zoxide ] \
|| brew install zoxide

my_cfgs () {

    local custom=$HOME

    # things that always appear in the same place
    ln -f {$PORTABLES,$custom}/.zprofile
    ln -f {$PORTABLES,$custom}/.precompinit.zshrc

    GITCFGDIR=$custom/.config/git
    [[ -d $GITCFGDIR ]] || mkdir -p $GITCFGDIR
    ln -f {$PORTABLES,$custom}/.config/git/ignore
    git config --global core.excludesfile $GITCFGDIR/ignore

    # oh-my-zsh specific config (also the default)
    if [[ $# -eq 0 || $1:l = 'omz' ]]; then
        custom=${ZSH_CUSTOM:=${ZSH:=$HOME/.oh-my-zsh}/custom}

        rm $custom/*(.) &> /dev/null

        # environment variables
        ln -f {$PORTABLES/.$MACHINE.,$custom/00_}env.zsh

        # functions, aliases, and .zshrc snippets that work best outside of actual .zshrc
        for f in $PORTABLES/.{aliases,p10k.zsh}(-N);
        do
            ln -f $f $custom/${${${f:t}#.}%.zsh}.zsh;
        done

        ln -f $PORTABLES/.andfinally.zshrc $custom/zz_andfinally.zsh

        return
    
    fi

    # environment variables
    ln -f {$PORTABLES/.$MACHINE,$custom/}.env.zsh

    # functions, aliases, .zprofile, and .zshrc snippets that work best outside of actual .zshrc
    for f in $PORTABLES/.{aliases,p10k.zsh,andfinally.zshrc}(-N);
    do
        ln -f $f $custom/${f:t};
    done
}

if [[ $# -eq 0 || $1:l = 'omz' ]]; then

    my_cfgs omz

    # make sure it's installed
    omz version &> /dev/null \
    || [ -d ${ZSH:=$HOME/.oh-my-zsh} ] \
    || sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

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
    

    # set up the necessaries
    ln -f {$PORTABLES/omz+,$HOME/}.zshrc
    [ ! -e $HOME/.zshenv ] || mv $HOME/{,.shh}.zshenv

    echo 'Success! Now restart your shell…'

    exit

fi
