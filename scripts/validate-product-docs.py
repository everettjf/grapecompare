#!/usr/bin/env python3
"""Check install links and compatibility claims across the public product docs."""
from pathlib import Path
import re
from html.parser import HTMLParser

ROOT = Path(__file__).resolve().parents[1]
STORE = 'https://apps.apple.com/us/app/grapecompare/id6796778424?mt=12'
project = (ROOT / 'macos/GrapeCompare.xcodeproj/project.pbxproj').read_text()
assert set(re.findall(r'MACOSX_DEPLOYMENT_TARGET = ([\d.]+);', project)) == {'15.0'}

class Page(HTMLParser):
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        for key in ('href', 'src'):
            url = attrs.get(key, '')
            if url and not re.match(r'(?:[a-z]+:|#|/)', url):
                target = ROOT / 'docs' / url.split('#')[0].split('?')[0]
                assert target.exists(), f'Missing local page asset: {url}'

for relative in ('README.md', 'README.zh-CN.md', 'docs/index.html', 'docs/support.html'):
    text = (ROOT / relative).read_text()
    assert STORE in text, f'{relative}: missing App Store installation link'
    assert 'macOS 15' in text, f'{relative}: missing minimum system'
    assert not re.search(r'macOS 14|brew install|Coming soon|In preparation|Signed &amp; notarized', text), relative
    assert 'difftool/mergetool' in text and ('CLI' in text or 'command-line tool' in text), f'{relative}: missing integration boundaries'
    if relative.endswith('.html'):
        Page().feed(text)
print('Product documentation checks passed: installation, macOS target, scope, local links.')
