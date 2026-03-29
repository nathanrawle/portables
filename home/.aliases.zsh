[[ -s ~/.aliases.sh ]] && . ~/.aliases.sh

alias -g andyes='&& print yes'
alias -g orno='|| print no'
alias -g istrue='andyes orno'

# pipe shortcuts
alias -g H='| head'
alias -g T='| tail'
alias -g F='| tail -F'
alias -g G='| egrep'
alias -g Gi='G -i'
alias -g L='| less'
alias -g M='| more'

if [[ $(uname -s) == 'Darwin' ]]; then
  alias -g C='| clipcopy'
fi

# redirects
alias -g DN='/dev/null'
alias -g 1DN='>/dev/null'
alias -g 2DN='2>/dev/null'
alias -g XDN='&>/dev/null'

# zsh-autocomplete
alias hisb="zstyle -t ':autocomplete:*' default-context '' && zstyle ':autocomplete:*' default-context history-incremental-search-backward || zstyle ':autocomplete:*' default-context ''"

# gcloud config
alias gconf='() {
  if [[ -z $1 ]]; then
    gcloud config list
  else
    case $1 in
      get|set|unset) gcloud config $@ ;;
      *) gcloud config configurations $@ ;;
    esac
  fi
}'

