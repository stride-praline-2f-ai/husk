#!/usr/bin/env python3
"""Reuse official3.4 compiled shaders only while the exact shader source is unchanged."""
import hashlib,sys,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DONOR='3907f099d91411c24d703d825276102d2ba213c628cd6701fb977c25fe398fab'
SOURCE='b70aabc7aa1376f81f90bee59cdf7831358990d1d2380caf387b2302132e85eb'
def stage(ipa):
    if hashlib.sha256(ipa.read_bytes()).hexdigest()!=DONOR:raise SystemExit('Wrong shader donor; refusing reuse')
    if hashlib.sha256((ROOT/'src/app/Husk/Shaders.metal').read_bytes()).hexdigest()!=SOURCE:raise SystemExit('Shader source changed; install Metal compiler and rebuild shaders')
    with zipfile.ZipFile(ipa)as z: data=z.read('Payload/Husk.app/default.metallib')
    if not data or data[:4]!=b'MTLB':raise SystemExit('Missing/invalid official Metal library')
    target=ROOT/'build/graphics-base/Payload/Husk.app/default.metallib'
    if not target.is_file() or target.read_bytes()!=data:raise SystemExit('Official resources must be staged first')
    project=ROOT/'src/app/project.yml';text=project.read_text()
    anchor='          - "Resources/**"'
    if text.count(anchor)!=1:raise SystemExit('Unexpected shader project layout')
    text=text.replace(anchor,anchor+'\n          # Exact-source official3.4 default.metallib is copied with release resources.\n          - "Shaders.metal"')
    project.write_text(text)
    print('Verified unchanged3.4 shaders; donor metallib SHA256 '+hashlib.sha256(data).hexdigest())
if __name__=='__main__':stage(Path(sys.argv[1]))
