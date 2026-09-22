#compdef vault
# zsh completion for vault (sops-vault-kit)
# 安装：把本文件放入 fpath（如 ~/.zfunc/_vault），并确保 fpath 含该目录后 compinit
_vault() {
  local -a cmds
  cmds=(
    'ls:列出所有系统（不解密）'
    'peek:不解密列出系统名（无需密钥）'
    'meta:全库 JSON 元数据（免解密，供 UI/AI）'
    'show:显示整条记录（含明文，谨慎）'
    'get:取单个字段值'
    'copy:复制字段到剪贴板（不打印）'
    'search:搜索系统名/入口/用户名/备注'
    'find-secret:反查某密钥片段用在哪些系统'
    'totp:计算当前动态验证码'
    'cat:明文输出到 stdout（不落盘）'
    'view:less 分页明文查看'
    'html:生成浏览器卡片视图（用完 vault clean）'
    'clean:清理明文临时文件'
    'audit:安全审计（白名单/泄漏检查）'
    'shape:stdin 内容体检（形状+指纹，不显示内容）'
    'reencrypt:按当前规则重新加密整库'
    'new:新建条目（自动生成密码）'
    'set:设置字段（值为 - 时走 stdin）'
    'rm:删除条目或字段'
    'edit:用编辑器整库编辑（VS Code）'
    'import:从 CSV 导入（Bitwarden/1Password/Chrome/通用）'
    'md:重建 systems.md 入口表'
    'save:提交改动到 git'
    'log:查看改动历史'
    'remote:绑定备份 git 仓库'
    'push:推送'
    'pull:拉取'
    'export:导出明文 CSV（用完即删）'
    'backup:打包 bundle 备份'
    'restore:从 bundle 恢复（不覆盖）'
    'keycard:生成密钥离线备份卡（打印）'
    'path:打印库与密钥位置'
    'doctor:自检'
    'version:打印版本'
    'help:帮助'
  )
  if (( CURRENT == 2 )); then
    _describe -t commands 'vault command' cmds
  elif (( CURRENT == 3 )); then
    case "${words[2]}" in
      get|copy|cp|show|cat|totp|rm|del)
        local -a entries
        entries=(${(f)"$(vault peek 2>/dev/null)"})
        _describe -t entries 'vault entry' entries ;;
    esac
  fi
}
_vault "$@"
