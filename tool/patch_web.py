"""يظبط ملفات الويب اللي بيولدها flutter create: الاسم، الأيقونة، الألوان."""
import json, pathlib
from PIL import Image

web = pathlib.Path('web')
idx = web / 'index.html'
s = idx.read_text()
s = s.replace('<title>gamila</title>', '<title>كلك جميلة</title>')
s = s.replace('content="A new Flutter project."', 'content="كلك جميلة - المبيعات والتحصيلات"')
s = s.replace('<html>', '<html lang="ar" dir="rtl">')
s = s.replace('content="gamila"', 'content="كلك جميلة"')
if 'theme-color' not in s:
    s = s.replace('<head>', '<head>\n  <meta name="theme-color" content="#0C0C0C">', 1)
idx.write_text(s)

m = json.loads((web / 'manifest.json').read_text())
m.update({'name': 'كلك جميلة', 'short_name': 'كلك جميلة', 'background_color': '#FFFFFF',
          'theme_color': '#0C0C0C', 'description': 'كلك جميلة - المبيعات والتحصيلات'})
(web / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2))

src = Image.open('assets/icon.png').convert('RGB')
for name, size in [('Icon-192.png', 192), ('Icon-512.png', 512),
                   ('Icon-maskable-192.png', 192), ('Icon-maskable-512.png', 512)]:
    src.resize((size, size)).save(web / 'icons' / name)
src.resize((32, 32)).save(web / 'favicon.png')
print('web patched')
