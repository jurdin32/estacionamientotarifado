import os, re

# Build reverse map: Unicode char -> Windows-1252 byte value
CP1252_EXTRA = {
    0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E,
    0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
    0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
    0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
    0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
    0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
    0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
}

UNI_TO_CP1252_BYTE = {}
for byte_val, uni_cp in CP1252_EXTRA.items():
    UNI_TO_CP1252_BYTE[uni_cp] = byte_val
for b in range(0xA0, 0x100):
    UNI_TO_CP1252_BYTE[b] = b
for b in [0x81, 0x8D, 0x8F, 0x90, 0x9D]:
    UNI_TO_CP1252_BYTE[b] = b

MOJIBAKE_CHARS = set(chr(cp) for cp in UNI_TO_CP1252_BYTE)

def char_to_byte(ch):
    cp = ord(ch)
    return UNI_TO_CP1252_BYTE.get(cp)

def fix_mojibake_segment(segment):
    raw = bytearray()
    for ch in segment:
        b = char_to_byte(ch)
        if b is None:
            return None
        raw.append(b)
    try:
        return raw.decode('utf-8')
    except UnicodeDecodeError:
        return None

def fix_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    original = text

    mojibake_pattern = re.compile(
        '[' + re.escape(''.join(sorted(MOJIBAKE_CHARS))) + ']{2,}'
    )

    def replacer(m):
        segment = m.group(0)
        result = fix_mojibake_segment(segment)
        if result is not None and result != segment:
            return result
        return segment

    text = mojibake_pattern.sub(replacer, text)

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
        if any(marker in content for marker in [
            '\u00e2\u20ac\u201c', '\u00f0\u0178',
            '\u00c3\u00a1', '\u00c3\u00b3', '\u00c3\u00a9'
        ]):
            remaining += 1
            print(f'STILL BAD: {path}')

if remaining == 0:
    print('ALL CLEAN!')
