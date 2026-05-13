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

RequiredPackages=(
  python3
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
  local BootstrapDirectory

  printf 'Arcadify: installing system files...\n'
  BootstrapDirectory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

  CreateDirectory "${ConfigDirectory}" -m 0755
  CreateDirectory /opt/Arcadify -m 0755
  CreateDirectory /opt/Arcadify/shell -m 0755
  CreateDirectory /opt/Arcadify/shell/arcadify_shell -m 0755
  CreateDirectory /opt/Arcadify/shell/assets -m 0755
  CreateDirectory /opt/Arcadify/shell/assets/icons -m 0755
  CreateDirectory /usr/local/bin -m 0755
  CreateDirectory /usr/share/xsessions -m 0755

  InstallSourceFile "${BootstrapDirectory}/shell/pyproject.toml" /opt/Arcadify/shell/pyproject.toml 0644
  InstallSourceFile "${BootstrapDirectory}/shell/README.md" /opt/Arcadify/shell/README.md 0644
  InstallSourceFile "${BootstrapDirectory}/shell/arcadify_shell/__init__.py" /opt/Arcadify/shell/arcadify_shell/__init__.py 0644
  InstallSourceFile "${BootstrapDirectory}/shell/arcadify_shell/__main__.py" /opt/Arcadify/shell/arcadify_shell/__main__.py 0644
  InstallSourceFile "${BootstrapDirectory}/shell/arcadify_shell/app.py" /opt/Arcadify/shell/arcadify_shell/app.py 0644
  InstallSourceFile "${BootstrapDirectory}/shell/arcadify_shell/config.py" /opt/Arcadify/shell/arcadify_shell/config.py 0644
  InstallSourceFile "${BootstrapDirectory}/shell/Shell.ini" "${ConfigDirectory}/Shell.ini" 0644

  local IconPath
  local IconName
  for IconPath in "${BootstrapDirectory}"/shell/assets/icons/*.png; do
    IconName="$(basename "${IconPath}")"
    InstallSourceFile "${IconPath}" "/opt/Arcadify/shell/assets/icons/${IconName}" 0644
  done

  BackupFileBeforeWrite "${ConfigDirectory}/blank-cursor.xbm"
  cat >"${ConfigDirectory}/blank-cursor.xbm" <<'CURSOR'
#define blank_width 1
#define blank_height 1
static unsigned char blank_bits[] = {
   0x00 };
CURSOR

  BackupFileBeforeWrite "${ConfigDirectory}/blank-cursor-mask.xbm"
  cat >"${ConfigDirectory}/blank-cursor-mask.xbm" <<'CURSOR'
#define blank_width 1
#define blank_height 1
static unsigned char blank_bits[] = {
   0x00 };
CURSOR

  BackupFileBeforeWrite "${ConfigDirectory}/Arcadify.conf"
  cat >"${ConfigDirectory}/Arcadify.conf" <<CONFIG
# Arcadify runtime configuration.
# Re-run Bootstrap.sh or edit this file as root to change the launched game.
ArcadeUser=$(ShellQuote "${ArcadeUser}")
GameCommand=$(ShellQuote "${GameCommand}")
GameExitAction=$(ShellQuote "${GameExitAction}")
CONFIG

  BackupFileBeforeWrite /usr/local/bin/ArcadifyShell
  cat >/usr/local/bin/ArcadifyShell <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

export ARCADIFY_SHELL_CONFIG="${ARCADIFY_SHELL_CONFIG:-/etc/Arcadify/Shell.ini}"
cd /opt/Arcadify/shell
exec python3 -m arcadify_shell
SCRIPT

  BackupFileBeforeWrite /usr/local/bin/ArcadifyLaunchGame
  cat >/usr/local/bin/ArcadifyLaunchGame <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

ConfigFile="/etc/Arcadify/Arcadify.conf"

if [[ -r "${ConfigFile}" ]]; then
  # shellcheck source=/etc/Arcadify/Arcadify.conf
  source "${ConfigFile}"
else
  printf 'Arcadify: missing %s\n' "${ConfigFile}" >&2
  exit 1
fi

if [[ -z "${GameCommand:-}" ]]; then
  printf 'Arcadify: GameCommand is empty.\n' >&2
  exit 1
fi

exec bash -lc "${GameCommand}"
SCRIPT

  BackupFileBeforeWrite /usr/local/bin/ArcadifyMaintenance
  cat >/usr/local/bin/ArcadifyMaintenance <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:0}"

RequestFile="${XDG_RUNTIME_DIR:-/tmp}/ArcadifyLaunchGame"

rm -f "${RequestFile}"
openbox --reconfigure >/dev/null 2>&1 || true

printf 'Arcadify maintenance mode is running.\n'
printf 'Right-click the desktop or use the launcher for Launch Game, Firefox, Files, Archive Manager, Terminal, and Shutdown.\n'

while true; do
  if [[ -e "${RequestFile}" ]]; then
    rm -f "${RequestFile}"
    exit 0
  fi

  Action="$(/usr/local/bin/ArcadifyShell || true)"

  case "${Action}" in
    launch_game)
      exit 0
      ;;
    terminal)
      xfce4-terminal >/dev/null 2>&1 &
      ;;
    files)
      thunar >/dev/null 2>&1 &
      ;;
    browser)
      /usr/local/bin/ArcadifyBrowser >/dev/null 2>&1 &
      ;;
    archive_manager)
      file-roller >/dev/null 2>&1 &
      ;;
    shutdown)
      systemctl poweroff
      ;;
    logout)
      loginctl terminate-user "$USER"
      ;;
  esac

  sleep 1
done
SCRIPT

  BackupFileBeforeWrite /usr/local/bin/ArcadifyRequestLaunch
  cat >/usr/local/bin/ArcadifyRequestLaunch <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

RequestFile="${XDG_RUNTIME_DIR:-/tmp}/ArcadifyLaunchGame"

touch "${RequestFile}"
pkill -u "$(id -u)" -f "python3 -m arcadify_shell" >/dev/null 2>&1 || true
SCRIPT

  BackupFileBeforeWrite /usr/local/bin/ArcadifyBrowser
  cat >/usr/local/bin/ArcadifyBrowser <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

if command -v firefox >/dev/null 2>&1; then
  exec firefox "$@"
fi

if command -v firefox-esr >/dev/null 2>&1; then
  exec firefox-esr "$@"
fi

if command -v x-www-browser >/dev/null 2>&1; then
  exec x-www-browser "$@"
fi

printf 'Arcadify: no supported browser command found.\n' >&2
exit 1
SCRIPT

  BackupFileBeforeWrite /usr/local/bin/ArcadifySession
  cat >/usr/local/bin/ArcadifySession <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

ConfigFile="/etc/Arcadify/Arcadify.conf"

if [[ -r "${ConfigFile}" ]]; then
  # shellcheck source=/etc/Arcadify/Arcadify.conf
  source "${ConfigFile}"
fi

CurrentUser="$(id -un)"

if [[ -n "${ArcadeUser:-}" && "${CurrentUser}" != "${ArcadeUser}" ]]; then
  Message="Arcadify is configured for user ${ArcadeUser}, but this session is running as ${CurrentUser}."
  printf 'Arcadify: %s\n' "${Message}" >&2

  exit 1
fi

ArcadeHome="$(getent passwd "${ArcadeUser:-${CurrentUser}}" | cut -d: -f6 || true)"
if [[ -n "${ArcadeHome}" ]]; then
  export HOME="${ArcadeHome}"
fi

export DISPLAY="${DISPLAY:-:0}"

if command -v xsetroot >/dev/null 2>&1; then
  xsetroot -solid black || true
  xsetroot -cursor /etc/Arcadify/blank-cursor.xbm /etc/Arcadify/blank-cursor-mask.xbm || true
fi

unclutter -idle 0.1 -root >/dev/null 2>&1 &

StartOpenbox() {
  local ConfigFile="${HOME:-}/.config/openbox/rc.xml"

  while true; do
    if [[ -r "${ConfigFile}" ]]; then
      openbox --config-file "${ConfigFile}" >/dev/null 2>&1 || true
    else
      openbox >/dev/null 2>&1 || true
    fi
    sleep 1
  done
}

StartOpenbox &

if command -v xset >/dev/null 2>&1; then
  xset s off || true
  xset -dpms || true
  xset s noblank || true
fi

while true; do
  /usr/local/bin/ArcadifyLaunchGame || true

  case "${GameExitAction:-maintenance}" in
    restart)
      sleep 1
      ;;
    shutdown)
      systemctl poweroff
      ;;
    maintenance|*)
      /usr/local/bin/ArcadifyMaintenance || true
      ;;
  esac
done
SCRIPT

  chmod 0755 /usr/local/bin/ArcadifyLaunchGame
  chmod 0755 /usr/local/bin/ArcadifyShell
  chmod 0755 /usr/local/bin/ArcadifyMaintenance
  chmod 0755 /usr/local/bin/ArcadifyRequestLaunch
  chmod 0755 /usr/local/bin/ArcadifyBrowser
  chmod 0755 /usr/local/bin/ArcadifySession

  BackupFileBeforeWrite /usr/share/xsessions/Arcadify.desktop
  cat >/usr/share/xsessions/Arcadify.desktop <<'DESKTOP'
[Desktop Entry]
Name=Arcadify
Comment=Boot directly into an arcade game
Exec=/usr/local/bin/ArcadifySession
Type=Application
DESKTOP
}

InstallOpenboxConfig() {
  local HomeDirectory
  HomeDirectory="$(getent passwd "${ArcadeUser}" | cut -d: -f6)"
  [[ -n "${HomeDirectory}" ]] || Fail "could not find home directory for ${ArcadeUser}."

  printf 'Arcadify: installing Openbox menu for %s...\n' "${ArcadeUser}"

  CreateDirectory "${HomeDirectory}/.config/openbox" -m 0755 -o "${ArcadeUser}" -g "${ArcadeUser}"

  BackupFileBeforeWrite "${HomeDirectory}/.config/openbox/menu.xml"
  cat >"${HomeDirectory}/.config/openbox/menu.xml" <<'MENU'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Arcadify">
    <item label="Launch Game">
      <action name="Execute">
        <command>/usr/local/bin/ArcadifyRequestLaunch</command>
      </action>
    </item>
    <separator/>
    <item label="Firefox">
      <action name="Execute">
        <command>/usr/local/bin/ArcadifyBrowser</command>
      </action>
    </item>
    <item label="Files">
      <action name="Execute">
        <command>thunar</command>
      </action>
    </item>
    <item label="Archive Manager">
      <action name="Execute">
        <command>file-roller</command>
      </action>
    </item>
    <item label="Terminal">
      <action name="Execute">
        <command>xfce4-terminal</command>
      </action>
    </item>
    <separator/>
    <item label="Shutdown">
      <action name="Execute">
        <command>systemctl poweroff</command>
      </action>
    </item>
  </menu>
</openbox_menu>
MENU

  BackupFileBeforeWrite "${HomeDirectory}/.config/openbox/rc.xml"
  cat >"${HomeDirectory}/.config/openbox/rc.xml" <<'RC'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc"
  xmlns:xi="http://www.w3.org/2001/XInclude">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Primary</monitor>
    <primaryMonitor>1</primaryMonitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout></titleLayout>
    <keepBorder>no</keepBorder>
    <animateIconify>no</animateIconify>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>Arcadify</name>
    </names>
    <popupTime>0</popupTime>
  </desktops>
  <resize>
    <drawContents>yes</drawContents>
    <popupShow>Never</popupShow>
  </resize>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
  </keyboard>
  <mouse>
    <context name="Root">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu">
          <menu>root-menu</menu>
        </action>
      </mousebind>
    </context>
    <context name="Frame">
      <mousebind button="A-Left" action="Drag">
        <action name="Move"/>
      </mousebind>
      <mousebind button="A-Right" action="Drag">
        <action name="Resize"/>
      </mousebind>
    </context>
  </mouse>
  <menu>
    <file>menu.xml</file>
    <hideDelay>200</hideDelay>
    <middle>no</middle>
    <submenuShowDelay>100</submenuShowDelay>
    <submenuHideDelay>400</submenuHideDelay>
    <showIcons>no</showIcons>
  </menu>
</openbox_config>
RC

  chown "${ArcadeUser}:${ArcadeUser}" "${HomeDirectory}/.config/openbox/menu.xml" "${HomeDirectory}/.config/openbox/rc.xml"

  CreateDirectory "${HomeDirectory}/.config/xfce4/terminal" -m 0755 -o "${ArcadeUser}" -g "${ArcadeUser}"

  BackupFileBeforeWrite "${HomeDirectory}/.config/xfce4/terminal/terminalrc"
  cat >"${HomeDirectory}/.config/xfce4/terminal/terminalrc" <<'TERMINAL'
[Configuration]
FontName=Monospace 12
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBordersDefault=TRUE
MiscMenubarDefault=FALSE
MiscToolbarDefault=FALSE
ColorForeground=#E6EDF3
ColorBackground=#0B1020
ColorCursor=#E6EDF3
ColorPalette=#0B1020;#F87171;#34D399;#FBBF24;#60A5FA;#C084FC;#22D3EE;#E6EDF3;#475569;#FCA5A5;#86EFAC;#FDE68A;#93C5FD;#D8B4FE;#67E8F9;#FFFFFF
TERMINAL

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

  BackupFileBeforeWrite /etc/lightdm/lightdm.conf.d/99-Arcadify.conf
  cat >/etc/lightdm/lightdm.conf.d/99-Arcadify.conf <<CONFIG
[Seat:*]
autologin-user=${ArcadeUser}
autologin-user-timeout=0
autologin-session=Arcadify
user-session=Arcadify

[SeatDefaults]
autologin-user=${ArcadeUser}
autologin-user-timeout=0
autologin-session=Arcadify
user-session=Arcadify
CONFIG

  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files lightdm.service >/dev/null 2>&1; then
    systemctl enable -f lightdm.service >/dev/null 2>&1 || true
  fi

  if [[ -x /usr/sbin/lightdm ]]; then
    printf '/usr/sbin/lightdm\n' >/etc/X11/default-display-manager
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
