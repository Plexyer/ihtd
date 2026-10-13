"""Upload owner-held signing credentials using a trusted local gh login."""
import argparse
import base64
import getpass
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location('android_signing', Path(__file__).with_name('android-signing.py'))
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--keystore', type=Path, required=True)
parser.add_argument('--alias', default='ihtd-release')
parser.add_argument('--repo', default='Plexyer/ihtd')
parser.add_argument('--password-file', type=Path)
args = parser.parse_args()
try:
    expected = signing.fingerprint()
    password = (args.password_file.read_text().strip() if args.password_file
                else getpass.getpass('Keystore password: '))
    with tempfile.TemporaryDirectory(prefix='ihtd-cert-check-') as temporary:
        certificate = Path(temporary) / 'certificate.der'
        signing.run([signing.tool('keytool'), '-exportcert', '-keystore',
                     str(args.keystore.resolve()), '-alias', args.alias,
                     '-storepass:env', 'IHTD_KEY_PASSWORD', '-file', str(certificate)],
                    dict(os.environ, IHTD_KEY_PASSWORD=password))
        if hashlib.sha256(certificate.read_bytes()).hexdigest() != expected:
            raise ValueError('Keystore does not match the committed release certificate')
    values = {
        'ANDROID_KEYSTORE_BASE64': base64.b64encode(args.keystore.read_bytes()).decode(),
        'ANDROID_KEYSTORE_PASSWORD': password,
        'ANDROID_KEY_ALIAS': args.alias,
    }
    for name, value in values.items():
        result = subprocess.run([signing.tool('gh'), 'secret', 'set', name, '--repo',
                                 args.repo, '--env', 'android-release'], input=value,
                                capture_output=True, text=True)
        if result.returncode:
            raise ValueError(f'Uploading {name} failed; check administrator access and environment setup')
    print('Three signing secrets uploaded to the android-release environment.')
except (ValueError, OSError) as error:
    parser.exit(1, f'{error}\n')
