"""Check unsigned device packages without claiming an installation test."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

for argument in sys.argv[1:]:
    package = Path(argument)
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        assert archive.testzip() is None
        assert all(name.startswith('Payload/') and '..' not in name.split('/') for name in names)
        root_info = next(name for name in names if name.count('/') == 2 and name.endswith('/Info.plist'))
        info = plistlib.loads(archive.read(root_info))
        app = root_info.rsplit('/', 1)[0]
        executable = archive.read(app + '/' + info['CFBundleExecutable'])
        assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
        assert info['MinimumOSVersion'] == '18.0'
        assert executable[:4] == b'\xcf\xfa\xed\xfe'
        assert struct.unpack('<I', executable[4:8])[0] == 0x100000c  # ARM64, not a simulator binary.
        assert not any(name.endswith('.mobileprovision') for name in names)
        assert info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName')
        extensions = []
        if 'FocusTube' in package.name:
            extension_info = next(name for name in names if name.endswith('.appex/Info.plist'))
            extension = plistlib.loads(archive.read(extension_info))
            assert extension['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.Safari.web-extension'
            assert extension['CFBundleIdentifier'].startswith(info['CFBundleIdentifier'] + '.')
            assert info['CFBundleShortVersionString'] == extension['CFBundleShortVersionString'] == '0.1.1'
            folder = extension_info.rsplit('/', 1)[0]
            manifest = json.loads(archive.read(folder + '/manifest.json'))
            assert manifest['content_scripts'][0]['world'] == 'MAIN'
            assert set(manifest['content_scripts'][0]['matches']) == {'https://youtube.com/*', 'https://m.youtube.com/*', 'https://www.youtube.com/*'}
            assert 'Zmień konto' in archive.read(folder + '/content.js').decode()
            host_html = archive.read(app + '/Base.lproj/Main.html').decode()
            assert 'lang="pl"' in host_html and 'Rozszerzenia' in host_html
            extensions.append(extension['CFBundleIdentifier'])
        else:
            assert info['CFBundleIdentifier'] == 'dev.palamabron.warsawtechradar'
            assert info['CFBundleShortVersionString'] == '0.2.0'
            html = archive.read(app + '/radar.html').decode()
            assert 'window.RADAR_NATIVE = true' in html and 'nativeCall' in html
        report = {'file': package.name, 'sha256': hashlib.sha256(package.read_bytes()).hexdigest(), 'bytes': package.stat().st_size, 'bundleId': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'], 'minimumIOS': info['MinimumOSVersion'], 'platform': 'iPhoneOS', 'architecture': 'arm64', 'extensions': extensions, 'signed': False, 'deviceTested': False}
        package.with_suffix('.validation.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(report))
