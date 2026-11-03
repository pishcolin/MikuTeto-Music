"""Prepare a new clean runtime; never copy account, cache, queue or favorites data."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,sys
import pefile,PySide6

p=argparse.ArgumentParser()
p.add_argument('--qt-root',type=Path,required=True)
p.add_argument('--native-exe',type=Path,required=True)
p.add_argument('--node-exe',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--fonts',type=Path)
a=p.parse_args();root=Path(__file__).resolve().parents[1]
assert not a.output.exists(),'Use a fresh runtime destination'
a.output.mkdir(parents=True)
shutil.copy2(a.native_exe,a.output/'RhinePlaybackService.exe')
queue=[a.output/'RhinePlaybackService.exe']
for folder in ('platforms','multimedia','tls','networkinformation','imageformats'):
    source=a.qt_root/'plugins'/folder
    if not source.is_dir():continue
    for dll in source.glob('*.dll'):
        if dll.stem.endswith('d') or dll.name.lower()=='qpdf.dll':continue
        dest=a.output/folder/dll.name;dest.parent.mkdir(exist_ok=True);shutil.copy2(dll,dest);queue.append(dest)
known={f.name.lower():f for folder in (Path(PySide6.__file__).parent,Path(sys.base_prefix),a.qt_root/'bin') for f in folder.glob('*.dll')}
seen=set()
while queue:
    file=queue.pop()
    if file in seen:continue
    seen.add(file)
    with pefile.PE(str(file),fast_load=True) as pe:
        pe.parse_data_directories(directories=[1,13])
        names=[entry.dll.decode('ascii').lower() for table in ('DIRECTORY_ENTRY_IMPORT','DIRECTORY_ENTRY_DELAY_IMPORT') for entry in getattr(pe,table,[])]
    for name in names:
        if name in known and not (a.output/known[name].name).exists():
            dest=a.output/known[name].name;shutil.copy2(known[name],dest);queue.append(dest)
        elif name.startswith(('qt6','avcodec','avformat','avutil','swresample','swscale')):
            assert (a.output/name).exists(),'Missing runtime dependency: '+name
(a.output/'qt.conf').write_text('[Paths]\nPlugins=.\n',encoding='utf-8')
resources=a.output/'resources';bridge=resources/'MusicBridge';bridge.mkdir(parents=True)
for name in ('worker-dual.cjs','xhr-sync-worker.js'):
    shutil.copy2(root/'native'/name,bridge/('worker.cjs' if name=='worker-dual.cjs' else name))
shutil.copy2(a.node_exe,bridge/'node.exe')
shutil.copytree(root/'vendor/rhine/MusicBridge/upstream',bridge/'upstream')
shutil.copy2(root/'licenses/Node.js-LICENSE.txt',bridge/'NODE-LICENSE')
shutil.copy2(root/'licenses/LyricsKit-MPL-2.0.txt',bridge/'LyricsKit-LICENSE')
shutil.copy2(root/'vendor/rhine/MusicBridge/lyrics-source.json',bridge/'lyrics-source.json')
fonts=a.fonts or root/'build/fonts'
if not all((fonts/name).exists() for name in ('MiSans-Regular.ttf','MiSans-Demibold.ttf','MiSans-Bold.ttf')):
    subprocess.run([sys.executable,str(root/'scripts/fetch-fonts.py'),str(fonts)],check=True)
font_hashes=json.loads((root/'licenses/font-source.json').read_text(encoding='utf-8'))['files']
for name,digest in font_hashes.items():
    assert hashlib.sha256((fonts/name).read_bytes()).hexdigest()==digest
    shutil.copy2(fonts/name,resources/name)
shutil.copy2(root/'licenses/MiSans-license.pdf',resources/'MiSans-license.pdf')
for name in ('NotoSansSymbols2-Regular.ttf','NotoSansSymbols2-OFL.txt'):
    shutil.copy2(root/'assets/fonts'/name,resources/name)
print('Clean runtime created:',a.output)
