import glob

dart_files = glob.glob('lib/**/*.dart', recursive=True)
bad = []

for f in dart_files:
    raw = open(f, 'rb').read()
    # Remove BOM
    if raw.startswith(b'\xef\xbb\xbf'):
        raw = raw[3:]
    try:
        raw.decode('utf-8')
    except UnicodeDecodeError as e:
        bad.append((f, str(e)))

if bad:
    print(f'{len(bad)} files with invalid UTF-8:')
    for f, err in bad:
        print(f'  {f}: {err}')
else:
    print('All files are valid UTF-8!')
