"""Native tray lifecycle for the QML player, independent of its visual design."""
from PySide6.QtCore import QObject, QTimer, Slot
from PySide6.QtGui import QIcon, QWindow
from PySide6.QtWidgets import QApplication, QMenu, QStyle, QSystemTrayIcon, QMessageBox


class DesktopController(QObject):
    def __init__(self, application, bridge, icon: QIcon, parent=None):
        super().__init__(parent)
        self._application = application
        self._bridge = bridge
        self._window = None
        self._tray = QSystemTrayIcon(self)
        self._tray.setIcon(icon if not icon.isNull() else QApplication.style().standardIcon(QStyle.SP_MediaPlay))
        self._tray.setToolTip(application.applicationName())
        self._menu = QMenu()
        show = self._menu.addAction("打开播放器")
        show.triggered.connect(self.showWindow)
        self._menu.addSeparator()
        self._toggle = self._menu.addAction("播放 / 暂停")
        self._toggle.triggered.connect(lambda: bridge.control("player.toggle", {}))
        previous = self._menu.addAction("上一首")
        previous.triggered.connect(lambda: bridge.control("player.next", {"direction": -1}))
        following = self._menu.addAction("下一首")
        following.triggered.connect(lambda: bridge.control("player.next", {"direction": 1}))
        self._controls = [self._toggle, previous, following]
        self._menu.addSeparator()
        notices = self._menu.addAction("关于与开源许可")
        notices.triggered.connect(self.showLicenses)
        quit_action = self._menu.addAction("退出播放器")
        quit_action.triggered.connect(application.quit)
        self._tray.setContextMenu(self._menu)
        self._tray.activated.connect(self._activated)
        bridge.preferencesChanged.connect(self._update)
        bridge.connectedChanged.connect(self._update)
        bridge.snapshotChanged.connect(self._update)
        application.aboutToQuit.connect(self._tray.hide)
        application.setQuitOnLastWindowClosed(False)

    def bind(self, window):
        self._window = window
        self._update()

    def _activated(self, reason):
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick):
            self.showWindow()

    @Slot()
    def showWindow(self):
        if self._window is None:
            return
        if self._window.visibility() == QWindow.Minimized:
            self._window.showNormal()
        else:
            self._window.show()
        self._window.raise_()
        self._window.requestActivate()

    @Slot()
    def showLicenses(self):
        QMessageBox.about(None, "Miku Teto Music · 开源许可",
            '<b>Miku Teto Music 1.0.0</b><br>程序代码：MIT · pishcolin<br>'
            '基于 <a href="https://github.com/MikeQu223/Rhine-Music-Database">Rhine Music Database</a>'
            '（LBEILC，MIT）。<br><br>'
            '本软件使用 MiSans 字体（小米科技），字体保留原始协议。<br>'
            'Qt / PySide6：LGPL-3.0；FFmpeg：LGPL-2.1-or-later。<br>'
            '完整依赖署名、协议及源码获取方式见随包 THIRD_PARTY_NOTICES.md 与 licenses。<br><br>'
            '初音未来：Crypton Future Media, INC.；本同人作品按 '
            '<a href="https://piapro.jp/license/pcl">PCL</a> 使用该角色。<br>'
            '重音テト：線・小山乃舞世 / ツインドリル；按 '
            '<a href="https://kasaneteto.jp/guideline/character.html">角色使用规则</a>使用。<br>'
            '角色素材不属于 MIT，非官方免费同人项目，不含声音库或音乐作品。')

    @Slot(result=bool)
    def closeWindow(self):
        """Return false to dismiss a close event while retaining the service."""
        if self._bridge.preferences.get("close-behavior") == "tray" and QSystemTrayIcon.isSystemTrayAvailable():
            self._tray.show()
            if self._window is not None:
                self._window.hide()
            return False
        # Explicit exit, or no tray available: do not leave an invisible process.
        QTimer.singleShot(0, self._application.quit)
        return True

    def _update(self):
        snapshot = self._bridge.snapshot
        title = str((snapshot.get("current") or {}).get("title", ""))
        name = self._application.applicationName()
        self._tray.setToolTip((title + " - " + name)[:127] if title else name)
        enabled = self._bridge.connected and bool(snapshot.get("queue") or snapshot.get("current"))
        for action in self._controls:
            action.setEnabled(enabled)
        self._toggle.setText("暂停" if snapshot.get("state", {}).get("playing") else "播放")
        if QSystemTrayIcon.isSystemTrayAvailable():
            hidden = self._window is not None and not self._window.isVisible()
            self._tray.setVisible(hidden or self._bridge.preferences.get("close-behavior") == "tray")
