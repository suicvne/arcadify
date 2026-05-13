#!/usr/bin/env bash
set -Eeuo pipefail

ArcadifyVersion="0.1.0"
ArcadeUser="arcade"
GameCommand=""
InstallPackages="true"
EnableAutologin="true"
GameExitAction="maintenance"
ConfigDirectory="/etc/Arcadify"
StateDirectory="/var/lib/Arcadify"
ManifestFile="${StateDirectory}/InstallManifest.tsv"
BackupDirectory="${StateDirectory}/Backups"
SourceDirectory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

RequiredPackages=(
  python3
  python3-pil.imagetk
  python3-tk
  xorg
  openbox
  lightdm
  thunar
  file-roller
  xfce4-terminal
  unclutter
  x11-xserver-utils
)

PrintUsage() {
  cat <<'USAGE'
Arcadify bootstrap installer for Debian/Ubuntu systems.

Usage:
  sudo ./Bootstrap.sh --game-command "/path/to/game --fullscreen" [options]

Options:
  --game-command COMMAND    Command launched in arcade mode.
  --arcade-user USER        Dedicated arcade account. Default: arcade
  --exit-action ACTION      What to do when the game exits: maintenance, restart, shutdown. Default: maintenance
  --skip-packages           Do not run apt-get update/install.
  --no-autologin            Install the session but do not configure LightDM autologin.
  --help                    Show this help.

Examples:
  sudo ./Bootstrap.sh --game-command "/opt/MyGame/MyGame --fullscreen"
  sudo ./Bootstrap.sh --arcade-user cabinet --game-command "firefox --kiosk https://example.com"
USAGE
}

Fail() {
  printf 'Arcadify: %s\n' "$*" >&2
  exit 1
}

RequireRoot() {
  if [[ "${EUID}" -ne 0 ]]; then
    Fail "please run this installer with sudo or as root."
  fi
}

ParseArguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --game-command)
        [[ $# -ge 2 ]] || Fail "--game-command requires a value."
        GameCommand="$2"
        shift 2
        ;;
      --arcade-user)
        [[ $# -ge 2 ]] || Fail "--arcade-user requires a value."
        ArcadeUser="$2"
        shift 2
        ;;
      --exit-action)
        [[ $# -ge 2 ]] || Fail "--exit-action requires a value."
        GameExitAction="$2"
        shift 2
        ;;
      --skip-packages)
        InstallPackages="false"
        shift
        ;;
      --no-autologin)
        EnableAutologin="false"
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

  [[ -n "${GameCommand}" ]] || Fail "missing --game-command."

  case "${GameExitAction}" in
    maintenance|restart|shutdown) ;;
    *) Fail "--exit-action must be maintenance, restart, or shutdown." ;;
  esac

  if [[ ! "${ArcadeUser}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    Fail "--arcade-user must be a valid Linux user name."
  fi
}

ShellQuote() {
  printf "%q" "$1"
}

ManifestHasRecord() {
  local RecordType="$1"
  local RecordName="$2"

  [[ -f "${ManifestFile}" ]] || return 1
  awk -F '\t' -v RecordType="${RecordType}" -v RecordName="${RecordName}" \
    '$1 == RecordType && $2 == RecordName { Found = 1 } END { exit Found ? 0 : 1 }' \
    "${ManifestFile}"
}

ReadManifestValue() {
  local RecordName="$1"

  [[ -f "${ManifestFile}" ]] || return 1
  awk -F '\t' -v RecordName="${RecordName}" \
    '$1 == "Value" && $2 == RecordName { print $3; Found = 1; exit } END { exit Found ? 0 : 1 }' \
    "${ManifestFile}"
}

AppendManifestRecord() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${3:-}" "${4:-}" >>"${ManifestFile}"
}

BackupNameForPath() {
  local Path="$1"
  printf '%s' "${Path}" | sha256sum | awk '{ print $1 }'
}

RecordDirectoryBeforeCreate() {
  local Path="$1"

  if ManifestHasRecord "Directory" "${Path}"; then
    return
  fi

  if [[ -d "${Path}" ]]; then
    AppendManifestRecord "Directory" "${Path}" "present" ""
  else
    AppendManifestRecord "Directory" "${Path}" "missing" ""
  fi
}

CreateDirectory() {
  local Path="$1"
  shift

  RecordDirectoryBeforeCreate "${Path}"
  install -d "$@" "${Path}"
}

InstallSourceFile() {
  local SourcePath="$1"
  local DestinationPath="$2"
  local Mode="${3:-0644}"

  [[ -f "${SourcePath}" ]] || Fail "missing source file: ${SourcePath}"

  BackupFileBeforeWrite "${DestinationPath}"
  install -m "${Mode}" "${SourcePath}" "${DestinationPath}"
}

