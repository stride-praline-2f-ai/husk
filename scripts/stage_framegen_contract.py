#!/usr/bin/env python3
"""Bind the app to the exact reviewed FG driver code; never trust a toggle alone."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,struct,subprocess
ROOT=Path(__file__).resolve().parents[1]
REQUIRED=[b'_coarsePSO',b'_regularizePSO',b'_qualityPSO',b'hierarchical-coherent-quality-v2']
def code_digest(raw):
    if len(raw)<32 or struct.unpack_from('<I',raw)[0]!=0xfeedfacf:raise ValueError('Expected thin64-bit Mach-O')
    commands,bytes_=struct.unpack_from('<II',raw,16)
    if commands>4096 or 32+bytes_>len(raw):raise ValueError('Invalid Mach-O command range')
    offset=32
    for _ in range(commands):
        if offset+8>32+bytes_:raise ValueError('Truncated Mach-O command')
        cmd,size=struct.unpack_from('<II',raw,offset)
        if size<8 or offset+size>32+bytes_:raise ValueError('Invalid Mach-O command')
        if cmd==0x19:
            if size<72:raise ValueError('Truncated segment')
            count=struct.unpack_from('<I',raw,offset+64)[0]
            if 72+count*80>size:raise ValueError('Truncated sections')
            for i in range(count):
                p=offset+72+i*80;section=raw[p:p+16].split(b'\0')[0];segment=raw[p+16:p+32].split(b'\0')[0]
                if section==b'__text'and segment==b'__TEXT':
                    length=struct.unpack_from('<Q',raw,p+40)[0];start=struct.unpack_from('<I',raw,p+48)[0]
                    if not length or length>64*1024*1024 or start+length>len(raw):raise ValueError('Invalid code section')
                    return hashlib.sha256(raw[start:start+length]).hexdigest()
        offset+=size
    raise ValueError('No code section')
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def stage(libroot,output,source):
    shader=(ROOT/'patches/metalfx/HuskFramegen.metal').read_bytes();entries={}
    for driver,meta_name in [('HuskMoltenVK','HuskSpatialBuild.json'),('HuskKosmicKrisp','HuskMetal4Build.json')]:
        folder=libroot/(driver+'.framework');binary=folder/driver
        if not binary.exists():continue # Optional renderer absent: runtime FG is refused.
        raw=binary.read_bytes();meta=json.loads((folder/meta_name).read_text());code=code_digest(raw)
        if len(raw)>128*1024*1024 or shader not in raw or any(marker not in raw for marker in REQUIRED):raise ValueError('Required fixed FG model absent: '+driver)
        if driver=='HuskMoltenVK':
            inputs=module('fgreuse',ROOT/'scripts/reuse_spatial_driver.py').INPUTS
            digest=hashlib.sha256(b''.join((ROOT/n).read_bytes()for n in inputs)).hexdigest();actual=meta['husk_spatial_patch_sha256']
        else:
            inputs=module('fgmetal4',ROOT/'scripts/prepare_metal4_source.py').INPUTS
            h=hashlib.sha256()
            for n in inputs:h.update(n.encode()+b'\0'+(ROOT/n).read_bytes()+b'\0')
            digest=h.hexdigest();actual=meta['patch_sha256']
            if code!=meta['code_sha256']:raise ValueError('Source Metal4 code digest mismatch')
        if digest!=actual:raise ValueError('Stale FG source/patch contract: '+driver)
        entries[driver]={'code_sha256':code,'patch_sha256':digest,'shader_sha256':hashlib.sha256(shader).hexdigest(),'driver_compile_source':meta.get('husk_source_at_compile','UNAVAILABLE')}
    record={'schema':1,'model':2,'app_source':source,'required_pipeline':'hierarchical-coherent-quality-v2','libraries':entries,'scope':'Mandatory when FG is enabled; loaded entrypoint image code is checked before enabling the30FPS source cap. No environment bypass. Game CVars cannot replace these host kernels.'}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(record,indent=2)+'\n')
    return record
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('libroot',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    r=stage(a.libroot,a.output,source);print('Staged mandatory FG model2 contract for:',','.join(r['libraries'])or'no optional FG drivers (FG refuses safely)')
