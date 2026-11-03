# Third-party notices

Miku Teto Music's original code is MIT licensed, © 2026 pishcolin. This grant
does not replace the licenses of the components below or the separate character
and font conditions in [ASSET-NOTICE.txt](ASSET-NOTICE.txt).

## Upstream application

Based on [MikeQu223/Rhine-Music-Database](https://github.com/MikeQu223/Rhine-Music-Database),
commit `15139d4b3562edcf3d9b24b50ca502bd42f784d7`, MIT, © 2026 LBEILC.
The complete upstream grant is retained in [LICENSE-Rhine.txt](LICENSE-Rhine.txt).
Credit also goes to [LBEILC/RhineLabUI](https://github.com/LBEILC/RhineLabUI),
the upstream application's UI foundation. See [provenance](docs/UPSTREAM.md).

## Runtime and source components

| Component | Version / scope | License and retained material |
| --- | --- | --- |
| Qt | 6.12.0; Core, GUI, Network, QML/Quick/Controls, SVG, image formats, multimedia, shader tools | LGPL-3.0 option for the distributed library modules; third-party subcomponents retain their own licenses. `licenses/runtime/`, accompanying exact source archives. |
| PySide6 / Shiboken6 | 6.12.0 | LGPL-3.0; `licenses/runtime/pyside-setup/` and PySide source archive. |
| FFmpeg | 9.0.1 shared libraries used by Qt Multimedia | LGPL-2.1-or-later build, without GPL/nonfree configure flags; `licenses/runtime/ffmpeg/`, source and configuration below. |
| Python | 3.12.14 | PSF and incorporated third-party notices; `licenses/Python-LICENSE.txt`. |
| Node.js | Exact shipped runtime version in `licenses/runtime-versions.json` | Node.js MIT and incorporated notices in `licenses/Node.js-LICENSE.txt`. |
| PyInstaller | 6.22.0 bootloader | GPL with distribution exception; `licenses/python-packages/`. Does not change the application license. |
| QQ Music API | `@yakult-green-tea/qq-music-api` 3.3.1; based on Rain120/QQMusicApi | MIT; npm notices and source below. |
| NeteaseCloudMusicApiEnhanced | `@neteasecloudmusicapienhanced/api` 4.41.1, continuing Binaryify/NeteaseCloudMusicApi | MIT; npm notices and source below. |
| YesPlayMusic | Adapted NetEase login/account/user functions, upstream pinned metadata in `vendor/rhine/MusicBridge/upstream/` | MIT; `licenses/YesPlayMusic-LICENSE.txt`. |
| LyricsKit | Adapted JavaScript lyric parser, `vendor/rhine/MusicBridge/lyrics-format.cjs` | MPL-2.0; `licenses/LyricsKit-MPL-2.0.txt`. This covered source and its upstream provenance are supplied. |
| @unblockneteasemusic/server | 0.28.0, dependency present inside the NetEase API bundle | LGPL-3.0; full package, license and rebuildable bridge sources accompany the release. Its presence does not imply an application feature that bypasses platform permissions. |
| qrcodegen | Nayuki QR code generator, source in `native/playback/` | MIT; `licenses/qrcodegen-LICENSE.hpp`. |
| utfcpp | Header dependency, source in `native/playback/` | Boost Software License 1.0; `licenses/utfcpp-LICENSE.txt`. |
| MiSans | Unmodified official Regular, Demibold, Bold TTFs | Separate MiSans license; `licenses/MiSans-license.pdf`, exact archive and font checksums in `licenses/font-source.json`. |
| Noto Sans Symbols 2 | Bundled font | SIL OFL-1.1; `assets/fonts/NotoSansSymbols2-OFL.txt`. |

The full locked Node dependency inventory is [licenses/NPM-INDEX.md](licenses/NPM-INDEX.md)
and [licenses/npm-packages.json](licenses/npm-packages.json). Each package's
provided license/notices are in `licenses/npm/`. Some upstream tarballs omit a
standalone license: their original package metadata, retrieved upstream notices
or clearly labelled supplements are preserved rather than inventing copyright
owners or claiming all dependencies are MIT. For node-forge's dual licensing,
this distribution uses its BSD-3-Clause option.

In the Git repository, the full `npm/`, `runtime/` and `python-packages/`
notice trees are stored losslessly in `licenses/component-notices.zip`.
`python scripts/unpack-notices.py` restores them; the Windows build runs this
automatically. Windows releases and the full source archive include the
expanded notices. The archive does not change or replace any license text.

The upstream bridge source tree also contains providers not exposed in this
two-platform player (for example KuGou). Their source/dependency notices remain
in the inventory. No source attribution is removed merely because a UI route
is disabled.

## Replacing libraries and obtaining corresponding source

The Windows archive uses dynamically linked Qt/PySide/FFmpeg libraries; it is
not a statically linked or sealed runtime. The release's
`MikuTeto-Music-1.0.0-ThirdPartySources.zip` supplies the matching Qt module,
PySide, FFmpeg and zlib source snapshots plus the exact installed Node package
sources, original bridge modules and adaptation/build scripts. Download it
from the same [release page](https://github.com/pishcolin/MikuTeto-Music/releases/tag/v1.0.0).
Source URLs and SHA-256 hashes are in `licenses/source-downloads.json`.
Build and replacement instructions are in [docs/BUILDING.md](docs/BUILDING.md).
No separate restriction is imposed on debugging modifications to LGPL-covered
libraries, reverse engineering for that purpose, or substituting compatible
modified libraries. Keep applicable notices and comply with each license when
redistributing modified binaries.

## FFmpeg build

The shipped FFmpeg DLLs report `LGPL version 2.1 or later`. They are the Qt
runtime's prebuilt shared libraries, not a locally modified FFmpeg build.
Their reported configuration is recorded in `licenses/runtime-versions.json`.
Matching FFmpeg 9.0.1 and zlib 1.3.1 sources are provided. The project does not
claim byte-identical reproducible vendor binaries; platform SDK, compiler and
vendor packaging can affect the output.

## Characters, music services and names

See [ASSET-NOTICE.txt](ASSET-NOTICE.txt) for Hatsune Miku and Kasane Teto rights,
AI-assisted asset provenance and noncommercial fan-use context. QQ Music and
NetEase Cloud Music are third-party services, not affiliated with this project.
Playback availability remains determined by their accounts, regions and rights.
