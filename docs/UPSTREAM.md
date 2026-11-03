# Upstream provenance and changes

The native service and music-service bridge derive from
[MikeQu223/Rhine-Music-Database](https://github.com/MikeQu223/Rhine-Music-Database),
commit [`15139d4b3562edcf3d9b24b50ca502bd42f784d7`](https://github.com/MikeQu223/Rhine-Music-Database/tree/15139d4b3562edcf3d9b24b50ca502bd42f784d7).
Upstream copyright: © 2026 LBEILC, MIT. Its original license is retained in
`LICENSE-Rhine.txt` and `vendor/rhine/LICENSE`. Upstream credits
[RhineLabUI](https://github.com/LBEILC/RhineLabUI), which we acknowledge here;
the original scene/UI asset archive is not distributed in this project.

`vendor/rhine/source.json` records the pinned input files. The original
`vendor/rhine/MusicBridge` modules, lockfile, bundled upstream notices and bridge
builder are retained. Our build creates an adapted builder in a fresh build
folder without overwriting the original inputs. Covered LyricsKit sources
remain readable in that tree; Node package sources are also shipped with the
release's ThirdPartySources archive.

The application replaces the original full UI with a Python/PySide6 QML shell
and an IPC-controlled C++ playback service. Changes include source-aware mixed
queues, independent SQLite favorites and playlists, per-account like imports,
explicit like/unlike synchronization with persistent pending operations,
account-generation guards, browsing-state preservation, queue batching,
reconnection/recovery, lightweight visibility-aware animation, and two themes.
The dual-platform bridge is produced by `scripts/build-bridge.cjs` and
`scripts/adapt-dual-worker.cjs`, including `native/favorites-sync.cjs` and
`native/netease-features.cjs`.

The continuous-radio update adds a service-owned `RadioController`, QML radio
controls and a NetEase private-FM adapter. The vendored `MusicBridge/worker.cjs`
route table and generated `netease-endpoints.cjs` include `personal_fm` for that
adapter. These are local changes on top of the pinned inputs recorded above;
the upstream licenses and copyright notices remain intact.

Claude assisted with the QML visual design, abstract app icon and README.
Codex assisted with integration, logic, validation and release preparation.
These descriptions do not alter third-party ownership or license conditions.
The public edition's character sprites are AI-assisted fan assets, governed
separately as described in `ASSET-NOTICE.txt`. Personal-edition Kieed artwork,
reference images, private playback history and account files are not included.
