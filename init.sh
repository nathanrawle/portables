#! /bin/zsh

# Handle $0 according to the standard:
# https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

: ${HOME:=~}
export PORTABLES=${0:P:h}

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

    ln -f {$PORTABLES,$custom}/.zprofile

    if [[ $1 = 'omz' ]]; then
        custom=${ZSH_CUSTOM:=${ZSH:=$HOME/.oh-my-zsh}/custom}

        # environment variables
        ln -f {$PORTABLES/.${HOST/%.*}.,$custom/}env.zsh

        # functions, aliases, and .zshrc snippets that work best outside of actual .zshrc
        for f in $PORTABLES/.{'functions',aliases,p10k.zsh,andfinally.zshrc}(-N);
        do
            ln -f $f $custom/${${f:t}#.}.zsh;
        done

        return
    
    fi

    # environment variables
    ln -f {$PORTABLES/.${HOST/%.*},$custom/}.env.zsh

    # functions, aliases, .zprofile, and .zshrc snippets that work best outside of actual .zshrc
    for f in $PORTABLES/.{'functions',aliases,p10k.zsh,andfinally.zshrc}(-N);
    do
        ln -f $f $custom/${f:t};
    done
}

if [[ $1 = 'omz' ]]; then

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
