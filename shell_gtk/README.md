# Arcadify Shell GTK

This is a GTK3 prototype of the Arcadify maintenance launcher. It keeps the same configuration shape and stdout action contract as the Tk shell, but uses GTK/Cairo/CSS so translucent panels and buttons render properly.

## Requirements

```bash
sudo apt-get install python3 python3-gi gir1.2-gtk-3.0 gir1.2-gdkpixbuf-2.0
```

## Run

From this directory:

```bash
python3 -m arcadify_shell_gtk
```

For a windowed smoke test:

```bash
ARCADIFY_SHELL_CONFIG=/Users/mike/git/arcadify/shell_gtk/Shell.dev.ini python3 -m arcadify_shell_gtk
```

Clicking an option prints its action, such as `launch_game`, to stdout and exits.