EscapeSedReplacement() {
  printf '%s' "$1" | sed -e 's/[|&\]/\\&/g'
}

RenderTemplate() {
  local SourcePath="$1"
  local DestinationPath="$2"
  local ArcadeUserValue
  local GameCommandValue
  local GameExitActionValue

  [[ -f "${SourcePath}" ]] || Fail "missing template file: ${SourcePath}"

  ArcadeUserValue="$(EscapeSedReplacement "$(ShellQuote "${ArcadeUser}")")"
  GameCommandValue="$(EscapeSedReplacement "$(ShellQuote "${GameCommand}")")"
  GameExitActionValue="$(EscapeSedReplacement "$(ShellQuote "${GameExitAction}")")"

  sed \
    -e "s|@ARCADE_USER@|$(EscapeSedReplacement "${ArcadeUser}")|g" \
    -e "s|@ARCADE_USER_QUOTED@|${ArcadeUserValue}|g" \
    -e "s|@GAME_COMMAND_QUOTED@|${GameCommandValue}|g" \
    -e "s|@GAME_EXIT_ACTION_QUOTED@|${GameExitActionValue}|g" \
    "${SourcePath}" >"${DestinationPath}"
}

InstallTemplateFile() {
  local TemplatePath="$1"
  local DestinationPath="$2"
  local Mode="${3:-0644}"

  BackupFileBeforeWrite "${DestinationPath}"
  RenderTemplate "${SourceDirectory}/templates/${TemplatePath}.template" "${DestinationPath}"
  chmod "${Mode}" "${DestinationPath}"
}

BackupFileBeforeWrite() {
  local Path="$1"
  local BackupName

  if ManifestHasRecord "File" "${Path}"; then
    return
  fi

  if [[ -e "${Path}" || -L "${Path}" ]]; then
    BackupName="$(BackupNameForPath "${Path}")"
    cp -a "${Path}" "${BackupDirectory}/${BackupName}"
    AppendManifestRecord "File" "${Path}" "present" "${BackupName}"
  else
    AppendManifestRecord "File" "${Path}" "missing" ""
  fi
}

InitializeInstallState() {
  local ExistingArcadeUser
  local PreviousDefaultTarget
  local StoredArcadeUser

  if [[ -f "${ManifestFile}" ]]; then
    StoredArcadeUser="$(ReadManifestValue "ArcadeUser" || true)"
    if [[ -n "${StoredArcadeUser}" && "${StoredArcadeUser}" != "${ArcadeUser}" ]]; then
      Fail "an Arcadify install manifest already exists for user ${StoredArcadeUser}. Run Uninstall.sh before changing --arcade-user."
    fi

    printf 'Arcadify: reusing existing install manifest at %s.\n' "${ManifestFile}"
    install -d -m 0755 "${BackupDirectory}"
    return
  fi

  install -d -m 0755 "${StateDirectory}"
  install -d -m 0700 "${BackupDirectory}"
  : >"${ManifestFile}"
  chmod 0600 "${ManifestFile}"

  if id "${ArcadeUser}" >/dev/null 2>&1; then
    ExistingArcadeUser="true"
  else
    ExistingArcadeUser="false"
  fi

  PreviousDefaultTarget="$(systemctl get-default 2>/dev/null || true)"

  AppendManifestRecord "Value" "ArcadifyVersion" "${ArcadifyVersion}" ""
  AppendManifestRecord "Value" "ArcadeUser" "${ArcadeUser}" ""
  AppendManifestRecord "Value" "UserExistedBeforeInstall" "${ExistingArcadeUser}" ""
  AppendManifestRecord "Value" "PreviousDefaultTarget" "${PreviousDefaultTarget}" ""

  printf 'Arcadify: created install manifest at %s.\n' "${ManifestFile}"
}

DetectBrowserPackage() {
  if apt-cache show firefox >/dev/null 2>&1; then
    printf 'firefox'
    return
  fi

  if apt-cache show firefox-esr >/dev/null 2>&1; then
    printf 'firefox-esr'
    return
  fi

  printf 'firefox'
}

InstallPackageDependencies() {
  if [[ "${InstallPackages}" != "true" ]]; then
    printf 'Arcadify: skipping package installation.\n'
    return
  fi

  command -v apt-get >/dev/null 2>&1 || Fail "apt-get was not found. This bootstrap targets Debian/Ubuntu based systems."

  printf 'Arcadify: updating apt package lists...\n'
  apt-get update

  printf 'Arcadify: installing desktop/session packages...\n'
  local BrowserPackage
  BrowserPackage="$(DetectBrowserPackage)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${RequiredPackages[@]}" "${BrowserPackage}"
}

