# Arcadify Shell

Arcadify Shell is a small fullscreen Tkinter launcher for maintenance mode. It is configuration driven so the shell session can decide what each selected action does.

By default it reads the first available config file from:

```text
$ARCADIFY_SHELL_CONFIG
/etc/Arcadify/Shell.ini
./Shell.ini
```

## Requirements

Arcadify Shell uses Python's built-in `tkinter` module. On Debian/Ubuntu, `tkinter` is provided by the system package `python3-tk`, not by `pip`. JPEG and other wallpaper formats use Pillow's ImageTk bindings from `python3-pil.imagetk`.

```bash
sudo apt-get install python3 python3-tk python3-pil.imagetk
```

`Bootstrap.sh` installs these packages automatically unless package installation is skipped.

Run it from this directory during development. On Linux this opens the same canvas-based launcher that Arcadify installs:

```bash
python3 -m arcadify_shell
```

For a non-fullscreen Linux smoke test, point it at the windowed config:

```bash
ARCADIFY_SHELL_CONFIG=/Users/mike/git/arcadify/shell/Shell.dev.ini python3 -m arcadify_shell
```

The built-in drawn icons are `play`, `globe`, `folder`, `archive`, `terminal`, `power`, and `logout`.

The selected action is printed to stdout, then the process exits. The caller should branch on that action and launch programs, log out, or power off.
