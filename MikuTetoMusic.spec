# Native Windows package. Keep the original Rhine runtime beside the executable.
from pathlib import Path
from PyInstaller.utils.hooks.qt import pyside6_library_info

source = Path(SPECPATH)
player_data = [(str(p), str(p.parent.relative_to(source))) for p in (source / "assets").rglob("*") if p.is_file()]
player_data += [(str(p), "claude/qml") for p in (source / "claude/qml").iterdir()
                if p.suffix in {".qml", ".js"} and p.name != "Pane.qml"]
original_collect_qml = pyside6_library_info.collect_qtqml_files

def collect_player_qml():
    binaries, datas = original_collect_qml()
    allowed = (
        "QtCore", "QtQml", "QtQuick/Controls", "QtQuick/Templates", "QtQuick/Layouts",
        "QtQuick/Shapes", "QtQuick/Effects", "QtQuick/Window", "Qt/labs/settings",
    )
    def needed(item):
        dest = str(item[1]).replace("\\", "/").split("/qml/", 1)[-1]
        if any(x in dest for x in ("StateMachine", "VirtualKeyboard", "DesignHelpers")): return False
        return dest == "QtQuick" or any(dest == p or dest.startswith(p + "/") for p in allowed)
    return [v for v in binaries if needed(v)], [v for v in datas if needed(v)]

pyside6_library_info.collect_qtqml_files = collect_player_qml

a = Analysis(
    [str(source / "app.py")],
    pathex=[str(source)],
    binaries=[],
    datas=player_data,
    hiddenimports=["PySide6.QtQuickControls2"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["PySide6.QtWebEngineCore", "PySide6.QtWebEngineQuick", "PySide6.QtWebEngineWidgets", "PySide6.QtPdf", "PySide6.QtPdfWidgets"],
    noarchive=False,
)
# Qt 6.12 uses the Windows ICU API. A Poppler directory on the build machine's
# PATH contains an incompatible DLL with the same name (version-suffixed exports).
# Let the Windows loader resolve the supported system ICU instead of that DLL.
a.binaries = [entry for entry in a.binaries if Path(entry[0]).name.lower() not in {"icuuc.dll", "icudt78.dll", "qt6pdf.dll", "qpdf.dll", "qt6virtualkeyboard.dll", "qt6statemachine.dll", "qt6statemachineqml.dll", "qt6quick3dutils.dll", "qt6quickshapesdesignhelpers.dll", "qtvirtualkeyboardplugin.dll", "qmldbg_quick3dprofiler.dll"}]
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name="MikuTetoMusic", debug=False,
          bootloader_ignore_signals=False, strip=False, upx=False, console=False,
          disable_windowed_traceback=False,
          icon=str(source / "assets/app-icon.ico"))
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name="MikuTetoMusic")
