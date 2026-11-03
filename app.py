"""Miku Music native desktop launcher and original Rhine service adapter."""
import argparse
import os
from pathlib import Path
import sys

from PySide6.QtCore import QTimer, QUrl, QSettings
from PySide6.QtGui import QGuiApplication, QFont, QFontDatabase, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtWidgets import QApplication
from native_bridge import NativeBridge
from desktop_controller import DesktopController
from skin_theme import SkinTheme


def main():
    source = Path(__file__).resolve().parent
    packaged = getattr(sys, "frozen", False)
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", type=Path, default=Path(sys.executable).parent / "runtime" if packaged else source / "runtime")
    parser.add_argument("--qml", type=Path, default=source / "claude" / "qml" / "Main.qml")
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--exit-after", type=int, default=0)
    parser.add_argument("--size", default="")
    parser.add_argument("--skin", choices=("miku", "teto"))
    args = parser.parse_args()
    if not args.qml.is_file():
        print("Missing qml/Main.qml; please keep the full application folder together.", file=sys.stderr)
        return 2
    # The preview uses native 2D panels and two bounded sprite textures.
    # Avoid the driver and swap-chain allocations of a 3D scene; an explicit
    # QT_QUICK_BACKEND override remains available for troubleshooting.
    os.environ.setdefault("QT_QUICK_BACKEND", "software")
    application = QApplication(sys.argv)
    application.setApplicationName("Miku Teto Music")
    application.setOrganizationName("MikuTetoMusicLocal")
    application.setOrganizationDomain("local.mikuteto.music")
    if sys.platform == "win32":
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("local.mikuteto.music")
    # Only a user-selected final icon is installed here; design drafts stay separate.
    icon_path = source / "assets" / "app-icon.ico"
    if icon_path.is_file():
        application.setWindowIcon(QIcon(str(icon_path)))
    for weight in ("Regular", "Demibold", "Bold"):
        font_id = QFontDatabase.addApplicationFont(str(args.runtime / "resources" / ("MiSans-" + weight + ".ttf")))
        if weight == "Regular" and font_id >= 0:
            application.setFont(QFont(QFontDatabase.applicationFontFamilies(font_id)[0], 10))
    engine = QQmlApplicationEngine()
    context = engine.rootContext()
    args.runtime = args.runtime.resolve()
    (args.runtime / "data").mkdir(parents=True, exist_ok=True)
    appearance = QSettings(str(args.runtime / "data/appearance.ini"), QSettings.IniFormat)
    skin = SkinTheme(source / "assets", initial=args.skin, settings=appearance)
    bridge = NativeBridge(args.runtime, provider="netease" if skin.choice == "teto" else "qq")
    bridge.providerChanged.connect(lambda: skin.select("teto" if bridge.provider == "netease" else "miku"))
    desktop = DesktopController(application, bridge, application.windowIcon())
    context.setContextProperty("backend", bridge)
    context.setContextProperty("desktop", desktop)
    context.setContextProperty("skinTheme", skin)
    context.setContextProperty("mikuSpriteSource", QUrl.fromLocalFile(str(source / "assets/characters/miku-pixel.png")))
    context.setContextProperty("tetoSpriteSource", QUrl.fromLocalFile(str(source / "assets/characters/teto-pixel.png")))
    context.setContextProperty("runtimeFontsFolder", QUrl.fromLocalFile(str(args.runtime.resolve() / "resources") + "/"))
    bridge.quitRequested.connect(application.quit)
    application.aboutToQuit.connect(bridge.shutdown)
    engine.load(QUrl.fromLocalFile(str(args.qml.resolve())))
    if not engine.rootObjects():
        return 1
    window = engine.rootObjects()[0]
    desktop.bind(window)
    if args.size:
        width, height = map(int, args.size.split("x"))
        window.setWidth(width)
        window.setHeight(height)
    if args.capture:
        def capture():
            args.capture.parent.mkdir(parents=True, exist_ok=True)
            window.grabWindow().save(str(args.capture))
        QTimer.singleShot(2500, capture)
    if args.exit_after:
        QTimer.singleShot(args.exit_after, application.quit)
    QTimer.singleShot(0, bridge.start)
    return application.exec()


if __name__ == "__main__":
    sys.exit(main())
