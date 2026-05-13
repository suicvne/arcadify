# Arcadify

Arcadify is a small bootstrap layer for turning a normal Debian/Ubuntu install into a simple arcade-style session.

The first version installs:

- a dedicated arcade user
- a custom `Arcadify` X session
- LightDM configured as the display manager with autologin into that session
- an Arcadify-controlled Openbox maintenance menu
- a fullscreen, configuration-driven Arcadify Shell maintenance launcher
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

When the game exits, Arcadify shows a fullscreen maintenance launcher with large icon buttons for common actions and smaller utility buttons for shutdown/logout.
Choosing Launch Game returns control to the main Arcadify session supervisor before relaunching the game, so exiting a relaunched game goes back to maintenance mode instead of ending the login session.

The launcher is configured from `/etc/Arcadify/Shell.ini`. That file controls labels, icons, button grouping, colors, and an optional background image without requiring command-line arguments.

## Installed Files

```text
/etc/Arcadify/Arcadify.conf
/etc/Arcadify/Shell.ini
/var/lib/Arcadify/InstallManifest.tsv
/var/lib/Arcadify/Backups/
/usr/local/bin/ArcadifySession
/usr/local/bin/ArcadifyLaunchGame
/usr/local/bin/ArcadifyShell
/usr/local/bin/ArcadifyRequestLaunch
/usr/local/bin/ArcadifyMaintenance
/usr/local/bin/ArcadifyBrowser
/opt/Arcadify/shell/
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

If `/etc/lightdm/lightdm.conf` exists and contains an `autologin-user=` setting, Arcadify backs up that file and removes only that setting. This prevents the main LightDM config from overriding Arcadify's `/etc/lightdm/lightdm.conf.d/99-Arcadify.conf` autologin user.

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

# Technical Deep Dive

Arcadify is not a singular program or script, rather it is a set of scripts designed to convert a specific user on your Ubuntu-based system to launch into a singular game. To expand upon this idea, the maintenance menu "shell" was added as well.

Arcadify uses existing Linux technologies and is surprisingly simple on the surface. Everything is scripted: that means that this entire setup is accomplished by installing/modifying configuration files and script files.

This technical deep dive will focus on Arcadify's operation post bootstrapping.

## Tech Stack

* Protocol: X11
* Desktop Manager: LightDM
* Window Manager: Openbox
* Shell: Scripted; Your app then maintenance app in a loop
  * Maintenance shell: Python 3, Tkinter UI (canvas based)
  * Browser: Firefox, Firefox ESR, falls back to x-www-browser
  * Terminal: xfce4-terminal
  * Archive Manager: file-roller
  * File Manager: thunar
  * Addons: unclutter

## Entry

The entry point for Arcadify is in `/usr/local/bin/ArcadifySession`, also exported as an xsession at `Arcadify.desktop.template`. It's a bash script, and tries to be as straightforward as possible.

As a session, Arcadify has a few basic goals:
* Ensure that you are running as the user we expect you to run as.
* Set a blank cursor and launch unclutter
* Start and wait for Openbox
* Configure X11: Disable screen saver, disable DPMS, no blank screen on activation
* Enter into the session main loop:
  * Launch your configured game
  * Perform game exit action
  * Repeat... (unless the game exit action is "sleep" or "poweroff")

### ArcadifyLaunchGame

The game launch is handled as a bash script in `/usr/local/bin/ArcadifyLaunchGame`.

This wrapper is drastically simpler:
* Load config.
* Validate the game command exists
* Execute the game command

Whatever happens after the game command exits is handled in `ArcadifySession`.

### ArcadifyMaintenance (Maintenance shell)

The maintenance shell is a simple Python application built against Tkinter that provides a series of buttons for launching various support applications. Like everything else in Arcadify, its launcher is a bash script installed to `/usr/local/bin/ArcadifyMaintenance`. 

The bulk of the heavy lifting is actually accomplished inside of `ArcadifyMaintenance`, the shell is simply a visual component that returns a string stating what we should do. This shell is launched through a bash script as well, `/usr/local/bin/ArcadifyShell`. 

The options are as follows:

* `launch_game` - Exits `ArcadifyMaintenance`, returning back to the entry main loop and launching the user configured game again.
* `terminal` - Launches `xfce4-terminal`
* `files` - Launches `thunar`
* `browser` - Launches `firefox`
* `archive_manager` - Launches `file-roller`
* `shutdown` - Powers down the system
* `logout` - Logs out of the configured arcade user, returning the user to their default login manager.

When the maintenance shell launches an application, excluding the user configured game, it enters into a waiting loop to ensure that the actual visual shell is not launched over the application.

#### ArcadifyShell

`ArcadifyShell` simply launches the actual visual application that allows the user to select an action. The default implementation will launch the Python visual shell installed to `/opt/Arcadify/shell`.

#### arcadify_shell

This is the actual Python application that renders the visual component. Tkinter is used as the toolkit, with Pillow's ImageTk system used to assist in compositing and rendering images.

The shell is small in scope, but highly configurable. It's built as a Python module with the bulk of the code being in `app.py`. 

`class ArcadifyShell` manages the lifetime and functionality of the UI. When it's constructed, the key UI elements are built. `_draw` is where the top level draw loop starts. 

This is a Canvas based application, and certain images are collected to be composited together later since Tk doesn't naturally support drawing partially translucent quads.

The draw loop is as follows:

* Clear screen, clear shape images array
* Draw the user configured background, if present.
* Draw the actual panel containing the information and buttons.

When translucent rectangles are drawn, they're drawn to Tk Images and pushed into the `shape_images` array. Simultaneously, they are composited to the screen.

##### Configuration
Primary configuration sections and then keys are described:

* `window` - Window and panel settings
  * `title` - Configures the title of the window, unlikely to ever be seen.
  * `heading` - Configures the user visible heading of the shell application. Defaults to `Maintenance Mode`
  * `subheading` - Configures user visible subheading; defaults to `Choose what you would like to do next.`
  * `fullscreen` - Whether to show fullscreen or not; defaults to `true`.
  * `show_clock` - Whether to show the clock in the upper right corner of the panel or not. Defaults to `true`.
* `background` - Configures the background of the shell
  * `color` - The background color to use with the wallpaper. Defaults to #0f172a
  * `image` - Path to an image to load and use as a background. Defaults to nothing.
  * `image_mode` - How to fit the image in the canvas. Options: `cover`, `contain`, `center`, `tile`. Defaults to `cover`
  * `overlay` - A color to overlay on top of the wallpaper for aesthetics. Defaults to #07111f
  * `overlay_alpha` - How transparent `overlay` should be on top of the wallpaper. Defaults to 0.62
* `theme` - Configures how panels and text look in the shell
* `option.*` - Configures how options are displayed in the menu. The `*` means there will be one entry that corresponds to a valid `ArcadifyMaintenance` launch option. (Ex: `[option.browser]`)
