#!/usr/bin/env python3
"""Collect independent Mac build-readiness failures; never claim an app build passed."""
import json,os,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
checks=[]
def run(name,command):
    try:
        result=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        print(result.stdout,flush=True)
        checks.append(dict(name=name,passed=result.returncode==0,exit_code=result.returncode))
    except OSError as error:
        print(str(error),flush=True);checks.append(dict(name=name,passed=False,error=str(error)))
def require(name,valid):
    checks.append(dict(name=name,passed=bool(valid)))
mode=sys.argv[1]
if mode=='platform':
    require('Apple ARM64 host',sys.platform=='darwin' and os.uname().machine=='arm64')
    for tool in ['xcodebuild','xcrun','codesign','zip','unzip','rsync','ditto','plutil','python3','bash','git','curl']:
        require('tool '+tool,shutil.which(tool))
    require('at least 3 GiB free workspace',shutil.disk_usage(ROOT).free>=3*1024**3)
    run('Xcode selection',['xcodebuild','-version'])
    run('iPhoneOS SDK',['xcrun','--sdk','iphoneos','--show-sdk-path'])
    run('package shell syntax',['bash','-n','scripts/package_ipa.sh'])
    with tempfile.TemporaryDirectory(prefix='husk-signing-') as d:
        p=Path(d);(p/'probe.c').write_text('int husk_probe(void) { return 42; }\n')
        run('iOS arm64 compiler/linker',['xcrun','--sdk','iphoneos','clang','-target','arm64-apple-ios15.5','-dynamiclib',str(p/'probe.c'),'-o',str(p/'probe.dylib')])
        run('ad hoc entitlement signing',['codesign','--force','--sign','-','--timestamp=none','--entitlements',str(ROOT/'src/app/Husk/Husk.entitlements'),str(p/'probe.dylib')])
        run('signature verification',['codesign','--verify','--strict',str(p/'probe.dylib')])
        run('zip packaging',['zip','-q',str(p/'probe.zip'),str(p/'probe.c')])
        run('zip verification',['unzip','-t',str(p/'probe.zip')])
elif mode=='project':
    run('project generation',['xcodegen','generate','--spec',str(ROOT/'src/app/project.yml'),'--project',str(ROOT/'src/app')])
    run('project and scheme loading',['xcodebuild','-list','-json','-project',str(ROOT/'src/app/Husk.xcodeproj')])
    run('iOS release settings',['xcodebuild','-showBuildSettings','-project',str(ROOT/'src/app/Husk.xcodeproj'),'-scheme','Husk','-sdk','iphoneos','-configuration','Release','CODE_SIGNING_ALLOWED=NO'])
    for name in ['libhusk_rppairing.a','libqemu-aarch64-softmmu.dylib','libhuskps4.dylib','MoltenVK.framework/MoltenVK','HuskMoltenVK.framework/HuskMoltenVK']:
        path=ROOT/'build/ios-arm64/lib'/name
        require('staged '+name,path.is_file() and path.stat().st_size>0)
    require('verified release shader library',(ROOT/'build/graphics-base/Payload/Husk.app/default.metallib').is_file())
    require('StikJIT arm64 framework',(ROOT/'src/app/Frameworks/StikJIT.xcframework/ios-arm64/StikJIT.framework/StikJIT').is_file())
else:raise SystemExit('unknown preflight mode')
output=ROOT/'build/logs';output.mkdir(parents=True,exist_ok=True)
(output/('preflight-'+mode+'.json')).write_text(json.dumps(checks,indent=2)+'\n')
for check in checks: print(('PASS 'if check['passed']else'FAIL ')+check['name'],flush=True)
raise SystemExit(0 if all(c['passed']for c in checks)else 1)
