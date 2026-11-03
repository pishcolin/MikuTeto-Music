# Building and modifying the Windows edition

## Tools

Use a Windows 10/11 x64 machine with Python 3.12, Node.js 22 or later with npm,
Visual Studio 2022 C++ x64 build tools and Windows SDK, CMake, and the official
Qt 6.12.0 MSVC 2022 x64 SDK (Core, GUI, Network, Multimedia). Use the **x64
Native Tools Command Prompt** and run PowerShell from it. Install only tools
from their official vendors. Tested Python packages are pinned in
`requirements-build.txt`; Node dependencies are pinned in both lockfiles.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-build.txt
powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1 `
  -QtRoot 'C:\Qt\6.12.0\msvc2022_64' `
  -PythonExe '.\.venv\Scripts\python.exe'
```

Use a fresh checkout/output folder for each packaged build. The packaging
script deliberately refuses an existing final output. It runs npm with
dependency lifecycle scripts disabled, rebuilds the dual-platform bridge,
builds the native playback service, packages the desktop application, and
collects only a clean runtime. It never imports an installed user's profile.
`scripts/fetch-fonts.py` downloads the official MiSans archive and verifies its
SHA-256 and each original font file. No conversion or font modification occurs.
Network access is needed for package/font downloads on a fresh machine.

The repository stores the large component-notice tree in
`licenses/component-notices.zip`. The build restores it automatically with
`scripts/unpack-notices.py`; it can also be extracted manually for inspection.

The result is `dist/MikuTetoMusic/MikuTetoMusic.exe`. Keep the whole folder,
including `_internal`, `runtime`, `licenses` and the notices, together.
The packaged UI uses PySide6's Qt DLLs under `_internal/PySide6`; the separate
native service uses its own compatible Qt DLLs under `runtime`.

## Corresponding source and replacing LGPL components

The release's `MikuTeto-Music-1.1.0-ThirdPartySources.zip` contains the exact
downloaded Qt 6.12.0 module sources, PySide/Shiboken 6.12.0 sources, FFmpeg
9.0.1 and zlib 1.3.1 sources, plus installed Node dependency source files and
the bridge build inputs. Archive URLs/hashes and actual runtime versions are
recorded under `licenses`. Original Qt/PySide/FFmpeg license directories and
third-party attribution files are preserved. No modifications to these
upstream C/C++ library sources were made for this release.

Build modified Qt libraries with the upstream CMake instructions in the
supplied module sources, MSVC 2022 x64, shared Release configuration and the
same Qt version/ABI. Build PySide/Shiboken against that compatible Qt using
the instructions in the supplied pyside-setup source. Build FFmpeg with its
included `configure`/make instructions; the vendor configuration is in
`licenses/runtime-versions.json`, using zlib 1.3.1 and shared MSVC libraries,
without `--enable-gpl` or `--enable-nonfree`.

After closing the application, back up its folder, then substitute your
compatible DLLs/plugins in `_internal/PySide6` and/or `runtime` as appropriate.
Preserve filenames, architecture and the Qt plugin directory structure.
There are no application signature checks preventing replacement. You may
also rebuild the whole application with your modified libraries. Python
bindings and native plugins must match the replacement Qt ABI.

To modify a bundled Node dependency, use the provided package sources under
`vendor/rhine/MusicBridge/node_modules` (or reconstruct from its lockfile),
then run `node scripts/build-bridge.cjs`. Copy the resulting
`native/worker-dual.cjs` to `runtime/resources/MusicBridge/worker.cjs` and keep
`xhr-sync-worker.js` beside it. `scripts/adapt-dual-worker.cjs` contains this
player's source routing and adapters. Source distribution includes the
MPL-covered `lyrics-format.cjs` and provenance; modifications to that covered
file remain subject to MPL-2.0. Consult the supplied LGPL text when conveying
modified LGPL dependencies.

## Validation and local data

Python tests are in `tests`; run `python -m unittest discover -s tests`.
The native CMake build with `-DMIKU_PLAYBACK_CHECKS=ON` produces
`MikuMixedQueueChecks.exe` and `MikuRadioChecks.exe`; run them with the Qt runtime DLLs on PATH and pass
the path to a one-second silent WAV file as its first argument. For example:

```powershell
python -c "import wave; w=wave.open('silence.wav','wb'); w.setparams((1,2,44100,0,'NONE','')); w.writeframes(bytes(88200)); w.close()"
$env:PATH = 'C:\Qt\6.12.0\msvc2022_64\bin;' + $env:PATH
.\build\native\MikuMixedQueueChecks.exe silence.wav
.\build\native\MikuRadioChecks.exe silence.wav
```

The radio checks use an offline service fixture and silent audio. They cover
both providers, automatic refill, recent-track deduplication, bounded buffering,
manual queue priority, pause during loading, late callbacks, account changes,
failure/retry handling and natural track endings. No real account is needed.

The source UI can also run with `python app.py --runtime <clean-runtime-path>`.

The application creates account state, queue history, settings, caches and
SQLite data in its local runtime profile on first use. These files are not
release inputs. Do not upload your working `runtime/data` folder, credentials,
cookie files, personal DB or caches when contributing a bug report or build.
The application currently has no publisher signing certificate and no
automatic self-updater; releases are downloaded manually from GitHub.
