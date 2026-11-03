"""Restore the complete component notice tree retained as a source-repo archive."""
from pathlib import Path
from zipfile import ZipFile
root=Path(__file__).resolve().parents[1]/'licenses'
archive=root/'component-notices.zip'
if archive.exists():
    with ZipFile(archive) as z:
        for member in z.infolist():
            if member.is_dir():continue
            target=(root/member.filename).resolve()
            if not target.is_relative_to(root.resolve()):raise ValueError('Unsafe notice path')
            content=z.read(member)
            if target.exists():
                if target.read_bytes()!=content:raise ValueError('Existing notice differs: '+member.filename)
            else:
                target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
    print('Component notices restored without modifying existing files.')
