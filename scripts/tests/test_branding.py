"""Ensure every platform ships the same master artwork, with safe icon geometry."""
import importlib.util
from pathlib import Path
import re
import struct
import unittest
from unittest import mock
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('branding', ROOT/'scripts/generate-branding.py')
BRANDING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRANDING)
ANDROID = '{http://schemas.android.com/apk/res/android}'
RES = ROOT/BRANDING.RES


class BrandingTest(unittest.TestCase):
    def test_asset_inventory_matches_master_and_generator(self):
        BRANDING.verify()
        self.assertEqual((ROOT/'packaging/fedora/ihtd.svg').read_bytes(), BRANDING.SOURCE.read_bytes())

    def test_inventory_verifies_in_a_windows_crlf_checkout(self):
        with tempfile.TemporaryDirectory() as temp:
            checkout = Path(temp)
            names = BRANDING.inventory() + ['assets/branding/ihtd.svg',
                'assets/branding/generated.json', 'scripts/generate-branding.py']
            for name in names:
                destination = checkout/name
                destination.parent.mkdir(parents=True, exist_ok=True)
                data = (ROOT/name).read_bytes()
                if destination.suffix in {'.svg','.xml','.json','.py'}:
                    data = data.replace(b'\r\n', b'\n').replace(b'\n',b'\r\n')
                destination.write_bytes(data)
            with mock.patch.multiple(BRANDING, ROOT=checkout,
                    SOURCE=checkout/'assets/branding/ihtd.svg',
                    MANIFEST=checkout/'assets/branding/generated.json',
                    __file__=str(checkout/'scripts/generate-branding.py')):
                BRANDING.verify()

    def test_adaptive_monochrome_and_splash_share_art_and_safe_padding(self):
        master = BRANDING.paths()
        for name in ['ic_launcher_foreground', 'ihtd_splash']:
            vector = ET.parse(RES/f'drawable/{name}.xml').getroot()
            group = vector.find('group')
            scale = float(group.attrib[ANDROID+'scaleX'])
            tx = float(group.attrib[ANDROID+'translateX'])
            ty = float(group.attrib[ANDROID+'translateY'])
            paths = group.findall('path')
            self.assertEqual([(p.attrib[ANDROID+'fillColor'], p.attrib[ANDROID+'pathData']) for p in paths], master)
            for _, data in master:
                points = list(map(float, re.findall(r'-?\d+(?:\.\d+)?', data)))
                for x,y in zip(points[::2], points[1::2]):
                    self.assertLessEqual(((x*scale+tx-512)**2+(y*scale+ty-512)**2)**.5, 301)
        mono = ET.parse(RES/'drawable/ic_launcher_monochrome.xml').getroot().find('group/path')
        self.assertEqual(mono.attrib[ANDROID+'fillType'], 'evenOdd')
        self.assertEqual(mono.attrib[ANDROID+'pathData'], ' '.join(d for _,d in master))
        api33 = ET.parse(RES/'mipmap-anydpi-v33/ic_launcher.xml').getroot()
        self.assertEqual(api33.find('monochrome').attrib[ANDROID+'drawable'], '@drawable/ic_launcher_monochrome')
        for theme in ['values','values-night']:
            items = ET.parse(RES/f'{theme}/styles.xml').getroot().findall("style[@name='LaunchTheme']/item")
            values = {i.attrib['name']:i.text for i in items}
            self.assertEqual(values['android:windowSplashScreenAnimatedIcon'], '@drawable/ihtd_splash')

    def test_windows_ico_contains_all_shell_sizes_and_android_densities(self):
        data = (ROOT/'app/windows/runner/resources/app_icon.ico').read_bytes()
        reserved, kind, count = struct.unpack_from('<HHH', data)
        self.assertEqual((reserved,kind,count),(0,1,7))
        sizes = []
        for i in range(count):
            width,height,_,_,_,depth,length,offset = struct.unpack_from('<BBBBHHII',data,6+i*16)
            self.assertEqual(width,height)
            self.assertGreaterEqual(depth,24)
            self.assertGreater(length,0)
            self.assertLessEqual(offset+length,len(data))
            sizes.append(width or 256)
        self.assertEqual(sorted(sizes),[16,24,32,48,64,128,256])
        for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
            png=(RES/f'mipmap-{density}/ic_launcher.png').read_bytes()
            self.assertEqual(png[:8],b'\x89PNG\r\n\x1a\n')
            self.assertEqual(struct.unpack_from('>II',png,16),(size,size))
