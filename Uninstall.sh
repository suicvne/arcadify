#!/usr/bin/env bash
set -Eeuo pipefail

ArcadeUser="arcade"
RemoveArcadeUser="false"
ArcadeUserWasProvided="false"
UserExistedBeforeInstall="unknown"
StateDirectory="/var/lib/Arcadify"
ManifestFile="${StateDirectory}/InstallManifest.tsv"
BackupDirectory="${StateDirectory}/Backups"

PrintUsage() {
  cat <<'USAGE'
Arcadify uninstaller.

Usage:
  sudo ./Uninstall.sh [options]

Options:
  --arcade-user USER     Arcade account used during install. Default: arcade
  --remove-user          Also remove the arcade user and home directory if Arcadify created it.
  --help                 Show this help.
USAGE
}

Fail() {
  printf 'Arcadify: %s\n' "$*" >&2
  exit 1
}

RequireRoot() {
  if [[ "${EUID}" -ne 0 ]]; then
    Fail "please run this uninstaller with sudo or as root."
  fi
}

ParseArguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arcade-user)
        [[ $# -ge 2 ]] || Fail "--arcade-user requires a value."
        ArcadeUser="$2"
        ArcadeUserWasProvided="true"
        shift 2
        ;;
      --remove-user)
        RemoveArcadeUser="true"
        shift
        ;;
      --help|-h)
        PrintUsage
        exit 0
        ;;
      *)
        Fail "unknown option: $1"
        ;;
    esac
  done
}

RemoveFileIfPresent() {
  local Path="$1"
  if [[ -e "${Path}" || -L "${Path}" ]]; then
    rm -f "${Path}"
    printf 'Removed %s\n' "${Path}"
  fi
}

RemoveDirectoryIfEmpty() {
  local Path="$1"
  if [[ -d "${Path}" ]]; then
    rmdir "${Path}" >/dev/null 2>&1 || true
  fi
}

ReadManifestValue() {
  local RecordName="$1"

  [[ -f "${ManifestFile}" ]] || return 1
  awk -F '\t' -v RecordName="${RecordName}" \
    '$1 == "Value" && $2 == RecordName { print $3; Found = 1; exit } END { exit Found ? 0 : 1 }' \
    "${ManifestFile}"
}

LoadManifestArcadeUser() {
  local StoredArcadeUser

  [[ -f "${ManifestFile}" ]] || return
  StoredArcadeUser="$(ReadManifestValue "ArcadeUser" || true)"
  [[ -n "${StoredArcadeUser}" ]] || return

  if [[ "${ArcadeUserWasProvided}" == "true" && "${ArcadeUser}" != "${StoredArcadeUser}" ]]; then
    Fail "install manifest belongs to user ${StoredArcadeUser}, not ${ArcadeUser}."
  fi

  ArcadeUser="${StoredArcadeUser}"
  UserExistedBeforeInstall="$(ReadManifestValue "UserExistedBeforeInstall" || printf 'unknown')"
}

RestoreFilesFromManifest() {
  local RecordType
  local Path
  local Status
  local BackupName

  while IFS=$'\t' read -r RecordType Path Status BackupName; do
    [[ "${RecordType}" == "File" ]] || continue

    case "${Status}" in
      present)
        [[ -n "${BackupName}" ]] || Fail "manifest backup name is missing for ${Path}."
        [[ -e "${BackupDirectory}/${BackupName}" || -L "${BackupDirectory}/${BackupName}" ]] || Fail "backup is missing for ${Path}."
        mkdir -p "$(dirname "${Path}")"
        rm -rf "${Path}"
        cp -a "${BackupDirectory}/${BackupName}" "${Path}"
        printf 'Restored %s\n' "${Path}"
        ;;
      missing)
        rm -rf "${Path}"
        printf 'Removed %s\n' "${Path}"
        ;;
      *)
        Fail "unknown file restore status for ${Path}: ${Status}"
        ;;
    esac
  done <"${ManifestFile}"
}

