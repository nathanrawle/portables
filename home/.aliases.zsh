[[ -s ~/.aliases.sh ]] && . ~/.aliases.sh

alias -g andyes='&& print yes'
alias -g orno='|| print no'
alias -g istrue='andyes orno'

# pipe shortcuts
alias -g H='| head'
alias -g T='| tail'
alias -g G='| grep'
alias -g Gi='G -i'
alias -g GE='G -E'
alias -g GEi='G -Ei'
alias -g L="| less"
alias -g M="| more"

# zsh-autocomplete
alias hisb="zstyle -t ':autocomplete:*' default-context '' && zstyle ':autocomplete:*' default-context history-incremental-search-backward || zstyle ':autocomplete:*' default-context ''"
