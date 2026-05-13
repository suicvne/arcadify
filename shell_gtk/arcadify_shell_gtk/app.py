from __future__ import annotations

from datetime import datetime
from pathlib import Path
import re
import sys

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import Gdk
    from gi.repository import GdkPixbuf
    from gi.repository import GLib
    from gi.repository import Gtk
    from gi.repository import Pango
except (ImportError, ValueError):
    gi = None
    Gdk = None
    GdkPixbuf = None
    GLib = None
    Gtk = None
    Pango = None

from .config import AppConfig, OptionConfig, load_config

GtkWindowBase = Gtk.Window if Gtk is not None else object


class ArcadifyGtkShell(GtkWindowBase):
    def __init__(self, config: AppConfig) -> None:
        super().__init__(title=config.window.title)
        self.config = config
        self.selected_action: str | None = None
        self.assets_directory = Path(__file__).resolve().parents[1] / "assets" / "icons"
        self.background_pixbuf = load_pixbuf(config.background.image)

        self.set_default_size(1100, 720)
        self.set_decorated(not config.window.fullscreen)
        if config.window.fullscreen:
            self.fullscreen()

        self.connect("destroy", self._on_destroy)
        self.connect("key-press-event", self._on_key_press)

        self._install_css()
        self.add(self._build_overlay())
        if config.window.show_clock:
            GLib.timeout_add_seconds(30, self._tick_clock)

    def _install_css(self) -> None:
        css = f"""
        .root {{
          background-color: {self.config.background.color};
        }}
        .panel {{
          background-color: {rgba(self.config.theme.panel, self.config.theme.panel_alpha)};
          border-radius: 28px;
        }}
        .heading {{
          color: {self.config.theme.text};
          font: 700 34px Helvetica, Arial, sans-serif;
        }}
        .subheading, .clock {{
          color: {self.config.theme.muted};
          font: 16px Helvetica, Arial, sans-serif;
        }}
        .clock {{
          font-size: 14px;
        }}
        .option-title {{
          color: {self.config.theme.primary_text};
          font: 700 20px Helvetica, Arial, sans-serif;
        }}
        .option-description {{
          color: {self.config.theme.muted};
          font: 12px Helvetica, Arial, sans-serif;
        }}
        .utility-title {{
          color: {self.config.theme.utility_text};
          font: 700 13px Helvetica, Arial, sans-serif;
        }}
        .option-card {{
          border-radius: 18px;
        }}
        .utility-card {{
          border-radius: 14px;
        }}
        """

        for option in self.config.options:
            class_name = option_class(option.action)
            base = self.config.theme.utility if option.kind == "utility" else self.config.theme.primary
            alpha = 0.62 if option.kind == "utility" else 0.72
            css += f"""
            .{class_name} {{
              background-color: {rgba(blend(base, option.accent, 0.16), alpha)};
            }}
            .{class_name}:hover {{
              background-color: {rgba(blend(base, option.accent, 0.28), min(alpha + 0.08, 1.0))};
            }}
            .{class_name}-stripe {{
              background-color: {rgba(option.accent, 0.92)};
            }}
            """

        provider = Gtk.CssProvider()
        provider.load_from_data(css.encode("utf-8"))
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    def _build_overlay(self) -> Gtk.Overlay:
        overlay = Gtk.Overlay()
        background = Gtk.DrawingArea()
        background.get_style_context().add_class("root")
        background.connect("draw", self._draw_background)
        overlay.add(background)

        panel_outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        panel_outer.set_margin_top(42)
        panel_outer.set_margin_bottom(42)
        panel_outer.set_margin_start(42)
        panel_outer.set_margin_end(42)
        panel_outer.set_halign(Gtk.Align.FILL)
        panel_outer.set_valign(Gtk.Align.FILL)

        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        panel.get_style_context().add_class("panel")
        panel.set_margin_top(0)
        panel.set_margin_bottom(0)
        panel.set_margin_start(0)
        panel.set_margin_end(0)
        panel_outer.pack_start(panel, True, True, 0)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=26)
        content.set_margin_top(34)
        content.set_margin_bottom(28)
        content.set_margin_start(46)
        content.set_margin_end(46)
        panel.pack_start(content, True, True, 0)

        content.pack_start(self._build_header(), False, False, 0)
        content.pack_start(self._build_primary_grid(), True, True, 8)
        content.pack_start(self._build_utility_row(), False, False, 0)

        overlay.add_overlay(panel_outer)
        return overlay

    def _build_header(self) -> Gtk.Grid:
        header = Gtk.Grid()
        header.set_column_spacing(24)
        header.set_hexpand(True)

        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        heading = Gtk.Label(label=self.config.window.heading, xalign=0)
        heading.get_style_context().add_class("heading")
        subheading = Gtk.Label(label=self.config.window.subheading, xalign=0)
        subheading.get_style_context().add_class("subheading")
        title_box.pack_start(heading, False, False, 0)
        title_box.pack_start(subheading, False, False, 0)
        header.attach(title_box, 0, 0, 1, 1)
        title_box.set_hexpand(True)

        self.clock = Gtk.Label(label=current_time(), xalign=1)
        self.clock.get_style_context().add_class("clock")
        if self.config.window.show_clock:
            header.attach(self.clock, 1, 0, 1, 1)

        return header

    def _build_primary_grid(self) -> Gtk.Grid:
        options = [option for option in self.config.options if option.kind != "utility"]
        grid = Gtk.Grid()
        grid.set_row_spacing(18)
        grid.set_column_spacing(18)
        grid.set_column_homogeneous(True)
        grid.set_row_homogeneous(True)
        grid.set_hexpand(True)
        grid.set_vexpand(True)

        columns = 3
        for index, option in enumerate(options):
            row, column = divmod(index, columns)
            grid.attach(self._build_option_card(option, large=True), column, row, 1, 1)

        return grid

    def _build_utility_row(self) -> Gtk.Box:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.set_halign(Gtk.Align.END)
        for option in (option for option in self.config.options if option.kind == "utility"):
            row.pack_start(self._build_option_card(option, large=False), False, False, 0)
        return row

    def _build_option_card(self, option: OptionConfig, large: bool) -> Gtk.EventBox:
        event_box = Gtk.EventBox()
        event_box.set_visible_window(True)
        event_box.get_style_context().add_class(option_class(option.action))
        event_box.get_style_context().add_class("option-card" if large else "utility-card")
        event_box.connect("button-press-event", lambda _widget, _event: self._choose(option.action))

        card = Gtk.Grid()
        card.set_column_spacing(14 if large else 8)
        card.set_margin_top(18 if large else 9)
        card.set_margin_bottom(18 if large else 9)
        card.set_margin_start(0)
        card.set_margin_end(16 if large else 12)
        card.set_hexpand(True)
        card.set_vexpand(large)
        event_box.add(card)

        stripe = Gtk.Box()
        stripe.get_style_context().add_class(f"{option_class(option.action)}-stripe")
        stripe.set_size_request(7, -1)
        card.attach(stripe, 0, 0, 1, 2 if large else 1)

        icon = Gtk.Image.new_from_file(str(self._icon_path(option.icon, large)))
        icon.set_margin_start(18 if large else 12)
        icon.set_margin_end(12 if large else 8)
        icon.set_valign(Gtk.Align.CENTER)
        card.attach(icon, 1, 0, 1, 2 if large else 1)

        labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7 if large else 0)
        labels.set_valign(Gtk.Align.CENTER)
        labels.set_hexpand(True)

        title = Gtk.Label(label=option.label, xalign=0)
        title.get_style_context().add_class("option-title" if large else "utility-title")
        title.set_ellipsize(Pango.EllipsizeMode.END)
        labels.pack_start(title, False, False, 0)

        if large:
            description = Gtk.Label(label=option.description, xalign=0)
            description.get_style_context().add_class("option-description")
            description.set_line_wrap(True)
            labels.pack_start(description, False, False, 0)

        card.attach(labels, 2, 0, 1, 2 if large else 1)
        event_box.set_size_request(-1 if large else 210, 132 if large else 56)
        return event_box

    def _icon_path(self, icon: str, large: bool) -> Path:
        variant = "large" if large else "small"
        path = self.assets_directory / f"{icon}-{variant}.png"
        if path.is_file():
            return path
        return self.assets_directory / f"play-{variant}.png"

    def _draw_background(self, widget: Gtk.Widget, context: object) -> bool:
        allocation = widget.get_allocation()
        width = allocation.width
        height = allocation.height

        context.set_source_rgb(*rgb01(self.config.background.color))
        context.rectangle(0, 0, width, height)
        context.fill()

        if self.background_pixbuf is not None:
            pixbuf = fit_pixbuf(self.background_pixbuf, width, height, self.config.background.image_mode)
            x = (width - pixbuf.get_width()) / 2
            y = (height - pixbuf.get_height()) / 2
            Gdk.cairo_set_source_pixbuf(context, pixbuf, x, y)
            context.paint()

        context.set_source_rgba(*rgb01(self.config.background.overlay), self.config.background.overlay_alpha)
        context.rectangle(0, 0, width, height)
        context.fill()
        return False

    def _on_key_press(self, _widget: Gtk.Widget, event: object) -> bool:
        keyval = event.keyval
        if keyval == Gdk.KEY_q and event.state & Gdk.ModifierType.CONTROL_MASK:
            self._choose("logout")
            return True
        return keyval == Gdk.KEY_Escape

    def _choose(self, action: str) -> None:
        self.selected_action = action
        print(action, flush=True)
        Gtk.main_quit()

    def _on_destroy(self, _widget: Gtk.Widget) -> None:
        Gtk.main_quit()

    def _tick_clock(self) -> bool:
        self.clock.set_text(current_time())
        return True


