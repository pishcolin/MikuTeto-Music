"""Fetch original MiSans files without converting or modifying the font software."""
from pathlib import Path
import hashlib,json,urllib.request,zipfile,sys

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'licenses/font-source.json').read_text(encoding='utf-8'))
target=Path(sys.argv[1]) if len(sys.argv)>1 else root/'build/fonts'
target.mkdir(parents=True,exist_ok=True)
archive=target/'MiSans.zip'
if not archive.exists():
    with urllib.request.urlopen(manifest['url'],timeout=60) as response,archive.open('xb') as output:
        while block:=response.read(1024*1024):output.write(block)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==manifest['sha256'],'Font archive changed'
with zipfile.ZipFile(archive) as package:
    for name,digest in manifest['files'].items():
        matches=[n for n in package.namelist() if Path(n).name==name]
        assert len(matches)==1,name
        data=package.read(matches[0]);assert hashlib.sha256(data).hexdigest()==digest
        (target/name).write_bytes(data)
print('Original licensed fonts ready:',target)
