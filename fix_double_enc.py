import glob

# Double-encoded characters: UTF-8 bytes read as Latin-1 then re-encoded as UTF-8
replacements = {
    '\u00c3\u00b3': '\u00f3',   # ó
    '\u00c3\u00a9': '\u00e9',   # é
    '\u00c3\u00a1': '\u00e1',   # á
    '\u00c3\u00ad': '\u00ed',   # í
    '\u00c3\u00ba': '\u00fa',   # ú
    '\u00c3\u00b1': '\u00f1',   # ñ
    '\u00c3\u0081': '\u00c1',   # Á
    '\u00c3\u0089': '\u00c9',   # É
    '\u00c3\u0093': '\u00d3',   # Ó
    '\u00c3\u009a': '\u00da',   # Ú
    '\u00c3\u0091': '\u00d1',   # Ñ
    '\u00c2\u00bf': '\u00bf',   # ¿
    '\u00c2\u00a1': '\u00a1',   # ¡
    '\u00c3\u00a0': '\u00e0',   # à
    '\u00c3\u00bc': '\u00fc',   # ü
}

# Box-drawing and special chars
box_replacements = {
    '\u00e2\u0080\u0094': '\u2014',  # —
    '\u00e2\u0080\u0093': '\u2013',  # –
    '\u00e2\u0094\u0080': '\u2500',  # ─
    '\u00e2\u0094\u0082': '\u2502',  # │
    '\u00e2\u0094\u009c': '\u251c',  # ├
    '\u00e2\u0094\u0094': '\u2514',  # └
    '\u00e2\u0094\u00a4': '\u2524',  # ┤
    '\u00e2\u0094\u00ac': '\u252c',  # ┬
    '\u00e2\u0094\u00b4': '\u2534',  # ┴
    '\u00e2\u0094\u00bc': '\u253c',  # ┼
    '\u00e2\u0095\u0090': '\u2550',  # ═
}
replacements.update(box_replacements)

# Emoji double-encoded
emoji_replacements = {
    '\u00e2\u009c\u0085': '\u2705',  # ✅
    '\u00e2\u009c\u0093': '\u2713',  # ✓
    '\u00e2\u009d\u008c': '\u274c',  # ❌
    '\u00e2\u009a\u00a0': '\u26a0',  # ⚠
    '\u00e2\u008f\u00b0': '\u23f0',  # ⏰
    '\u00e2\u008f\u00b8': '\u23f8',  # ⏸
    '\u00f0\u009f\u0094\u0084': '\U0001f504',  # 🔄
    '\u00f0\u009f\u0093\u00b1': '\U0001f4f1',  # 📱
    '\u00f0\u009f\u0094\u008c': '\U0001f50c',  # 🔌
    '\u00f0\u009f\u0093\u00b5': '\U0001f4f5',  # 📵
}
replacements.update(emoji_replacements)

fixed = 0
for f in glob.glob('lib/**/*.dart', recursive=True):
    text = open(f, 'r', encoding='utf-8').read()
    original = text
    for bad, good in replacements.items():
        text = text.replace(bad, good)
    if text != original:
        open(f, 'w', encoding='utf-8', newline='\n').write(text)
        fixed += 1
        print(f'Fixed: {f}')

print(f'\nTotal fixed: {fixed}')