def load_pixbuf(path: str) -> GdkPixbuf.Pixbuf | None:
    if not path:
        return None
    try:
        return GdkPixbuf.Pixbuf.new_from_file(path)
    except Exception as exc:
        print(f"Arcadify Shell GTK: could not load background image {path!r}: {exc}", file=sys.stderr)
        return None


def fit_pixbuf(pixbuf: GdkPixbuf.Pixbuf, width: int, height: int, mode: str) -> GdkPixbuf.Pixbuf:
    source_width = pixbuf.get_width()
    source_height = pixbuf.get_height()
    if source_width <= 0 or source_height <= 0 or width <= 0 or height <= 0:
        return pixbuf

    if mode == "center":
        return pixbuf

    if mode == "contain":
        scale = min(width / source_width, height / source_height)
    else:
        scale = max(width / source_width, height / source_height)

    target_width = max(1, round(source_width * scale))
    target_height = max(1, round(source_height * scale))
    return pixbuf.scale_simple(target_width, target_height, GdkPixbuf.InterpType.BILINEAR)


def rgba(color: str, alpha: float) -> str:
    red, green, blue = parse_hex(color)
    return f"rgba({red}, {green}, {blue}, {alpha:.3f})"


def rgb01(color: str) -> tuple[float, float, float]:
    red, green, blue = parse_hex(color)
    return red / 255, green / 255, blue / 255


