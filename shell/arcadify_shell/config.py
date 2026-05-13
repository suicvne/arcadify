from __future__ import annotations

from configparser import ConfigParser
from dataclasses import dataclass
from pathlib import Path
import os


DEFAULT_CONFIG_PATHS = (
    "/etc/Arcadify/Shell.ini",
    "Shell.ini",
)


@dataclass(frozen=True)
class WindowConfig:
    title: str
    heading: str
    subheading: str
    fullscreen: bool
    show_clock: bool


@dataclass(frozen=True)
class BackgroundConfig:
    color: str
    image: str
    image_mode: str
    overlay: str
    overlay_alpha: float


@dataclass(frozen=True)
class ThemeConfig:
    panel: str
    panel_alpha: float
    text: str
    muted: str
    primary: str
    primary_text: str
    utility: str
    utility_text: str
    focus: str


@dataclass(frozen=True)
class OptionConfig:
    action: str
    label: str
    description: str
    icon: str
    kind: str
    accent: str


@dataclass(frozen=True)
class AppConfig:
    path: Path
    window: WindowConfig
    background: BackgroundConfig
    theme: ThemeConfig
    options: tuple[OptionConfig, ...]


def load_config() -> AppConfig:
    parser = ConfigParser()
    config_path = _find_config_path()

    if not parser.read(config_path):
        raise RuntimeError(f"could not read config file: {config_path}")

    window = WindowConfig(
        title=parser.get("window", "title", fallback="Arcadify maintenance"),
        heading=parser.get("window", "heading", fallback="Maintenance Mode"),
        subheading=parser.get("window", "subheading", fallback="Choose what to do next."),
        fullscreen=parser.getboolean("window", "fullscreen", fallback=True),
        show_clock=parser.getboolean("window", "show_clock", fallback=True),
    )
    background = BackgroundConfig(
        color=parser.get("background", "color", fallback="#0f172a"),
        image=parser.get("background", "image", fallback="").strip(),
        image_mode=parser.get("background", "image_mode", fallback="cover").lower(),
        overlay=parser.get("background", "overlay", fallback="#07111f"),
        overlay_alpha=_bounded_float(parser.getfloat("background", "overlay_alpha", fallback=0.62), 0.0, 1.0),
    )
    theme = ThemeConfig(
        panel=parser.get("theme", "panel", fallback="#111827"),
        panel_alpha=_bounded_float(parser.getfloat("theme", "panel_alpha", fallback=0.84), 0.0, 1.0),
        text=parser.get("theme", "text", fallback="#f8fafc"),
        muted=parser.get("theme", "muted", fallback="#cbd5e1"),
        primary=parser.get("theme", "primary", fallback="#38bdf8"),
        primary_text=parser.get("theme", "primary_text", fallback="#031018"),
        utility=parser.get("theme", "utility", fallback="#1f2937"),
        utility_text=parser.get("theme", "utility_text", fallback="#f8fafc"),
        focus=parser.get("theme", "focus", fallback="#fbbf24"),
    )
    options = []
    for section in parser.sections():
        if not section.startswith("option."):
            continue

        action = section.removeprefix("option.").strip()
        if not action:
            continue

        options.append(
            OptionConfig(
                action=action,
                label=parser.get(section, "label", fallback=action.replace("_", " ").title()),
                description=parser.get(section, "description", fallback=""),
                icon=parser.get(section, "icon", fallback="spark"),
                kind=parser.get(section, "kind", fallback="primary").lower(),
                accent=parser.get(section, "accent", fallback=theme.primary),
            )
        )

    if not options:
        raise RuntimeError(f"no [option.*] sections were found in {config_path}")

    return AppConfig(
        path=config_path,
        window=window,
        background=background,
        theme=theme,
        options=tuple(options),
    )


def _find_config_path() -> Path:
    candidates = []
    env_path = os.environ.get("ARCADIFY_SHELL_CONFIG", "").strip()
    if env_path:
        candidates.append(env_path)
    candidates.extend(DEFAULT_CONFIG_PATHS)

    package_default = Path(__file__).resolve().parents[1] / "Shell.ini"
    candidates.append(str(package_default))

    for candidate in candidates:
        path = Path(candidate).expanduser()
        if path.is_file():
            return path

    return package_default


def _bounded_float(value: float, minimum: float, maximum: float) -> float:
    return min(max(value, minimum), maximum)
