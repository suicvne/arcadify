from __future__ import annotations

from datetime import datetime
from math import ceil
from pathlib import Path
import sys

try:
    import tkinter as tk
    from tkinter import font as tkfont
except ModuleNotFoundError:
    tk = None
    tkfont = None

try:
    from PIL import Image
    from PIL import ImageOps
    from PIL import ImageTk
except ModuleNotFoundError:
    Image = None
    ImageOps = None
    ImageTk = None

from .config import AppConfig, OptionConfig, load_config


class ArcadifyShell:
    def __init__(self, root: tk.Tk, config: AppConfig) -> None:
        self.root = root
        self.config = config
        self.selected_action: str | None = None
        self.background_image: tk.PhotoImage | None = None
        self.icon_images: dict[tuple[str, str], tk.PhotoImage] = {}
        self.icon_directory = Path(__file__).resolve().parents[1] / "assets" / "icons"

        self.root.title(config.window.title)
        self.root.configure(bg=config.background.color)
        self.root.geometry(self._initial_geometry())
        self.root.update_idletasks()
        if config.window.fullscreen:
            self.root.after(100, lambda: self.root.attributes("-fullscreen", True))
        self.root.bind("<Escape>", lambda _event: None)
        self.root.bind("<Control-q>", lambda _event: self._choose("logout"))
        self.warned_background_error = False

        self.screen = tk.Canvas(root, highlightthickness=0, bd=0, bg=config.background.color)
        self.screen.pack(fill="both", expand=True)
        self.screen.bind("<Configure>", self._draw)
        self.root.after_idle(self._draw)

        if config.window.show_clock:
            self.root.after(30_000, self._tick_clock)

    def _initial_geometry(self) -> str:
        if self.config.window.fullscreen:
            return f"{self.root.winfo_screenwidth()}x{self.root.winfo_screenheight()}+0+0"
        return "1100x720+80+80"

    def _draw(self, event: tk.Event | None = None) -> None:
        width = max(self.screen.winfo_width(), 1)
        height = max(self.screen.winfo_height(), 1)
        if width < 20 or height < 20:
            self.root.after(25, self._draw)
            return

        self.screen.delete("all")
        self._draw_background(width, height)
        self._draw_panel(width, height)

    def _draw_background(self, width: int, height: int) -> None:
        image_path = self.config.background.image
        if image_path:
            try:
                self.background_image = self._load_background_image(image_path, width, height)
                if self.config.background.image_mode == "tile":
                    self._tile_background(self.background_image, width, height)
                else:
                    self.screen.create_image(width // 2, height // 2, image=self.background_image)
            except Exception as exc:
                if not self.warned_background_error:
                    print(f"Arcadify Shell: could not load background image {image_path!r}: {exc}", file=sys.stderr)
                    self.warned_background_error = True
                self._draw_gradient(width, height)
        else:
            self._draw_gradient(width, height)

        overlay = blend(self.config.background.color, self.config.background.overlay, self.config.background.overlay_alpha)
        self.screen.create_rectangle(0, 0, width, height, fill=overlay, outline="")

    def _draw_gradient(self, width: int, height: int) -> None:
        top = self.config.background.color
        bottom = blend(top, "#020617", 0.58)
        steps = 42
        for index in range(steps):
            y0 = int(height * index / steps)
            y1 = int(height * (index + 1) / steps) + 1
            color = blend(top, bottom, index / max(steps - 1, 1))
            self.screen.create_rectangle(0, y0, width, y1, fill=color, outline="")

    def _load_background_image(self, image_path: str, width: int, height: int) -> tk.PhotoImage:
        if Image is not None and ImageOps is not None and ImageTk is not None:
            image = Image.open(image_path)
            mode = self.config.background.image_mode
            if mode == "cover":
                image = ImageOps.fit(image, (width, height), method=Image.Resampling.LANCZOS)
            elif mode == "contain":
                image = ImageOps.contain(image, (width, height), method=Image.Resampling.LANCZOS)
            elif mode == "tile":
                pass
            elif mode != "center":
                image = ImageOps.fit(image, (width, height), method=Image.Resampling.LANCZOS)
            return ImageTk.PhotoImage(image)

        source = tk.PhotoImage(file=image_path)
        return self._prepare_background_image(source, width, height)

    def _prepare_background_image(self, image: tk.PhotoImage, width: int, height: int) -> tk.PhotoImage:
        mode = self.config.background.image_mode
        if mode in {"center", "tile"}:
            return image

        image_width = max(image.width(), 1)
        image_height = max(image.height(), 1)
        scale = max(width / image_width, height / image_height) if mode == "cover" else min(width / image_width, height / image_height)

        if scale > 1:
            image = image.zoom(max(1, ceil(scale)), max(1, ceil(scale)))
        elif scale < 1:
            image = image.subsample(max(1, ceil(1 / scale)), max(1, ceil(1 / scale)))

        return image

    def _tile_background(self, image: tk.PhotoImage, width: int, height: int) -> None:
        tile_width = max(image.width(), 1)
        tile_height = max(image.height(), 1)
        for y in range(0, height + tile_height, tile_height):
            for x in range(0, width + tile_width, tile_width):
                self.screen.create_image(x, y, anchor="nw", image=image)

    def _draw_panel(self, width: int, height: int) -> None:
        margin = max(42, min(width, height) // 16)
        panel_color = blend(self.config.background.color, self.config.theme.panel, self.config.theme.panel_alpha)
        panel_x0 = margin
        panel_y0 = margin
        panel_x1 = width - margin
        panel_y1 = height - margin

        rounded_rectangle(self.screen, panel_x0, panel_y0, panel_x1, panel_y1, 28, fill=panel_color, outline="")

        heading_font = tkfont.Font(family="Helvetica", size=max(28, min(52, width // 24)), weight="bold")
        subheading_font = tkfont.Font(family="Helvetica", size=max(13, min(20, width // 64)))
        clock_font = tkfont.Font(family="Helvetica", size=max(12, min(18, width // 80)))

        content_inset = max(32, width // 24)
        left = panel_x0 + content_inset
        right = panel_x1 - content_inset
        top = panel_y0 + max(28, height // 22)
        self.screen.create_text(left, top, text=self.config.window.heading, anchor="nw", fill=self.config.theme.text, font=heading_font)
        self.screen.create_text(left, top + heading_font.metrics("linespace") + 8, text=self.config.window.subheading, anchor="nw", fill=self.config.theme.muted, font=subheading_font)

        if self.config.window.show_clock:
            self.screen.create_text(right, top + 4, text=datetime.now().strftime("%I:%M %p").lstrip("0"), anchor="ne", fill=self.config.theme.muted, font=clock_font)

        primary_options = [option for option in self.config.options if option.kind != "utility"]
        utility_options = [option for option in self.config.options if option.kind == "utility"]
        grid_top = top + heading_font.metrics("linespace") + subheading_font.metrics("linespace") + 44
        utility_height = 80 if utility_options else 0
        grid_bottom = panel_y1 - max(28, height // 28) - utility_height
        content_width = right - left
        self._draw_primary_options(primary_options, left, grid_top, content_width, max(160, grid_bottom - grid_top))
        self._draw_utility_options(utility_options, left, panel_y1 - 84, content_width, 56)

    def _draw_primary_options(self, options: list[OptionConfig], x: int, y: int, width: int, height: int) -> None:
        columns = 3 if width >= 900 and len(options) > 2 else 2
        if width < 620:
            columns = 1

        gap = 18
        rows = (len(options) + columns - 1) // columns
        tile_width = int((width - gap * (columns - 1)) / columns)
        tile_height = min(168, max(118, int((height - gap * max(rows - 1, 0)) / max(rows, 1))))

        for index, option in enumerate(options):
            row, column = divmod(index, columns)
            self._draw_option(option, x + column * (tile_width + gap), y + row * (tile_height + gap), tile_width, tile_height, large=True)

    def _draw_utility_options(self, options: list[OptionConfig], x: int, y: int, width: int, height: int) -> None:
        if not options:
            return

        gap = 12
        button_width = min(210, int((width - gap * (len(options) - 1)) / max(len(options), 1)))
        start_x = x + width - (button_width * len(options) + gap * (len(options) - 1))
        for index, option in enumerate(options):
            self._draw_option(option, start_x + index * (button_width + gap), y, button_width, height, large=False)

    def _draw_option(self, option: OptionConfig, x: int, y: int, width: int, height: int, large: bool) -> None:
        base = self.config.theme.primary if large else self.config.theme.utility
        text_color = self.config.theme.primary_text if large else self.config.theme.utility_text
        fill = blend(base, option.accent, 0.18 if large else 0.1)
        active = blend(fill, option.accent, 0.22)
        tag = f"option:{option.action}"

        accent_width = 7
        text_offset = 90 if large else 50
        icon_padding = 13 if large else 9

        rounded_rectangle(self.screen, x, y, x + width, y + height, 18 if large else 14, fill=fill, outline="", tags=(tag,))
        self.screen.create_rectangle(x, y, x + accent_width, y + height, fill=option.accent, outline="", tags=(tag,))

        icon_lane_width = text_offset - accent_width
        icon_size = max(20, icon_lane_width - icon_padding * 2)
        icon_x = x + accent_width + icon_lane_width / 2
        icon_y = y + height // 2
        self._draw_icon(option.icon, icon_x, icon_y, icon_size, option.accent, tag, large=large)

        title_font = tkfont.Font(family="Helvetica", size=20 if large else 13, weight="bold")
        body_font = tkfont.Font(family="Helvetica", size=12 if large else 10)
        text_x = x + text_offset
        text_width = max(24, width - text_offset - (20 if large else 12))
        self.screen.create_text(text_x, y + (34 if large else 14), text=option.label, anchor="nw", fill=text_color, font=title_font, width=text_width, tags=(tag,))
        if large and option.description:
            self.screen.create_text(text_x, y + 70, text=option.description, anchor="nw", fill=self.config.theme.muted, font=body_font, width=text_width, tags=(tag,))

        self.screen.tag_bind(tag, "<Button-1>", lambda _event, action=option.action: self._choose(action))
        self.screen.tag_bind(tag, "<Enter>", lambda _event, t=tag, c=active: self._set_option_fill(t, c))
        self.screen.tag_bind(tag, "<Leave>", lambda _event, t=tag, c=fill: self._set_option_fill(t, c))

    def _draw_icon(self, name: str, cx: int, cy: int, size: int, color: str, tag: str, large: bool) -> None:
        image = self._get_icon_image(name, large)
        if image is None:
            self._draw_canvas_icon(name, cx, cy, size, color, tag)
            return

        self.screen.create_image(cx, cy, image=image, tags=(tag,))

    def _get_icon_image(self, name: str, large: bool) -> tk.PhotoImage | None:
        variant = "large" if large else "small"
        key = (name, variant)
        if key not in self.icon_images:
            path = self.icon_directory / f"{name}-{variant}.png"
            if not path.is_file():
                return None
            self.icon_images[key] = tk.PhotoImage(file=str(path))
        return self.icon_images[key]

    def _draw_canvas_icon(self, name: str, cx: int, cy: int, size: int, color: str, tag: str) -> None:
        half = size // 2
        stroke = max(2, round(size / 16))
        x0, y0, x1, y1 = cx - half, cy - half, cx + half, cy + half
        self.screen.create_oval(x0, y0, x1, y1, outline=color, width=stroke, tags=(tag,))

        if name == "play":
            self.screen.create_polygon(cx - size * 0.12, cy - size * 0.22, cx - size * 0.12, cy + size * 0.22, cx + size * 0.25, cy, fill=color, outline="", tags=(tag,))
        elif name == "terminal":
            self.screen.create_line(cx - size * 0.22, cy - size * 0.1, cx - size * 0.05, cy, cx - size * 0.22, cy + size * 0.1, fill=color, width=stroke, tags=(tag,))
            self.screen.create_line(cx + size * 0.02, cy + size * 0.16, cx + size * 0.24, cy + size * 0.16, fill=color, width=stroke, tags=(tag,))
        elif name == "folder":
            self.screen.create_line(cx - size * 0.25, cy - size * 0.08, cx - size * 0.08, cy - size * 0.22, cx + size * 0.25, cy - size * 0.22, cx + size * 0.25, cy + size * 0.2, cx - size * 0.25, cy + size * 0.2, cx - size * 0.25, cy - size * 0.08, fill=color, width=stroke, tags=(tag,))
        elif name == "globe":
            self.screen.create_oval(cx - size * 0.22, cy - size * 0.22, cx + size * 0.22, cy + size * 0.22, outline=color, width=stroke, tags=(tag,))
            self.screen.create_line(cx - size * 0.22, cy, cx + size * 0.22, cy, fill=color, width=stroke, tags=(tag,))
            self.screen.create_line(cx, cy - size * 0.22, cx, cy + size * 0.22, fill=color, width=stroke, tags=(tag,))
        elif name == "archive":
            self.screen.create_rectangle(cx - size * 0.22, cy - size * 0.2, cx + size * 0.22, cy + size * 0.22, outline=color, width=stroke, tags=(tag,))
            self.screen.create_line(cx - size * 0.22, cy - size * 0.04, cx + size * 0.22, cy - size * 0.04, fill=color, width=stroke, tags=(tag,))
        elif name == "power":
            self.screen.create_arc(cx - size * 0.22, cy - size * 0.16, cx + size * 0.22, cy + size * 0.28, start=215, extent=110, outline=color, width=stroke, style="arc", tags=(tag,))
            self.screen.create_line(cx, cy - size * 0.24, cx, cy + size * 0.04, fill=color, width=stroke, tags=(tag,))
        elif name == "logout":
            self.screen.create_line(cx - size * 0.22, cy - size * 0.18, cx + size * 0.04, cy - size * 0.18, cx + size * 0.04, cy + size * 0.18, cx - size * 0.22, cy + size * 0.18, fill=color, width=stroke, tags=(tag,))
            self.screen.create_line(cx - size * 0.04, cy, cx + size * 0.24, cy, fill=color, width=stroke, tags=(tag,))
            self.screen.create_line(cx + size * 0.12, cy - size * 0.12, cx + size * 0.24, cy, cx + size * 0.12, cy + size * 0.12, fill=color, width=stroke, tags=(tag,))
        else:
            self.screen.create_line(cx - size * 0.18, cy, cx + size * 0.18, cy, fill=color, width=stroke, tags=(tag,))

    def _set_option_fill(self, tag: str, color: str) -> None:
        items = self.screen.find_withtag(tag)
        if items:
            self.screen.itemconfigure(items[0], fill=color)

    def _choose(self, action: str) -> None:
        self.selected_action = action
        self.root.quit()

    def _tick_clock(self) -> None:
        self._draw()
        self.root.after(30_000, self._tick_clock)


def rounded_rectangle(canvas: tk.Canvas, x0: int, y0: int, x1: int, y1: int, radius: int, **kwargs: object) -> None:
    points = (
        x0 + radius, y0,
        x1 - radius, y0,
        x1, y0,
        x1, y0 + radius,
        x1, y1 - radius,
        x1, y1,
        x1 - radius, y1,
        x0 + radius, y1,
        x0, y1,
        x0, y1 - radius,
        x0, y0 + radius,
        x0, y0,
    )
    canvas.create_polygon(points, smooth=True, splinesteps=24, **kwargs)


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


def main() -> int:
    if tk is None or tkfont is None:
        print(
            "Arcadify Shell: Python Tk support is not installed. "
            "On Debian/Ubuntu, install the system package: sudo apt-get install python3-tk",
            file=sys.stderr,
        )
        return 1

    try:
        config = load_config()
        root = tk.Tk()
        app = ArcadifyShell(root, config)
        root.mainloop()
        if app.selected_action:
            print(app.selected_action, flush=True)
        root.destroy()
        return 0
    except Exception as exc:
        print(f"Arcadify Shell: {exc}", file=sys.stderr)
        return 1