BackupPackageManagedState() {
  BackupFileBeforeWrite /etc/X11/default-display-manager
  BackupFileBeforeWrite /etc/systemd/system/display-manager.service
}

CreateArcadeUser() {
  if id "${ArcadeUser}" >/dev/null 2>&1; then
    printf 'Arcadify: user %s already exists.\n' "${ArcadeUser}"
    return
  fi

  printf 'Arcadify: creating user %s...\n' "${ArcadeUser}"
  adduser --disabled-password --gecos "" "${ArcadeUser}"
}

InstallSystemFiles() {
  printf 'Arcadify: installing system files...\n'

  CreateDirectory "${ConfigDirectory}" -m 0755
  CreateDirectory /opt/Arcadify -m 0755
  CreateDirectory /opt/Arcadify/shell -m 0755
  CreateDirectory /opt/Arcadify/shell/arcadify_shell -m 0755
  CreateDirectory /opt/Arcadify/shell/assets -m 0755
  CreateDirectory /opt/Arcadify/shell/assets/icons -m 0755
  CreateDirectory /usr/local/bin -m 0755
  CreateDirectory /usr/share/xsessions -m 0755

  InstallSourceFile "${SourceDirectory}/shell/pyproject.toml" /opt/Arcadify/shell/pyproject.toml 0644
  InstallSourceFile "${SourceDirectory}/shell/README.md" /opt/Arcadify/shell/README.md 0644
  InstallSourceFile "${SourceDirectory}/shell/arcadify_shell/__init__.py" /opt/Arcadify/shell/arcadify_shell/__init__.py 0644
  InstallSourceFile "${SourceDirectory}/shell/arcadify_shell/__main__.py" /opt/Arcadify/shell/arcadify_shell/__main__.py 0644
  InstallSourceFile "${SourceDirectory}/shell/arcadify_shell/app.py" /opt/Arcadify/shell/arcadify_shell/app.py 0644
  InstallSourceFile "${SourceDirectory}/shell/arcadify_shell/config.py" /opt/Arcadify/shell/arcadify_shell/config.py 0644
  InstallSourceFile "${SourceDirectory}/shell/Shell.ini" "${ConfigDirectory}/Shell.ini" 0644

  local IconPath
  local IconName
  for IconPath in "${SourceDirectory}"/shell/assets/icons/*.png; do
    IconName="$(basename "${IconPath}")"
    InstallSourceFile "${IconPath}" "/opt/Arcadify/shell/assets/icons/${IconName}" 0644
  done

  InstallTemplateFile etc/Arcadify/blank-cursor.xbm "${ConfigDirectory}/blank-cursor.xbm" 0644
  InstallTemplateFile etc/Arcadify/blank-cursor-mask.xbm "${ConfigDirectory}/blank-cursor-mask.xbm" 0644
  InstallTemplateFile etc/Arcadify/Arcadify.conf "${ConfigDirectory}/Arcadify.conf" 0644
  InstallTemplateFile usr/local/bin/ArcadifyShell /usr/local/bin/ArcadifyShell 0755
  InstallTemplateFile usr/local/bin/ArcadifyLaunchGame /usr/local/bin/ArcadifyLaunchGame 0755
  InstallTemplateFile usr/local/bin/ArcadifyMaintenance /usr/local/bin/ArcadifyMaintenance 0755
  InstallTemplateFile usr/local/bin/ArcadifyRequestLaunch /usr/local/bin/ArcadifyRequestLaunch 0755
  InstallTemplateFile usr/local/bin/ArcadifyBrowser /usr/local/bin/ArcadifyBrowser 0755
  InstallTemplateFile usr/local/bin/ArcadifySession /usr/local/bin/ArcadifySession 0755

  InstallTemplateFile usr/share/xsessions/Arcadify.desktop /usr/share/xsessions/Arcadify.desktop 0644
}

InstallOpenboxConfig() {
  local HomeDirectory
  HomeDirectory="$(getent passwd "${ArcadeUser}" | cut -d: -f6)"
  [[ -n "${HomeDirectory}" ]] || Fail "could not find home directory for ${ArcadeUser}."

  printf 'Arcadify: installing Openbox menu for %s...\n' "${ArcadeUser}"

  CreateDirectory "${HomeDirectory}/.config" -m 0755 -o "${ArcadeUser}" -g "${ArcadeUser}"
  CreateDirectory "${HomeDirectory}/.config/openbox" -m 0755 -o "${ArcadeUser}" -g "${ArcadeUser}"
  chown "${ArcadeUser}:${ArcadeUser}" "${HomeDirectory}/.config" "${HomeDirectory}/.config/openbox"

  InstallTemplateFile home/arcade/.config/openbox/menu.xml "${HomeDirectory}/.config/openbox/menu.xml" 0644
  InstallTemplateFile home/arcade/.config/openbox/rc.xml "${HomeDirectory}/.config/openbox/rc.xml" 0644

  chown "${ArcadeUser}:${ArcadeUser}" "${HomeDirectory}/.config/openbox/menu.xml" "${HomeDirectory}/.config/openbox/rc.xml"

  CreateDirectory "${HomeDirectory}/.config/xfce4/terminal" -m 0755 -o "${ArcadeUser}" -g "${ArcadeUser}"
  chown "${ArcadeUser}:${ArcadeUser}" "${HomeDirectory}/.config/xfce4" "${HomeDirectory}/.config/xfce4/terminal"

  InstallTemplateFile home/arcade/.config/xfce4/terminal/terminalrc "${HomeDirectory}/.config/xfce4/terminal/terminalrc" 0644

  chown "${ArcadeUser}:${ArcadeUser}" "${HomeDirectory}/.config/xfce4/terminal/terminalrc"
}

ConfigureAutologin() {
  if [[ "${EnableAutologin}" != "true" ]]; then
    printf 'Arcadify: skipping LightDM autologin configuration.\n'
    return
  fi

  printf 'Arcadify: configuring LightDM autologin...\n'
  CreateDirectory /etc/lightdm/lightdm.conf.d -m 0755

  if [[ -f /etc/lightdm/lightdm.conf ]] && grep -Eq '^[[:space:]]*autologin-user[[:space:]]*=' /etc/lightdm/lightdm.conf; then
    printf 'Arcadify: removing autologin-user from /etc/lightdm/lightdm.conf so Arcadify can choose %s from 99-Arcadify.conf.\n' "${ArcadeUser}"
    BackupFileBeforeWrite /etc/lightdm/lightdm.conf
    sed -i '/^[[:space:]]*autologin-user[[:space:]]*=/d' /etc/lightdm/lightdm.conf
  fi

  BackupFileBeforeWrite /etc/lightdm/lightdm.conf.d/50-Arcadify.conf
  rm -f /etc/lightdm/lightdm.conf.d/50-Arcadify.conf

  InstallTemplateFile etc/lightdm/lightdm.conf.d/99-Arcadify.conf /etc/lightdm/lightdm.conf.d/99-Arcadify.conf 0644

  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files lightdm.service >/dev/null 2>&1; then
    systemctl enable -f lightdm.service >/dev/null 2>&1 || true
  fi

  if [[ -x /usr/sbin/lightdm ]]; then
    InstallTemplateFile etc/X11/default-display-manager /etc/X11/default-display-manager 0644
  fi

  systemctl set-default graphical.target >/dev/null 2>&1 || true
}

PrintNextSteps() {
  cat <<NEXT

Arcadify ${ArcadifyVersion} installed.

Installed:
  ${ConfigDirectory}/Arcadify.conf
  /var/lib/Arcadify/InstallManifest.tsv
  /usr/local/bin/ArcadifySession
  /usr/local/bin/ArcadifyLaunchGame
  /usr/local/bin/ArcadifyShell
  /usr/local/bin/ArcadifyRequestLaunch
  /usr/local/bin/ArcadifyMaintenance
  /usr/local/bin/ArcadifyBrowser
  /opt/Arcadify/shell/
  ${ConfigDirectory}/Shell.ini
  /usr/share/xsessions/Arcadify.desktop
  /etc/lightdm/lightdm.conf.d/99-Arcadify.conf
  ${ConfigDirectory}/blank-cursor.xbm
  ${ConfigDirectory}/blank-cursor-mask.xbm
  /home/${ArcadeUser}/.config/openbox/menu.xml
  /home/${ArcadeUser}/.config/openbox/rc.xml
  /home/${ArcadeUser}/.config/xfce4/terminal/terminalrc

Next:
  If /etc/lightdm/lightdm.conf had autologin-user set, Arcadify removed only that setting after backing up the file.
  Reboot to enter Arcadify automatically if LightDM autologin was enabled.
  To verify LightDM autologin before rebooting, run: lightdm --show-config
  Run ./Uninstall.sh later to remove Arcadify's system files.
NEXT
}

main() {
  ParseArguments "$@"
  RequireRoot
  InitializeInstallState
  BackupPackageManagedState
  InstallPackageDependencies
  CreateArcadeUser
  InstallSystemFiles
  InstallOpenboxConfig
  ConfigureAutologin
  PrintNextSteps
}

main "$@"
