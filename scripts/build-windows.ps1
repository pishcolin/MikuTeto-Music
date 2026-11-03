param(
    [Parameter(Mandatory=$true)][string]$QtRoot,
    [string]$NodeExe = (Get-Command node.exe -ErrorAction Stop).Source,
    [string]$PythonExe = 'python'
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $ProjectRoot
try {
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) { throw 'Run in an x64 Native Tools Command Prompt for Visual Studio 2022.' }
    if (Test-Path -LiteralPath 'dist/MikuTetoMusic') { throw 'Choose a fresh build directory; existing files are retained.' }
    & $PythonExe -m pip install -r requirements-build.txt
    if ($LASTEXITCODE) { throw 'Python dependency installation failed' }
    & $PythonExe scripts/unpack-notices.py
    if ($LASTEXITCODE) { throw 'License notice extraction failed' }
    npm ci --ignore-scripts --no-audit --no-fund
    if ($LASTEXITCODE) { throw 'Build dependency installation failed' }
    Push-Location vendor/rhine/MusicBridge
    try { npm ci --ignore-scripts --no-audit --no-fund; if ($LASTEXITCODE) { throw 'Bridge dependency installation failed' } } finally { Pop-Location }
    & $NodeExe scripts/build-bridge.cjs
    if ($LASTEXITCODE) { throw 'Bridge build failed' }
    cmake -S native/playback -B build/native -G 'NMake Makefiles' -DCMAKE_BUILD_TYPE=Release "-DCMAKE_PREFIX_PATH=$QtRoot" -DMIKU_PLAYBACK_CHECKS=ON
    if ($LASTEXITCODE) { throw 'Native configuration failed' }
    cmake --build build/native
    if ($LASTEXITCODE) { throw 'Native build failed' }
    & $PythonExe -m PyInstaller MikuTetoMusic.spec --distpath dist --workpath build/python
    if ($LASTEXITCODE) { throw 'Desktop build failed' }
    & $PythonExe scripts/prepare-runtime.py --qt-root $QtRoot --native-exe build/native/RhinePlaybackService.exe --node-exe $NodeExe --output dist/MikuTetoMusic/runtime
    if ($LASTEXITCODE) { throw 'Runtime preparation failed' }
    foreach ($Name in @('README.md','LICENSE','LICENSE-Rhine.txt','THIRD_PARTY_NOTICES.md','ASSET-NOTICE.txt')) { Copy-Item -LiteralPath $Name -Destination dist/MikuTetoMusic }
    Copy-Item -LiteralPath licenses -Destination dist/MikuTetoMusic -Recurse
} finally { Pop-Location }
