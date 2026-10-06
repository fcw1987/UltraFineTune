#!/usr/bin/env python3
"""Check local website links and accidental private evidence; standard library only."""
from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit, unquote
root = Path(__file__).resolve().parent.parent
class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []; self.ids = set()
    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if 'id' in d: self.ids.add(d['id'])
        for key in ('href', 'src'):
            if key in d: self.links.append(d[key])
errors = []
for file in (root / 'docs').glob('*.html'):
    parser = Links(); parser.feed(file.read_text())
    for link in parser.links:
        url = urlsplit(link)
        if url.scheme or url.netloc: continue
        target = file.parent / unquote(url.path) if url.path else file
        if not target.is_file(): errors.append(f'{file.name}: missing {link}')
        if url.fragment and target == file and url.fragment not in parser.ids:
            errors.append(f'{file.name}: missing anchor {link}')
files = subprocess.check_output(['git', 'ls-files'], cwd=root, text=True).splitlines()
patterns = [r'/Users/' + r'[A-Za-z0-9]', r'AppleUSB' + r'AudioEngine:', r'gh' + r'[opusr]_[A-Za-z0-9]{20,}', r'-----BEGIN ' + r'(?:RSA |EC |OPENSSH )?PRIVATE KEY-----']
for name in files:
    path = root / name
    if not path.exists(): continue
    try: text = path.read_text()
    except UnicodeDecodeError: continue
    if any(re.search(pattern, text) for pattern in patterns): errors.append(f'{name}: private evidence pattern')
if errors: raise SystemExit('\n'.join(errors))
print('Public source patterns and local HTML links passed')
