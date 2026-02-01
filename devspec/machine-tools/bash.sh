case "$1" in
    install) echo syspkgmgr:bash ;;
    config)
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
        ;;
esac
