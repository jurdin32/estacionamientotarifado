import os, re

def fix_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    original = text

    # Strategy: find sequences of chars in U+0080..U+00FF that,
    # when encoded as latin-1 bytes, form valid UTF-8.
    # This reverses the double-encoding.
    def try_fix_segment(m):
        segment = m.group(0)
        try:
            raw_bytes = segment.encode('latin-1')
            decoded = raw_bytes.decode('utf-8')
            return decoded
        except (UnicodeDecodeError, UnicodeEncodeError):
            return segment

    # Match sequences of characters in the range U+0080 to U+00FF
    # (these are the "latin-1 interpretations" of UTF-8 bytes)
    pattern = re.compile(r'[\u0080-\u00ff]{2,}')
    text = pattern.sub(try_fix_segment, text)

    if text != original:
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        return True
    return False

fixed = 0
for root, dirs, files in os.walk('lib'):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(root, fn)
        if fix_file(path):
            fixed += 1
            print(f'FIXED: {path}')

print(f'\nTotal fixed: {fixed}')

# Verify
remaining = 0
for root, dirs, files in os.walk('lib'):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(root, fn)
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        if re.search(r'[\u00c0-\u00c3][\u0080-\u00bf]', content):
            remaining += 1
            print(f'STILL BAD: {path}')

if remaining == 0:
    print('ALL CLEAN!')
