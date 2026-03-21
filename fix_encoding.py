import glob, os

dart_files = glob.glob('lib/**/*.dart', recursive=True)
fixed_count = 0

for f in dart_files:
    raw = open(f, 'rb').read()
    # Remove BOM if present
    if raw.startswith(b'\xef\xbb\xbf'):
        raw = raw[3:]
    
    text = raw.decode('utf-8')
    
    # Fix double-encoded UTF-8 (UTF-8 bytes read as Latin-1, then written as UTF-8)
    # Try the "encode as latin-1, decode as utf-8" trick
    try:
        fixed = text.encode('latin-1').decode('utf-8')
        if fixed != text:
            open(f, 'w', encoding='utf-8', newline='\n').write(fixed)
            fixed_count += 1
            print(f'  FIXED: {f}')
            continue
    except (UnicodeDecodeError, UnicodeEncodeError):
        pass
    
    # No double encoding, just ensure UTF-8 without BOM and LF line endings
    original = open(f, 'rb').read()
    new_content = text.encode('utf-8')
    if original != new_content:
        open(f, 'w', encoding='utf-8', newline='\n').write(text)
        print(f'  NORMALIZED: {f}')

print(f'\nTotal fixed: {fixed_count} / {len(dart_files)} files')
