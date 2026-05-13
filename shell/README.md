# Arcadify Shell

Arcadify Shell is a small fullscreen Tkinter launcher for maintenance mode. It is configuration driven so the shell session can decide what each selected action does.

By default it reads the first available config file from:

```text
$ARCADIFY_SHELL_CONFIG
/etc/Arcadify/Shell.ini
./Shell.ini
```

Run it from this directory during development. On Linux this opens the same canvas-based launcher that Arcadify installs:

```bash
python3 -m arcadify_shell
```

For a non-fullscreen Linux smoke test, point it at the windowed config:

```bash
ARCADIFY_SHELL_CONFIG=/Users/mike/git/arcadify/shell/Shell.dev.ini python3 -m arcadify_shell
```

The selected action is printed to stdout, then the process exits. The caller should branch on that action and launch programs, log out, or power off.
