# utilities: shell
alias cd-='cd -' # for times when `pushdminus` might be unset
alias g='grep'
alias gi='grep -i'
alias ge='grep -E'
alias gei='grep -Ei'
alias qg='grep -q'
alias h='head'
alias t='tail'
alias l='ls -lAh'
alias ft='t -F'
alias follow='ft'
alias hist='history'
alias rnsort='sort -rn'

alias reshell='exec $SHELL'

alias -g andyes='&& print yes'
alias -g orno='|| print no'
alias -g istrue='andyes orno'

# utilities: python
alias wp='which python'
alias pw='pyenv which'
alias pwp='pw python'
alias pylatest='pyenv install --list | grep -E "^\s*\d\.\d{1,2}\.\d+$" | sort -t "." -k 1bn -k 2n -k 3n | tail -1'
alias pil='pyenv install $(pylatest)'

# git overrides
alias gP='git push'
alias gp='git pull'
alias gs='git switch'
alias gsc='git switch -c'
alias gs-='git switch -'
alias gsm='git switch main'

# pipe shortcuts
alias -g H='| head'
alias -g T='| tail'
alias -g G='| grep'
alias -g Gi='G -i'
alias -g GE='G -E'
alias -g GEi='G -Ei'
alias -g L="| less"
alias -g M="| more"

# dbt
alias serve-dbtdocs='{ nohup dbt docs serve < /dev/null &> /tmp/dbt-docs-serve-$(date -I) & } && print "docs served in background" || print "something went wrong. Check /tmp/dbt-docs-serve-$(date -I)"'
alias killdocs='pkill -a -f dbt\ docs\ serve'

# gcloud auth
alias gauth='gcloud auth'
alias gal='gcloud auth login --login-config=$HOME/.config/gcloud/blume_login_config.json'
alias gadl='gcloud auth application-default login --login-config=$HOME/.config/gcloud/blume_login_config.json'
alias glogin='gal && gadl'

# gcloud config
alias gconf='gcloud config'
alias gcfg='gcloud config list'
alias gconfs='gcloud config configurations'
alias gcfgs='gcloud config configurations list'

# gcloud compute engine
alias gce='gcloud compute'
alias gcia='gcloud compute instances start'
alias gcio='gcloud compute instances stop'
alias gssh='gcloud beta compute ssh'

# task/time warrior
alias todo='task add'
alias tasks='task list'

alias tw=timew
alias twd='timew day'
alias twyd='timew day :yesterday'
alias tww='timew week'
alias twlw='timew week :lastweek'
alias twm='timew month'
alias twlm='timew month :lastmonth'
alias tws='timew summary :ids'
alias twa='timew start'
alias twx='timew cancel'
alias two='timew stop'
alias twc='timew continue'
alias twt='timew track'
alias twmv='timew move'

# terraform
alias tf='terraform'
alias tfi='tf init'
alias tfo='tf output'
alias tfp='tf plan'
alias tfa='tf apply'
alias tfv='tf validate'
alias tfmt='tf fmt'
alias tffmt=tfmt

# zsh-autocomplete
alias hisb="zstyle -t ':autocomplete:*' default-context '' && zstyle ':autocomplete:*' default-context history-incremental-search-backward || zstyle ':autocomplete:*' default-context ''"
alias pycal='python -m calendar'

alias nvim-ks='NVIM_APPNAME="nvim-ks" nvim'
alias lzvim='NVIM_APPNAME="nvim-lz" nvim'

alias monty='source ~/monty/.venv/bin/activate'
alias py=' ~/monty/.venv/bin/python'
alias bpy='~/monty/.venv/bin/bpython'
alias ipy='~/monty/.venv/bin/ipython'
