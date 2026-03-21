import glob

# Remaining uppercase accented chars that were double-encoded differently
# These produce patterns where the second byte got interpreted as a Windows-1252 char
reps = {
    '\u00c3\u0161': '\u00da',   # Ú
    '\u00c3\u201c': '\u00d3',   # Ó (the " is U+201C from Windows-1252 interpretation of 0x93)
    '\u00c3\u2030': '\u00c9',   # É (the ‰ is U+2030 from Windows-1252 interpretation of 0x89)
    '\u00c3\u0152': '\u00d2',   # Ò
}

fixed = 0
for f in glob.glob('lib/**/*.dart', recursive=True):
    t = open(f, 'r', encoding='utf-8').read()
    o = t
    for bad, good in reps.items():
        t = t.replace(bad, good)
    if t != o:
        open(f, 'w', encoding='utf-8', newline='\n').write(t)
        fixed += 1
        print(f'Fixed: {f}')
print(f'Total: {fixed}')
