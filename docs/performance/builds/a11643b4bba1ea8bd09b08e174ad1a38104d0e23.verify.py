"""Independent verification of downloaded build172; no device quality claim."""
from pathlib import Path
import sys,zipfile,hashlib,json,struct,plistlib,importlib.util
outer=Path(sys.argv[1]);expected=sys.argv[2];root=Path(sys.argv[3]) if len(sys.argv)>3 else Path(__file__).resolve().parents[3]
result={'download_sha256':hashlib.sha256(outer.read_bytes()).hexdigest(),'download_bytes':outer.stat().st_size}
with zipfile.ZipFile(outer) as z:
    assert z.testzip() is None
    if 'Payload/Husk.app/Info.plist' in z.namelist():ipa=outer
    else:
        members=[n for n in z.namelist() if n.endswith('.ipa')];assert len(members)==1
        ipa=outer.with_name('Husk-3.4-build172-Dungeons.ipa');ipa.write_bytes(z.read(members[0]))

def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
contract_module=module('contract172',root/'scripts/stage_framegen_contract.py')
def macho(raw):
    assert struct.unpack_from('<II',raw)==(0xfeedfacf,0x100000c)
    p=32;signature=0;symbols=[]
    for _ in range(struct.unpack_from('<I',raw,16)[0]):
        cmd,size=struct.unpack_from('<II',raw,p)
        assert size>=8 and p+size<=len(raw)
        if cmd==0x1d:signature=struct.unpack_from('<I',raw,p+12)[0]
        if cmd==2:
            offset,count,strings,_=struct.unpack_from('<4I',raw,p+8)
            for i in range(count):
                index,typ=struct.unpack_from('<IB',raw,offset+16*i)
                if typ&0xe==0xe:symbols.append(raw[strings+index:raw.find(b'\0',strings+index)].decode(errors='replace'))
        p+=size
    assert signature>0
    return {'signature_bytes':signature,'symbols':symbols,'code_sha256':contract_module.code_digest(raw)}
with zipfile.ZipFile(ipa) as z:
    assert z.testzip() is None;app='Payload/Husk.app/'
    info=plistlib.loads(z.read(app+'Info.plist'))
    assert info['CFBundleVersion']=='172' and info['CFBundleIdentifier']=='com.husk.app' and info['CFBundleShortVersionString']=='3.4'
    assert info['HuskBuildCommit'] in [expected,expected+'-dirty']
    result['info']=info
    host=z.read(app+'Husk');hostmeta=macho(host)
    for text in ['Controls & display','App details & storage','Capture frame-generation evidence','Developer experiments','framegen-analysis.json','effective_launch','saved_requested_settings_at_export','Identification & feedback','30 → 60 · Frame Generation (Beta)']:
        assert text.encode() in host,text
    for symbol in ['_tl_fg_contract_verify','_tl_vk_framegen_capture_arm','_husk_ue4_set_framegen_capture_directory','_tl_vk_is_metal4']:
        assert symbol in hostmeta['symbols'],symbol
    result['host_code_sha256']=hostmeta['code_sha256']
    contract=json.loads(z.read(app+'framegen-contract.json'));assert contract['model']==3 and contract['app_source']==expected
    assert set(contract['libraries'])=={'HuskMoltenVK','HuskKosmicKrisp'}
    shader=(root/'patches/metalfx/HuskFramegen.metal').read_bytes();result['drivers']={}
    for name,meta_name in [('HuskMoltenVK','HuskSpatialBuild.json'),('HuskKosmicKrisp','HuskMetal4Build.json')]:
        base=app+'Frameworks/'+name+'.framework/';raw=z.read(base+name);meta=json.loads(z.read(base+meta_name));compiled=macho(raw)
        assert shader in raw
        for marker in [b'image_measurements',b'exact_rgb_copy',b'maximum_rgb_difference_codes',b'presented_minus_target_ms',b'prepared-presentation-v1',b'whole_frame_real_fallback']:
            assert marker in raw,(name,marker)
        for export in ['FramegenConfigure','FramegenSnapshot','FramegenPause','FramegenCaptureConfigure']:
            assert '_vkHusk'+export in compiled['symbols']
        if name=='HuskMoltenVK':
            inputs=module('reuse172',root/'scripts/reuse_spatial_driver.py').INPUTS
            patch=hashlib.sha256(b''.join((root/n).read_bytes() for n in inputs)).hexdigest()
            assert meta['husk_spatial_patch_sha256']==patch
            assert meta['native_archive_abi']==2 and meta['native_archive_cache_schema']==2
        else:
            inputs=module('metal172',root/'scripts/prepare_metal4_source.py').INPUTS;h=hashlib.sha256()
            for n in inputs:h.update(n.encode()+b'\0'+(root/n).read_bytes()+b'\0')
            patch=h.hexdigest();assert meta['patch_sha256']==patch
            assert meta['code_sha256']==compiled['code_sha256']
            assert meta['framegen_capture_abi']==1 and meta['native_archive_abi']==2
            assert meta['compiler_contract']=='husk-kk-native-v1'
            assert len(z.read(base+'Licenses/Mesa-license.rst'))>0
        entry=contract['libraries'][name]
        assert entry['code_sha256']==compiled['code_sha256'] and entry['patch_sha256']==patch
        assert entry['shader_sha256']==hashlib.sha256(shader).hexdigest()
        result['drivers'][name]={'manifest':meta,'code_sha256':compiled['code_sha256'],'exact_shader':True,'patch_source_matches':True}
    extensions={n.split('/')[3] for n in z.namelist() if n.startswith(app+'PlugIns/') and '.appex/' in n}
    assert extensions=={'HuskMemoryDonor.appex','HuskJITHelper.appex','HuskDownloadsWidget.appex'}
    for ext in extensions:
        base=app+'PlugIns/'+ext+'/';p=plistlib.loads(z.read(base+'Info.plist'));assert p['NSExtension']['NSExtensionPointIdentifier'];macho(z.read(base+p['CFBundleExecutable']))
    result['extensions']=sorted(extensions)
    assert hashlib.sha256(z.read(app+'android-system/fonts/Roboto-Regular.ttf')).hexdigest()=='9e157d5ff70ae52cc8c527b36e89d9b3c69c6c814da79fa6237a0bf0895abc7c'
    java=json.loads(z.read(app+'java-runtime/husk-framework-build.json'))
    for name,record in java['files'].items():
        raw=z.read(app+'java-runtime/'+name);assert len(raw)==record['bytes'] and hashlib.sha256(raw).hexdigest()==record['sha256']
    for name,sha in java.get('storage_sources',{}).items():assert hashlib.sha256((root/name).read_bytes()).hexdigest()==sha
    result['java']=java
result['ipa_bytes']=ipa.stat().st_size;result['ipa_sha256']=hashlib.sha256(ipa.read_bytes()).hexdigest();result['source']=expected
outer.with_name('husk172-verification.json').write_text(json.dumps(result,indent=2))
print(json.dumps({'ipa':str(ipa),'bytes':result['ipa_bytes'],'sha256':result['ipa_sha256'],'source':expected,'checks':'package/arm64/signatures/source/contracts/exact shaders/driver patches/UI markers/extensions/Java/font passed'},indent=2))
