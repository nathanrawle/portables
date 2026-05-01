# utilities: shell
alias cd-='cd -' # for times when `pushdminus` might be unset

if [[ $(uname -s) == 'Darwin' ]]; then
  alias c=clipcopy
  alias v=clippaste
  alias V='clippaste |'
fi

alias g=egrep
alias gi='egrep -i'
alias qg='egrep -q'
alias h=head
alias t=tail
alias l='ls -lAh'
alias f='t -F'
alias follow='f'
alias hist=history
alias rnsort='sort -rn'

alias reshell='exec $0'
alias :q=exit

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
alias glgo='git log --stat --oneline'

# dbt
alias serve-dbtdocs='{ nohup dbt docs serve < /dev/null &> /tmp/dbt-docs-serve-$(date -I) & } && print "docs served in background" || print "something went wrong. Check /tmp/dbt-docs-serve-$(date -I)"'
alias killdocs='pkill -a -f dbt\ docs\ serve'

# gcloud auth
alias gauth='gcloud auth'

alias gal-wfid='gcloud auth login --login-config=$HOME/.config/gcloud/blume_login_config.json'
alias gadl-wfid='gcloud auth application-default login --login-config=$HOME/.config/gcloud/blume_login_config.json'
alias glogin-wfid='gal-wfid && gadl-wfid'

alias gal-gid='gcloud auth login'
alias gadl-gid='gcloud auth application-default login'
alias glogin-gid='gal-gid && gadl-gid'

alias gal='() { if [[ $1 = wf ]]; then gal-wfid; else gal-gid; fi }'
alias gadl='() { if [[ $1 = wf ]]; then gadl-wfid; else gadl-gid; fi }'
alias glogin='() { if [[ $1 = wf ]]; then glogin-wfid; else glogin-gid; fi }'

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
alias twsw='timew summary :ids :week'
alias twslw='timew summary :ids :lastweek'
alias twslm='timew summary :ids :lastmonth'
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
alias tfc='tf console'
alias tfmt='tf fmt'
alias tffmt=tfmt

alias pycal='python -m calendar'

alias nvim-ks='NVIM_APPNAME="nvim-ks" nvim'
alias lzvim='NVIM_APPNAME="nvim-lz" nvim'

alias monty='source ~/monty/.venv/bin/activate'
alias py=' ~/monty/.venv/bin/python'
alias bpy='~/monty/.venv/bin/bpython'
alias ipy='~/monty/.venv/bin/ipython'
