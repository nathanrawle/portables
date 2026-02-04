case "$1" in
    install) (( $(bash -c 'echo ${BASH_VERSINFO[0]}') >= 5 )) || echo syspkgmgr:bash ;;
    config)
        if [ ! -d $HOME/.oh-my-bash ]; then
            bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
        fi
        ;;
esac
