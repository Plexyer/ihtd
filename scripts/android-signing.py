"""Create owner-held PKCS12 keys and sign APKs without passwords in argv/logs."""
import argparse
import base64
import getpass
import hashlib
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CERTIFICATE = ROOT / 'packaging/android/release-certificate.sha256'


def fingerprint(path=CERTIFICATE):
    if not path.is_file():
        raise ValueError('Permanent certificate is not configured; see docs/android-signing.md')
    value = path.read_text().strip().lower()
    if not re.fullmatch(r'[0-9a-f]{64}', value):
        raise ValueError('Expected one SHA-256 certificate fingerprint (64 hex digits)')
    return value


def run(command, env=None):
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    if result.returncode:
        # Tool errors may contain sensitive input; report the operation only.
        raise ValueError(f'{Path(command[0]).name} {command[1]} failed')
    return result.stdout


def tool(name):
    executable = shutil.which(name)
    if not executable:
        raise ValueError(f'{name} must be available on PATH')
    return executable


def generate(destination, alias, certificate, password=None, password_file=None):
    if destination.exists() or certificate.exists():
        raise ValueError('Refusing to overwrite an existing key or certificate file')
    if password_file is not None:
        if password_file.exists():
            raise ValueError('Refusing to overwrite a password file')
        password = secrets.token_urlsafe(48)
        password_file.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(password_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w') as output:
            output.write(password + '\n')
    elif password is None:
        password = getpass.getpass('New keystore password (store in your password manager): ')
        if password != getpass.getpass('Confirm password: '):
            raise ValueError('Passwords differ')
    if len(password) < 20:
        raise ValueError('Use a password of at least 20 characters')
    destination.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, IHTD_KEY_PASSWORD=password)
    keytool = tool('keytool')
    # Unix restricts the generated file before keytool writes it; Windows users
    # must use a private account directory (see the ownership documentation).
    previous = os.umask(0o077)
    try:
        run([keytool, '-genkeypair', '-keystore', str(destination), '-storetype',
             'PKCS12', '-alias', alias, '-keyalg', 'RSA', '-keysize', '4096',
             '-validity', '10000', '-dname', 'CN=IHTD Android Release, O=IHTD',
             '-storepass:env', 'IHTD_KEY_PASSWORD', '-keypass:env', 'IHTD_KEY_PASSWORD'], env)
        with tempfile.TemporaryDirectory(prefix='ihtd-public-cert-') as temporary:
            der = Path(temporary) / 'certificate.der'
            run([keytool, '-exportcert', '-keystore', str(destination), '-alias',
                 alias, '-storepass:env', 'IHTD_KEY_PASSWORD', '-file', str(der)], env)
            digest = hashlib.sha256(der.read_bytes()).hexdigest()
        certificate.parent.mkdir(parents=True, exist_ok=True)
        certificate.write_text(digest + '\n')
    finally:
        os.umask(previous)
    print(f'Public certificate SHA-256: {digest}')
    print('Back up the encrypted keystore and password separately before activating releases.')


def verify(apk, expected, apksigner):
    output = run([apksigner, 'verify', '--verbose', '--print-certs', str(apk)])
    digests = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$', output, re.M)
    if len(digests) != 1 or digests[0].lower() != expected:
        raise ValueError('APK signer differs from the pinned permanent certificate')


def sign(source, destination, apksigner, zipalign, keystore=None, password_file=None, alias='ihtd-release'):
    expected = fingerprint()
    env = dict(os.environ)
    if keystore is not None or password_file is not None:
        if keystore is None or password_file is None:
            raise ValueError('Local signing requires both --keystore and --password-file')
        env.update(ANDROID_KEYSTORE_BASE64=base64.b64encode(keystore.read_bytes()).decode(),
                   ANDROID_KEYSTORE_PASSWORD=password_file.read_text().strip(),
                   ANDROID_KEY_ALIAS=alias)
    names = ('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS')
    if any(not env.get(name) for name in names):
        raise ValueError('Required Android signing secrets are missing')
    if destination.exists():
        raise ValueError('Refusing to overwrite a signed APK')
    with tempfile.TemporaryDirectory(prefix='ihtd-signing-') as temporary:
        key = Path(temporary) / 'release.p12'
        key.touch(mode=0o600)
        key.write_bytes(base64.b64decode(env[names[0]], validate=True))
        aligned = Path(temporary) / 'aligned.apk'
        run([zipalign, '-P', '16', '-f', '4', str(source), str(aligned)])
        signed = Path(temporary) / 'signed.apk'
        run([apksigner, 'sign', '--ks', str(key), '--ks-key-alias', env[names[2]],
             '--ks-pass', 'env:ANDROID_KEYSTORE_PASSWORD', '--key-pass',
             'env:ANDROID_KEYSTORE_PASSWORD', '--out', str(signed), str(aligned)], env)
        verify(signed, expected, apksigner)
        run([zipalign, '-c', '-P', '16', '4', str(signed)])
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(signed, destination)
    print('APK signature matches the pinned permanent certificate; 16 KB alignment verified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('generate')
    create.add_argument('--keystore', type=Path, required=True)
    create.add_argument('--alias', default='ihtd-release')
    create.add_argument('--certificate', type=Path, default=CERTIFICATE)
    create.add_argument('--password-file', type=Path,
                        help='Generate a random password into a new private file; never print it')
    commands.add_parser('check-config')
    verification = commands.add_parser('verify')
    verification.add_argument('--apk', type=Path, required=True)
    verification.add_argument('--apksigner', required=True)
    signing = commands.add_parser('sign')
    signing.add_argument('--apk', type=Path, required=True)
    signing.add_argument('--output', type=Path, required=True)
    signing.add_argument('--apksigner', required=True)
    signing.add_argument('--zipalign', required=True)
    signing.add_argument('--keystore', type=Path)
    signing.add_argument('--password-file', type=Path)
    signing.add_argument('--alias', default='ihtd-release')
    args = parser.parse_args()
    try:
        if args.command == 'generate':
            generate(args.keystore.resolve(), args.alias, args.certificate.resolve(),
                     password_file=args.password_file.resolve() if args.password_file else None)
        elif args.command == 'check-config':
            fingerprint()
            print('Permanent signing certificate is configured.')
        elif args.command == 'verify':
            verify(args.apk, fingerprint(), args.apksigner)
            print('APK matches the pinned permanent certificate.')
        else:
            sign(args.apk, args.output, args.apksigner, args.zipalign,
                 args.keystore, args.password_file, args.alias)
    except (ValueError, OSError) as error:
        parser.exit(1, f'{error}\n')
