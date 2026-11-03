"""Reactive MIKU/TETO palettes; browsing theme never controls playback."""
from pathlib import Path

from PySide6.QtCore import QObject, Property, QSettings, QUrl, Signal, Slot


MIKU = {
    "mint": "#39c5bb", "mintDim": "#1f6f6c", "bar": "#176e78",
    "barHover": "#1f8691", "pane": "#031c22", "raised": "#06262d",
    "hover": "#0a333b", "select": "#0e414a", "rule": "#0f3b43",
    "ink": "#e7f6f4", "inkDim": "#8ab7b4", "inkFaint": "#4e7f7e",
    "alert": "#ff6474", "alertBar": "#8e2a3a", "trial": "#f2e48a",
    "paper": "#ffffff", "veil": "#99031c22", "barTextDim": "#bfe9e5",
    "primaryHover": "#86e3dc", "modalVeil": "#b3031c22", "qrScanVeil": "#cc031c22",
}

# Warm red companion theme, with shared semantic color roles.
TETO = {
    "mint": "#f11c30", "mintDim": "#63131a", "bar": "#941e26",
    "barHover": "#ad2a34", "pane": "#1e0000", "raised": "#2c0809",
    "hover": "#3a1013", "select": "#4b141a", "rule": "#461319",
    "ink": "#fbedee", "inkDim": "#bda9a9", "inkFaint": "#8e7f7f",
    "alert": "#ffb347", "alertBar": "#8a4a12", "trial": "#9ee3e6",
    "paper": "#ffffff", "veil": "#991e0000", "barTextDim": "#f1c2c6",
    "primaryHover": "#ff7784", "modalVeil": "#b31e0000", "qrScanVeil": "#cc1e0000",
}


class SkinTheme(QObject):
    changed = Signal()

    def __init__(self, assets: Path, parent=None, *, settings=None, initial=None):
        super().__init__(parent)
        self._assets = assets
        self._settings = settings if settings is not None else QSettings()
        saved = str(initial or self._settings.value("appearance/skin", "miku"))
        self._choice = saved if saved in ("miku", "teto") else "miku"

    @Property(str, notify=changed)
    def choice(self):
        return self._choice

    @Property("QVariantMap", notify=changed)
    def palette(self):
        return dict(TETO if self._choice == "teto" else MIKU)

    @Property(QUrl, notify=changed)
    def character(self):
        return QUrl.fromLocalFile(str(self._assets / "characters" / f"{self._choice}-pixel.png"))

    @Slot(str)
    def select(self, choice):
        if choice not in ("miku", "teto") or choice == self._choice:
            return
        self._choice = choice
        self._settings.setValue("appearance/skin", choice)
        self.changed.emit()
