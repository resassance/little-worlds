import argparse
import os
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--input', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--build-tools', required=True, type=Path)
parser.add_argument('--legacy-keystore', required=True, type=Path)
parser.add_argument('--release-keystore', required=True, type=Path)
parser.add_argument('--release-password-file', required=True, type=Path)
parser.add_argument('--lineage', required=True, type=Path)
args = parser.parse_args()
if 'LW_ANDROID_LEGACY_PASSWORD' not in os.environ:
    parser.error('LW_ANDROID_LEGACY_PASSWORD is required')
args.output.parent.mkdir(parents=True, exist_ok=True)
aligned = args.output.with_name(args.output.stem + '-aligned.apk')
try:
    subprocess.run([str(args.build_tools / 'zipalign'), '-f', '-p', '4', str(args.input), str(aligned)], check=True)
    subprocess.run([
        str(args.build_tools / 'apksigner'), 'sign',
        '--out', str(args.output), '--lineage', str(args.lineage),
        '--rotation-min-sdk-version', '28', '--debuggable-apk-permitted', 'false',
        '--v4-signing-enabled', 'false',
        '--ks', str(args.legacy_keystore), '--ks-key-alias', 'androiddebugkey',
        '--ks-pass', 'env:LW_ANDROID_LEGACY_PASSWORD',
        '--next-signer', '--ks', str(args.release_keystore),
        '--ks-key-alias', 'little-worlds-release',
        '--ks-pass', 'file:' + str(args.release_password_file), str(aligned)
    ], check=True)
    subprocess.run([str(args.build_tools / 'apksigner'), 'verify', '--verbose', str(args.output)], check=True)
finally:
    aligned.unlink(missing_ok=True)
