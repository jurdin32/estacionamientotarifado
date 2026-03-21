import glob

# Strategy: read each file as bytes, try to fix by decoding as UTF-8,
# then for each problematic section, try encoding as Latin-1 and decoding as UTF-8.
# If a file still has issues after the simple replacement table, use a smarter approach.

# Extended replacement table including multi-byte emoji sequences
replacements = {}

# Build from all common Latin-1 -> UTF-8 double-encoding patterns
# When UTF-8 byte sequence C3 XX is read as Latin-1, it becomes Ã + chr(XX)
# When that Latin-1 text is then written as UTF-8, Ã becomes C3 83, chr(XX) becomes CX XX or just XX
for i in range(0x80, 0x100):
    original_char = chr(i)
    try:
        # Original UTF-8 bytes for this character
        utf8_bytes = original_char.encode('utf-8')
        # When read as Latin-1
        latin1_text = utf8_bytes.decode('latin-1')
        # When re-encoded as UTF-8
        double_encoded_bytes = latin1_text.encode('utf-8')
        # When read back as UTF-8
        double_encoded_text = double_encoded_bytes.decode('utf-8')
        if double_encoded_text != original_char:
            replacements[double_encoded_text] = original_char
    except:
        pass

# Also handle common box-drawing and other multi-byte chars
special_chars = [
    '\u2500', '\u2502', '\u250c', '\u2510', '\u2514', '\u2518', '\u251c', '\u2524',
    '\u252c', '\u2534', '\u253c', '\u2550', '\u2551', '\u2552', '\u2553', '\u2554',
    '\u2555', '\u2556', '\u2557', '\u2558', '\u2559', '\u255a', '\u255b', '\u255c',
    '\u255d', '\u255e', '\u255f', '\u2560', '\u2561', '\u2562', '\u2563', '\u2564',
    '\u2565', '\u2566', '\u2567', '\u2568', '\u2569', '\u256a', '\u256b', '\u256c',
    '\u2014', '\u2013', '\u2018', '\u2019', '\u201c', '\u201d', '\u2026',
    '\u2705', '\u2713', '\u274c', '\u26a0', '\u23f0', '\u23f8',
    '\U0001f504', '\U0001f4f1', '\U0001f50c', '\U0001f4f5',
    '\U0001f4b0', '\U0001f4b3', '\U0001f6a8', '\U0001f4dd',
]

for ch in special_chars:
    try:
        utf8_bytes = ch.encode('utf-8')
        latin1_text = utf8_bytes.decode('latin-1')
        double_encoded_bytes = latin1_text.encode('utf-8')
        double_encoded_text = double_encoded_bytes.decode('utf-8')
        if double_encoded_text != ch:
            replacements[double_encoded_text] = ch
    except:
        pass

# Sort by length descending so longer replacements are applied first
sorted_replacements = sorted(replacements.items(), key=lambda x: len(x[0]), reverse=True)

fixed = 0
for f in glob.glob('lib/**/*.dart', recursive=True):
    text = open(f, 'r', encoding='utf-8').read()
    original = text
    for bad, good in sorted_replacements:
        text = text.replace(bad, good)
    if text != original:
        open(f, 'w', encoding='utf-8', newline='\n').write(text)
        fixed += 1
        print(f'Fixed: {f}')

print(f'\nTotal fixed: {fixed}')
