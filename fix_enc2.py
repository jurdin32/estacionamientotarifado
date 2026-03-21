import glob, os

dart_files = glob.glob('lib/**/*.dart', recursive=True)
fixed_count = 0

for f in dart_files:
    raw = open(f, 'rb').read()
    if raw.startswith(b'\xef\xbb\xbf'):
        raw = raw[3:]
    
    text = raw.decode('utf-8')
    
    try:
        fixed = text.encode('latin-1').decode('utf-8')
        if fixed != text:
            open(f, 'w', encoding='utf-8', newline='\n').write(fixed)
            fixed_count += 1
            print(f'  FIXED: {f}')
            continue
    except (UnicodeDecodeError, UnicodeEncodeError):
        pass

print(f'Total fixed: {fixed_count} / {len(dart_files)} files')
