# Enable the subsequent settings only in interactive sessions
case $- in
  *i*) ;;
    *) return;;
esac

if [ -z "$HOME" ]; then
  HOME=~
fi

export OSH="$HOME/.oh-my-bash"

OSH_THEME="random"

completions=(
  git
  gh
  npm
  nvm
  pip
  pip3
  ssh
  system
  terraform
  tmux
  uv
)

plugins=(
  brew
  colored-man-pages
  fzf
  gcloud
  git
  goenv
  golang
  npm
  nvm
  starship
  zoxide
)

source "$OSH"/oh-my-bash.sh