def blend(color_a: str, color_b: str, ratio: float) -> str:
    a = parse_hex(color_a)
    b = parse_hex(color_b)
    mixed = tuple(round(a[i] + (b[i] - a[i]) * ratio) for i in range(3))
    return "#{:02x}{:02x}{:02x}".format(*mixed)


def parse_hex(color: str) -> tuple[int, int, int]:
    value = color.strip().lstrip("#")
    if len(value) == 3:
        value = "".join(part * 2 for part in value)
    if len(value) != 6:
        return (15, 23, 42)
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def option_class(action: str) -> str:
    return "option-" + re.sub(r"[^a-z0-9_-]+", "-", action.lower())


def current_time() -> str:
    return datetime.now().strftime("%I:%M %p").lstrip("0")


def main() -> int:
    if Gtk is None:
        print(
            "Arcadify Shell GTK: GTK3/PyGObject is not installed. "
            "On Debian/Ubuntu, install: sudo apt-get install python3-gi gir1.2-gtk-3.0 gir1.2-gdkpixbuf-2.0",
            file=sys.stderr,
        )
        return 1

    try:
        config = load_config()
        window = ArcadifyGtkShell(config)
        window.show_all()
        Gtk.main()
        return 0
    except Exception as exc:
        print(f"Arcadify Shell GTK: {exc}", file=sys.stderr)
        return 1
