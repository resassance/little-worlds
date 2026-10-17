import argparse
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--input', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--signer', required=True, type=Path)
parser.add_argument('--pkcs12', required=True, type=Path)
parser.add_argument('--password-file', required=True, type=Path)
parser.add_argument('--certificate', required=True, type=Path)
args = parser.parse_args()
if args.input.resolve() == args.output.resolve():
    parser.error('Input and output must be different files')
args.output.parent.mkdir(parents=True, exist_ok=True)
subprocess.run([
    str(args.signer), 'sign', '-pkcs12', str(args.pkcs12),
    '-readpass', str(args.password_file), '-h', 'sha256',
    '-n', 'Little Worlds', '-i', 'https://github.com/resassance/little-worlds',
    '-in', str(args.input), '-out', str(args.output)
], check=True)
subprocess.run([
    str(args.signer), 'verify', '-CAfile', str(args.certificate),
    '-in', str(args.output)
], check=True)
