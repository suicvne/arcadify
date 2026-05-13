# Arcadify

Arcadify is a small bootstrap layer for turning a normal Debian/Ubuntu install into a simple arcade-style session.

The first version installs:

- a dedicated arcade user
- a custom `Arcadify` X session
- LightDM configured as the display manager with autologin into that session
- an Arcadify-controlled Openbox maintenance menu
- launch scripts for the game and fallback maintenance mode
- a browser launcher that works with `firefox`, `firefox-esr`, or `x-www-browser`
- a dark terminal profile for the arcade user
- a restore manifest and backups for files Arcadify changes

## Install

Run this on the target Debian/Ubuntu machine:

```bash
sudo ./Bootstrap.sh --game-command "/path/to/game --fullscreen"
```

Useful options:

```bash
sudo ./Bootstrap.sh \
  --arcade-user arcade \
  --game-command "/opt/MyGame/MyGame --fullscreen" \
  --exit-action maintenance
```

`--exit-action` can be:

- `maintenance`: when the game exits, show maintenance mode
- `restart`: restart the game after it exits
- `shutdown`: power off after the game exits

For browser-based cabinets:

```bash
sudo ./Bootstrap.sh --game-command "firefox --kiosk https://example.com"
```

## Maintenance Mode

Maintenance mode uses Openbox and provides a right-click menu with:

- Launch Game
- Firefox
- Files
- Archive Manager
- Terminal
- Shutdown

If `xmessage` is available, Arcadify also shows a small maintenance launcher when the game exits.
Choosing Launch Game returns control to the main Arcadify session supervisor before relaunching the game, so exiting a relaunched game goes back to maintenance mode instead of ending the login session.

## Installed Files

```text
/etc/Arcadify/Arcadify.conf
/var/lib/Arcadify/InstallManifest.tsv
/var/lib/Arcadify/Backups/
/usr/local/bin/ArcadifySession
/usr/local/bin/ArcadifyLaunchGame
/usr/local/bin/ArcadifyRequestLaunch
/usr/local/bin/ArcadifyMaintenance
/usr/local/bin/ArcadifyBrowser
/usr/share/xsessions/Arcadify.desktop
/etc/lightdm/lightdm.conf.d/99-Arcadify.conf
/etc/Arcadify/blank-cursor.xbm
/etc/Arcadify/blank-cursor-mask.xbm
/home/<arcade-user>/.config/openbox/menu.xml
/home/<arcade-user>/.config/openbox/rc.xml
/home/<arcade-user>/.config/xfce4/terminal/terminalrc
```

## Restore Safety

Before Arcadify writes a file, it records that path in:

```text
/var/lib/Arcadify/InstallManifest.tsv
```

If the file already existed, Arcadify stores a copy in:

```text
/var/lib/Arcadify/Backups/
```

If the file did not exist, the manifest records that too. Re-running `Bootstrap.sh` keeps the original pre-Arcadify backups instead of backing up Arcadify over itself, so you can iterate on the game command and settings cleanly.

`Uninstall.sh` restores existing files, removes files Arcadify created, restores the previous systemd default target, restores common display-manager pointers touched by LightDM setup, and removes directories Arcadify created when they are empty.

Packages installed with `apt-get` are intentionally not removed. Other sessions or users may rely on those packages.

## Change The Game Command

Edit this file as root:

```bash
sudo nano /etc/Arcadify/Arcadify.conf
```

Then restart the session or reboot.

## Uninstall

```bash
sudo ./Uninstall.sh
```

To also remove the dedicated arcade user and home directory:

```bash
sudo ./Uninstall.sh --remove-user
```

`--remove-user` only removes the account if the manifest proves Arcadify created it. It refuses to delete a pre-existing user.

## Notes

Arcadify intentionally starts loose rather than locked down. The arcade user is a normal user and should not be given sudo unless you explicitly want that.
