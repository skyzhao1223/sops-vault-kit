# bash completion for vault (sops-vault-kit)
# 安装：source completions/vault.bash   （或放进 /usr/local/etc/bash_completion.d/）
_vault() {
  local cur cmds
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  cmds="ls list peek show get copy cp search find find-secret totp cat view html clean
        audit reencrypt new add set rm del edit md save commit log remote push pull
        export import backup restore keycard meta shape path doctor help version"
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
  elif [ "$COMP_CWORD" -eq 2 ]; then
    case "${COMP_WORDS[1]}" in
      get|copy|cp|show|cat|totp|rm|del)
        COMPREPLY=( $(compgen -W "$(vault peek 2>/dev/null)" -- "$cur") ) ;;
    esac
  fi
  return 0
}
complete -F _vault vault
