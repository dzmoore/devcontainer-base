#!/usr/bin/env bash
# Ubuntu-style aliases for interactive bash shells.
# Sourced from ~/.bashrc by .devcontainer/post-create.sh.

# Listing (Ubuntu defaults)
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Colorized grep
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias cd..='cd ..'
alias md='mkdir -p'
alias rd='rmdir'

# History, jobs, and shell
alias h='history'
alias j='jobs -l'
alias c='clear'
alias reload='source ~/.bashrc'
alias path='echo -e ${PATH//:/\\n}'

# System info
alias df='df -h'
alias du='du -h'
alias myip='curl -s https://ifconfig.me/ip'

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'

# Kubernetes
alias kctx='kubectx'
alias kns='kubens'

# Containers
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'

# Editors
alias e='nvim'
alias v='nvim'
alias vi='nvim'
alias vim='nvim'