RestoreDirectoriesFromManifest() {
  local DirectoryRecords=()
  local Index
  local Record
  local Path
  local Status

  while IFS= read -r Record; do
    DirectoryRecords+=("${Record}")
  done < <(awk -F '\t' '$1 == "Directory" { print $2 "\t" $3 }' "${ManifestFile}")

  for ((Index = ${#DirectoryRecords[@]} - 1; Index >= 0; Index--)); do
    IFS=$'\t' read -r Path Status <<<"${DirectoryRecords[Index]}"
    if [[ "${Status}" == "missing" ]]; then
      RemoveDirectoryIfEmpty "${Path}"
    fi
  done
}

RestorePreviousDefaultTarget() {
  local PreviousDefaultTarget

  PreviousDefaultTarget="$(ReadManifestValue "PreviousDefaultTarget" || true)"
  if [[ -n "${PreviousDefaultTarget}" ]]; then
    systemctl set-default "${PreviousDefaultTarget}" >/dev/null 2>&1 || true
    printf 'Restored systemd default target to %s\n' "${PreviousDefaultTarget}"
  fi
}

CleanupInstallState() {
  rm -rf "${BackupDirectory}"
  RemoveFileIfPresent "${ManifestFile}"
  RemoveDirectoryIfEmpty "${StateDirectory}"
}

RestoreFromManifest() {
  printf 'Arcadify: restoring from install manifest at %s...\n' "${ManifestFile}"
  RestoreFilesFromManifest
  RestorePreviousDefaultTarget
  RestoreDirectoriesFromManifest
  CleanupInstallState
}

RemoveArcadifyFiles() {
  RemoveFileIfPresent /usr/local/bin/ArcadifySession
  RemoveFileIfPresent /usr/local/bin/ArcadifyLaunchGame
  RemoveFileIfPresent /usr/local/bin/ArcadifyShell
  RemoveFileIfPresent /usr/local/bin/ArcadifyRequestLaunch
  RemoveFileIfPresent /usr/local/bin/ArcadifyMaintenance
  RemoveFileIfPresent /usr/local/bin/ArcadifyBrowser
  RemoveFileIfPresent /usr/share/xsessions/Arcadify.desktop
  RemoveFileIfPresent /opt/Arcadify/shell/arcadify_shell/__init__.py
  RemoveFileIfPresent /opt/Arcadify/shell/arcadify_shell/__main__.py
  RemoveFileIfPresent /opt/Arcadify/shell/arcadify_shell/app.py
  RemoveFileIfPresent /opt/Arcadify/shell/arcadify_shell/config.py
  RemoveFileIfPresent /opt/Arcadify/shell/pyproject.toml
  RemoveFileIfPresent /opt/Arcadify/shell/README.md
  RemoveFileIfPresent /etc/Arcadify/blank-cursor.xbm
  RemoveFileIfPresent /etc/Arcadify/blank-cursor-mask.xbm
  RemoveFileIfPresent /etc/lightdm/lightdm.conf.d/99-Arcadify.conf
  RemoveFileIfPresent /etc/lightdm/lightdm.conf.d/50-Arcadify.conf
  RemoveFileIfPresent /etc/Arcadify/Shell.ini
  RemoveFileIfPresent /etc/Arcadify/Arcadify.conf
  RemoveDirectoryIfEmpty /opt/Arcadify/shell/arcadify_shell
  RemoveDirectoryIfEmpty /opt/Arcadify/shell
  RemoveDirectoryIfEmpty /opt/Arcadify
  RemoveDirectoryIfEmpty /etc/Arcadify
}

RemoveOpenboxMenu() {
  local HomeDirectory
  HomeDirectory="$(getent passwd "${ArcadeUser}" | cut -d: -f6 || true)"

  if [[ -n "${HomeDirectory}" ]]; then
    RemoveFileIfPresent "${HomeDirectory}/.config/openbox/menu.xml"
    RemoveFileIfPresent "${HomeDirectory}/.config/openbox/rc.xml"
    RemoveDirectoryIfEmpty "${HomeDirectory}/.config/openbox"
    RemoveFileIfPresent "${HomeDirectory}/.config/xfce4/terminal/terminalrc"
    RemoveDirectoryIfEmpty "${HomeDirectory}/.config/xfce4/terminal"
    RemoveDirectoryIfEmpty "${HomeDirectory}/.config/xfce4"
  fi
}

RemoveUserIfRequested() {
  if [[ "${RemoveArcadeUser}" != "true" ]]; then
    return
  fi

  if [[ "${UserExistedBeforeInstall}" == "true" ]]; then
    Fail "not removing ${ArcadeUser}; it existed before Arcadify was installed."
  fi

  if [[ "${UserExistedBeforeInstall}" != "false" ]]; then
    Fail "not removing ${ArcadeUser}; no manifest proves Arcadify created this user."
  fi

  if id "${ArcadeUser}" >/dev/null 2>&1; then
    deluser --remove-home "${ArcadeUser}"
  fi
}

main() {
  ParseArguments "$@"
  RequireRoot
  LoadManifestArcadeUser

  if [[ -f "${ManifestFile}" ]]; then
    RestoreFromManifest
  else
    printf 'Arcadify: no install manifest found; using legacy file removal.\n'
    RemoveArcadifyFiles
    RemoveOpenboxMenu
  fi

  RemoveUserIfRequested
  printf 'Arcadify uninstall complete.\n'
}

main "$@"
