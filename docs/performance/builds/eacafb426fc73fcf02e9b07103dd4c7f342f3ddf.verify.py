from pathlib import Path
import hashlib,json,plistlib,zipfile,struct,sys
outer=Path(sys.argv[1]);result={'zip_sha256':hashlib.sha256(outer.read_bytes()).hexdigest(),'zip_bytes':outer.stat().st_size}
with zipfile.ZipFile(outer)as z:
 assert z.testzip()is None
 names=[n for n in z.namelist()if n.endswith('.ipa')];assert len(names)==1,names
 data=z.read(names[0])
ipa=Path('/workspace/Husk-3.4-build166-Metal4-FG-Fix.ipa');ipa.write_bytes(data)
result.update(ipa_sha256=hashlib.sha256(data).hexdigest(),ipa_bytes=len(data))
def macho(b):
 assert struct.unpack_from('<I',b)[0]==0xfeedfacf
 assert struct.unpack_from('<I',b,4)[0]==0x100000c
 p=32;out={'sections':{}};symbols=[]
 for _ in range(struct.unpack_from('<I',b,16)[0]):
  cmd,n=struct.unpack_from('<II',b,p)
  if cmd==0x1d:out['code_signature_bytes']=struct.unpack_from('<I',b,p+12)[0]
  if cmd==0x1b:out['uuid']=b[p+8:p+24].hex()
  if cmd==2:
   symoff,nsyms,stroff,strsize=struct.unpack_from('<4I',b,p+8)
   for i in range(nsyms):
    pos=symoff+i*16;idx,typ=struct.unpack_from('<IB',b,pos)
    if typ&0xe==0xe:
     symbols.append(b[stroff+idx:b.find(b'\0',stroff+idx)].decode(errors='replace'))
  if cmd==0x19:
   for i in range(struct.unpack_from('<I',b,p+64)[0]):
    q=p+72+i*80;sect=b[q:q+16].split(b'\0')[0].decode();seg=b[q+16:q+32].split(b'\0')[0].decode();size=struct.unpack_from('<Q',b,q+40)[0];off=struct.unpack_from('<I',b,q+48)[0];flags=struct.unpack_from('<I',b,q+64)[0]
    if flags&255 not in [1,12,18]:out['sections'][seg+','+sect]=hashlib.sha256(b[off:off+size]).hexdigest()
  p+=n
 out['symbols']=symbols;return out
def progress_getter(raw):
 def pair(o):return struct.unpack_from('<II',raw,o)
 def ul(o):
  value=shift=0
  while True:
   b=raw[o];o+=1;value|=(b&127)<<shift;shift+=7
   if b<128:return value,o
 def string(o):
  _,o=ul(o);return raw[o:raw.index(0,o)].decode('utf8','replace')
 n,off=pair(0x38);strings=[string(struct.unpack_from('<I',raw,off+4*i)[0])for i in range(n)]
 n,off=pair(0x40);types=[strings[struct.unpack_from('<I',raw,off+4*i)[0]]for i in range(n)]
 n,off=pair(0x50);fields=[strings[struct.unpack_from('<HHI',raw,off+8*i)[2]]for i in range(n)]
 n,off=pair(0x58);methods=[struct.unpack_from('<HHI',raw,off+8*i)for i in range(n)]
 n,off=pair(0x60)
 for i in range(n):
  row=struct.unpack_from('<8I',raw,off+32*i)
  if types[row[0]]!='Landroid/widget/ProgressBar;':continue
  o=row[6];sf,o=ul(o);nf,o=ul(o);dm,o=ul(o);vm,o=ul(o)
  for _ in range(sf+nf):_,o=ul(o);_,o=ul(o)
  for count in [dm,vm]:
   index=0
   for _ in range(count):
    delta,o=ul(o);index+=delta;flags,o=ul(o);code,o=ul(o)
    if strings[methods[index][2]]!='getIndeterminateDrawable':continue
    size=struct.unpack_from('<I',raw,code+12)[0]
    units=list(struct.unpack_from('<'+'H'*size,raw,code+16))
    assert size==10,units
    assert [units[j]for j in [0,2,3,4,6,7,9]]==[0x1054,0x38,5,0x1054,0x11,0x1054,0x11],units
    names=[fields[units[j]]for j in [1,5,8]]
    assert names==['mIndeterminateDrawable','mIndeterminateDrawable','mThemeIndeterminate'],names
    return {'method':'getIndeterminateDrawable','nullable_actual_drawable_only':True,'code_units':size,'fields':names}
 raise AssertionError('ProgressBar getter not found')

def activity_reuse_method(raw):
 def pair(o):return struct.unpack_from('<II',raw,o)
 def ul(o):
  value=shift=0
  while True:
   b=raw[o];o+=1;value|=(b&127)<<shift;shift+=7
   if b<128:return value,o
 def string(o):
  _,o=ul(o);return raw[o:raw.index(0,o)].decode('utf8','replace')
 n,off=pair(0x38);strings=[string(struct.unpack_from('<I',raw,off+4*i)[0])for i in range(n)]
 n,off=pair(0x40);types=[strings[struct.unpack_from('<I',raw,off+4*i)[0]]for i in range(n)]
 n,off=pair(0x58);methods=[struct.unpack_from('<HHI',raw,off+8*i)for i in range(n)]
 n,off=pair(0x60)
 for i in range(n):
  row=struct.unpack_from('<8I',raw,off+32*i)
  if types[row[0]]!='Lhusk/AppRunner;':continue
  o=row[6];sf,o=ul(o);nf,o=ul(o);dm,o=ul(o);vm,o=ul(o)
  for _ in range(sf+nf):_,o=ul(o);_,o=ul(o)
  for count in [dm,vm]:
   index=0
   for _ in range(count):
    delta,o=ul(o);index+=delta;flags,o=ul(o);code,o=ul(o)
    if strings[methods[index][2]]!='reuseUniqueActivity':continue
    assert code and flags&8
    size=struct.unpack_from('<I',raw,code+12)[0];assert size>50,size
    return {'class':'husk/AppRunner','method':'reuseUniqueActivity','static':True,'code_units':size,'code_sha256':hashlib.sha256(raw[code+16:code+16+2*size]).hexdigest()}
 raise AssertionError('AppRunner unique-activity method missing')

with zipfile.ZipFile(ipa)as z:
 assert z.testzip()is None
 app='Payload/Husk.app/'
 info=plistlib.loads(z.read(app+'Info.plist'));result['info']={k:info.get(k)for k in ['CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion','MinimumOSVersion','HuskBuildCommit','HuskBuildDate']}
 source=Path('/tmp/husk166-package-source.txt').read_text().strip()
 assert info['HuskBuildCommit']in[source,source+'-dirty'],info
 assert info['CFBundleIdentifier']=='com.husk.app'
 assert info['CFBundleShortVersionString']=='3.4'and info['CFBundleVersion']=='166'
 executable=z.read(app+'Husk');assert macho(executable)['code_signature_bytes']>0
 assert b'HuskWebPending' in executable
 assert b'HuskDownload' in executable
 assert b'java runtime bundle: Husk build' in executable
 assert b'tl_javaapp_web_events' in executable
 result['retained_native_components']={'typed_pending_class_present':True,'coalesced_notification_symbol_present':True,'streaming_download_class_present':True}
 symbols_main=macho(executable)['symbols']
 for symbol in ['_husk_metal4_preflight','_tl_host_cpu_topology','_tl_pc_prepare_mesa_disk_cache','_tl_vk_is_metal4']:
  assert symbol in symbols_main,symbol
 for marker in [b'[NX18-HENGE-A20-v1] Metal 4 admission:',b'worker topology:',b'hw.perflevel0.logicalcpu',b'hw.perflevel1.logicalcpu',b'newMTL4CommandQueueWithDescriptor:',b'newArgumentTableWithDescriptor:']:
  assert marker in executable,marker
 # Verify the actual new Darwin signal table in the executable, not just a source marker.
 guest_to_host=[0,1,2,3,4,5,6,10,8,9,30,11,31,13,14,15,-1,20,19,17,18,21,22,16,24,25,26,27,28,23,29,12,0,0,7]+[0]*30
 assert len(guest_to_host)==65
 signal_table=struct.pack('<65i',*guest_to_host)
 assert signal_table in executable,'compiled signal34 to SIGEMT mapping absent'
 result['socket_close_signal_mapping']={'actual_compiled_table_present':True,'guest_signal':34,'darwin_signal':7,'ordinary_signal_mapping_preserved':True}
 for marker in [b'huskapp://android_asset/',b'huskapp://android_res/',b'[M4/M9 pacing-wait]',b'render fps',b'output waiting']:
  assert marker in executable,marker
 result['retained163_native_markers']={'virtual_android_assets':True,'render_output_readout':True,'bounded_pacing_wait_report':True}
 result['retained162_native_components']={'topology_function':True,'metal4_admission_function':True,'runtime_sysctl_keys':True,'real_metal4_object_calls':True,'source':'503f5cbef4d48e64828043fe057fd976928e0dc0'}
 with zipfile.ZipFile('/workspace/Husk-3.4-build160-AnkiDroid.ipa') as previous160:
  assert executable!=previous160.read(app+'Husk')
 for marker in [b'husk-pipeline-cache-metal4-v1',b'husk-metal4-shader-cache-v1',b'awaiting Vulkan cache API from a live instance',b'MESA_SHADER_CACHE_DIR',b'MESA_SHADER_CACHE_MAX_SIZE',b'128M']:
  assert marker in executable,marker
 result['candidate164_cache_native_symbols_and_markers']=True
 assert b'memory reserve:' in executable
 assert b'HuskMemoryCoordinator' in executable
 helper=app+'PlugIns/HuskMemoryDonor.appex/'
 helper_info=plistlib.loads(z.read(helper+'Info.plist'))
 assert helper_info['CFBundleIdentifier']=='com.husk.app.MemoryDonor',helper_info
 assert helper_info['NSExtension']['NSExtensionPrincipalClass']=='HuskMemoryDonorHandler'
 assert helper_info['XPCService']['_MultipleInstances'] is True
 helper_code=z.read(helper+helper_info['CFBundleExecutable'])
 assert macho(helper_code)['code_signature_bytes']>0
 assert b'HuskMemoryDonorHandler' in helper_code
 result['extensions']={}
 extdirs={n.split('/')[3]for n in z.namelist()if n.startswith(app+'PlugIns/')and '.appex/'in n}
 assert extdirs=={'HuskMemoryDonor.appex','HuskJITHelper.appex','HuskDownloadsWidget.appex'},extdirs
 for ext in sorted(extdirs):
  base=app+'PlugIns/'+ext+'/'
  meta=plistlib.loads(z.read(base+'Info.plist'))
  for key in ['CFBundleDisplayName','CFBundleIdentifier','CFBundleExecutable']:
   assert isinstance(meta.get(key),str)and meta[key].strip(),(ext,key)
  assert meta.get('NSExtension',{}).get('NSExtensionPointIdentifier'),ext
  assert macho(z.read(base+meta['CFBundleExecutable']))['code_signature_bytes']>0,ext
  result['extensions'][ext]={'display_name':meta['CFBundleDisplayName'],'identifier':meta['CFBundleIdentifier'],'arm64':True,'signature_present':True,'extension_point':meta['NSExtension']['NSExtensionPointIdentifier']}
 result['shared_memory_helper']={'embedded':True,'arm64':True,'signature_present':True,'principal_class':helper_info['NSExtension']['NSExtensionPrincipalClass']}
 for n in ['vmlinuz-virt','initramfs-virt','husk-jit.js','edk2-aarch64-code.fd','lineage-efi-vars-seed.fd','lineage-vdb-seed.qcow2','java-runtime/husk-framework.dex','Frameworks/libFilePickerFix.dylib','Frameworks/libqemu-aarch64-softmmu.dylib','Frameworks/libANGLE-shared.dylib','Frameworks/MoltenVK.framework/MoltenVK','Frameworks/HuskMoltenVK.framework/HuskMoltenVK']:
  assert len(z.read(app+n))>0,n
 result['donor_checks']={}
 with zipfile.ZipFile('/tmp/Husk-upstream-3.4.ipa')as donor,zipfile.ZipFile('/tmp/Husk-upstream-3.0.ipa')as baseline:
  for n in ['libqemu-aarch64-softmmu.dylib','libANGLE-shared.dylib','MoltenVK.framework/MoltenVK','libhuskps4.dylib','libFilePickerFix.dylib']:
   a=macho(z.read(app+'Frameworks/'+n));b=macho((baseline if n.startswith('libqemu')else donor).read(app+'Frameworks/'+n))
   assert a['sections']==b['sections']and a.get('uuid')==b.get('uuid'),n
   result['donor_checks'][n]='matching protected donor'if n.startswith('libqemu')else'matching3.4 donor'
  for n in ['java-runtime/framework-res.apk','default.metallib']:
   assert z.read(app+n)==donor.read(app+n),n
 driver=app+'Frameworks/HuskMoltenVK.framework/'
 manifest=json.loads(z.read(driver+'HuskSpatialBuild.json'));result['driver_manifest']=manifest
 assert manifest['native_archive_abi']==2 and manifest['native_archive_cache_schema']==2
 symbols=macho(z.read(driver+'HuskMoltenVK'))['symbols'];exports=sorted(n for n in symbols if n.startswith('_vkHusk'));result['driver_exports']=exports
 assert len(exports)==14,exports
 serialized=json.dumps(manifest)
 for identity in ['db66022459ffb663aa2b50f6b018bc2e124f5edf','6c09849fe88c48eaed08413aa022aaa136a3a057','a734100aa2a773b1e782c33b541593c02e7bba35aa28a5524ea30f2025202c50']:
  assert identity in serialized,identity

 assert 'M9-FLOW-FRAMEGEN-v1' in manifest['feature']
 for name in ['FramegenConfigure','FramegenSnapshot','FramegenPause']:
  assert '_vkHusk'+name in exports,name
 kk=app+'Frameworks/KosmicKrisp.framework/'
 kk_info=plistlib.loads(z.read(kk+'Info.plist'))
 assert kk_info['MinimumOSVersion']=='26.0'
 kk_manifest=json.loads(z.read(kk+'HuskMetal4Build.json'))
 assert kk_manifest['source']=='26620bf5319a0f5a5cca47cfecec797cafe45493'
 assert kk_manifest['binary_sha256']=='17bba1df31d4c8eb757ce2f56fdc1f8c6af92bc5427585e33673b0c60e8ba7de'
 kk_actual=macho(z.read(kk+'KosmicKrisp'))
 with zipfile.ZipFile('/tmp/Playport-0.5.0.ipa')as upstream:
  kk_expected=macho(upstream.read('Payload/Playport.app/Frameworks/KosmicKrisp.framework/KosmicKrisp'))
 assert kk_actual['sections']==kk_expected['sections'] and kk_actual['uuid']==kk_expected['uuid']
 assert kk_actual['code_signature_bytes']>0
 assert '_vkGetInstanceProcAddr'in kk_actual['symbols']and'_vkGetDeviceProcAddr'in kk_actual['symbols']
 assert b'newMTL4CommandQueue'in z.read(kk+'KosmicKrisp')
 assert len(z.read(kk+'Licenses/Mesa-license.rst'))>0
 result['metal4_driver']={'sections_and_uuid_match_pinned_donor':True,'arm64':True,'signature_present':True,'minimum_ios':'26.0','full_notices_present':True,'manifest':kk_manifest}
 import importlib.util
 spec=importlib.util.spec_from_file_location('reuse',Path('/workspace/Husk/scripts/reuse_spatial_driver.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 patch_digest=hashlib.sha256()
 for name in module.INPUTS:patch_digest.update((Path('/workspace/Husk')/name).read_bytes())
 # Source-wide contract is checked only for the final current source, not an
 # earlier successful intermediate with the narrower motion shader.
 if source=='eacafb426fc73fcf02e9b07103dd4c7f342f3ddf':
  assert manifest['husk_spatial_patch_sha256']==patch_digest.hexdigest()
  shader=Path('/workspace/Husk/patches/metalfx/HuskFramegen.metal').read_bytes()
  assert shader in z.read(driver+'HuskMoltenVK')
  result['exact_framegen_shader_embedded']=True

 source_driver=app+'Frameworks/HuskKosmicKrisp.framework/'
 enhanced_info=plistlib.loads(z.read(source_driver+'Info.plist'))
 assert enhanced_info['MinimumOSVersion']=='26.0' and enhanced_info['CFBundleVersion']=='1',enhanced_info
 enhanced_manifest=json.loads(z.read(source_driver+'HuskMetal4Build.json'))
 for k,v in dict(schema=2,husk_bridge_abi=1,native_archive_abi=2,frame_generation=True,metalfx_spatial=False,source='26620bf5319a0f5a5cca47cfecec797cafe45493',mesa='b39d173ca9369c19fda2635be6655d308067e52d').items():
  assert enhanced_manifest[k]==v,(k,enhanced_manifest.get(k))
 assert enhanced_manifest['husk_source_at_compile']==source,enhanced_manifest
 actual_bytes=z.read(source_driver+'HuskKosmicKrisp');actual=macho(actual_bytes)
 assert actual['code_signature_bytes']>0 and actual['sections']['__TEXT,__text']==enhanced_manifest['code_sha256']
 exports=sorted(s for s in actual['symbols'] if s.startswith('_vkHusk'))
 expected=sorted('_vkHusk'+s for s in ['ArchiveConfigure','ArchiveSnapshot','ArchivePrepare','ArchiveForget','FramegenConfigure','FramegenSnapshot','FramegenPause','Metal4Checkpoint'])
 assert exports==expected,(exports,expected)
 assert '_vkGetInstanceProcAddr' in actual['symbols'] and '_vkGetDeviceProcAddr' in actual['symbols']
 for marker in [b'HuskMetal4Compiler',b'HuskMetal4FGDrawable',b'HuskMetal4FGPresenter',b'newCompilerWithDescriptor:',b'newArchiveWithURL:',b'serializeAsArchiveAndFlushToURL:',b'addFeedbackHandler:',b'addResidencySet:',b'husk-kk-native-v1']:
  assert marker in actual_bytes,marker
 assert Path('/workspace/Husk/patches/metalfx/HuskFramegen.metal').read_bytes() in actual_bytes
 spec=importlib.util.spec_from_file_location('metal4patch',Path('/workspace/Husk/scripts/prepare_metal4_source.py'));native_patch=importlib.util.module_from_spec(spec);spec.loader.exec_module(native_patch)
 native_digest=hashlib.sha256()
 for name in native_patch.INPUTS:native_digest.update(name.encode()+b'\0'+(Path('/workspace/Husk')/name).read_bytes()+b'\0')
 assert enhanced_manifest['patch_sha256']==native_digest.hexdigest(),enhanced_manifest
 license_names=[n for n in z.namelist() if n.startswith(source_driver+'Licenses/')]
 assert z.read(source_driver+'Licenses/Mesa-license.rst')
 assert len(license_names)>5,license_names
 assert b'Husk source bridge' in z.read(source_driver+'HuskSourceNotice.txt')
 original_notices={n[len(kk+'Licenses/'):]:z.read(n) for n in z.namelist() if n.startswith(kk+'Licenses/') and not n.endswith('/')}
 source_notices={n[len(source_driver+'Licenses/'):]:z.read(n) for n in license_names if not n.endswith('/')}
 assert original_notices==source_notices,'Source renderer notices differ from complete upstream companion set'
 notices_digest=hashlib.sha256()
 for name,raw in sorted(source_notices.items()):notices_digest.update(name.encode()+b'\0'+hashlib.sha256(raw).digest())

 for marker in [b'HuskKosmicKrisp.framework/HuskKosmicKrisp',b'tl_vk_archive_automatic',b'tl_thread_policy_render_target',b'Metal 4 Enhancements',b'husk-pipeline-cache-metal4-extended-v1']:
  assert marker in executable,marker
 with zipfile.ZipFile('/workspace/Husk-3.4-build165-Metal4-Complete.ipa')as old165:
  prior=json.loads(old165.read(source_driver+'HuskMetal4Build.json'))
  assert prior['patch_sha256']!=enhanced_manifest['patch_sha256'] and prior['code_sha256']!=enhanced_manifest['code_sha256']
  assert prior['compiler_contract']==enhanced_manifest['compiler_contract'],'Ownership-only repair must preserve native compiler semantics'
  for name in ['husk-framework.dex','husk-framework-core.dex','husk-framework-build.json']:
   assert z.read(app+'java-runtime/'+name)==old165.read(app+'java-runtime/'+name)
 result['candidate166_new_source_framework_and_retained165_java_verified']=True
 result['source_metal4_driver']={'manifest':enhanced_manifest,'arm64':True,'signature_present':True,'code_section_hash_verified':True,'bridge_exports':exports,'shader_exact':True,'notices_files':len(source_notices),'notices_match_complete_original_set':True,'notices_manifest_sha256':notices_digest.hexdigest(),'native_compiler_and_framegen_markers':True}
 receipt=json.loads(z.read(app+'java-runtime/husk-framework-build.json'))
 assert receipt['schema']==1 and receipt['r8']=='8.5.35' and receipt['min_api']==26
 assert receipt['regression']=='ProgressBarContract:10 checks'
 assert receipt['progressbar_source_sha256']==hashlib.sha256(Path('/workspace/Husk/src/java-framework/src/android/widget/ProgressBar.java').read_bytes()).hexdigest()
 for name, expected in receipt['files'].items():
  raw=z.read(app+'java-runtime/'+name)
  assert len(raw)==expected['bytes'] and hashlib.sha256(raw).hexdigest()==expected['sha256'],name
  expected['getter_bytecode']=progress_getter(raw)
  expected['unique_activity_bytecode']=activity_reuse_method(raw)
  import zlib
  assert raw[:4]==b'dex\n' and hashlib.sha1(raw[32:]).digest()==raw[12:32]
  assert zlib.adler32(raw[12:])&0xffffffff==struct.unpack_from('<I',raw,8)[0]
  with zipfile.ZipFile('/workspace/Husk-3.4-Duo-Metal4-Framegen.ipa')as previous:
   assert raw!=previous.read(app+'java-runtime/'+name),name
 assert receipt['storage_regression']=='StoragePathContract'
 assert receipt['anki_interactions']=='AnkiInteractionContract:14 checks'
 assert receipt['download_manager']=='DownloadManagerContract:16 checks'
 for name,expected in receipt['storage_sources'].items():
  assert hashlib.sha256((Path('/workspace/Husk')/name).read_bytes()).hexdigest()==expected,name
 for name in ['husk-framework.dex','husk-framework-core.dex']:
  raw=z.read(app+'java-runtime/'+name)
  assert b'Lhusk/StoragePaths;'in raw and b'rebaseOwnDataPath'in raw and b'.husk-prefs-new'in raw
 result['storage_sources_verified']=True
 for name in ['husk-framework.dex','husk-framework-core.dex']:
  raw=z.read(app+'java-runtime/'+name)
  for marker in [b'hostLoad',b'mSentSettings',b'huskComplete',b'downloadStart',b'Destination outside imported app data']:
   assert marker in raw,(name,marker)
 result['anki_page_download_dialog_markers']=True
 assert hashlib.sha256(z.read(app+'android-system/fonts/Roboto-Regular.ttf')).hexdigest()=='9e157d5ff70ae52cc8c527b36e89d9b3c69c6c814da79fa6237a0bf0895abc7c'
 with zipfile.ZipFile('/workspace/Husk-3.4-build159-AnkiDroid.ipa') as previous:
  for name,count in [('husk-framework.dex',5995),('husk-framework-core.dex',2132)]:
   raw=z.read(app+'java-runtime/'+name)
   assert raw!=previous.read(app+'java-runtime/'+name), 'new activity method absent: DEX unchanged'
   assert struct.unpack_from('<I',raw,0x60)[0]==count
 result['retained159_contracts_new_activity_dex_and_font_verified']=True
 with zipfile.ZipFile('/workspace/Husk-3.4-build163-Anki-Metal4.ipa') as previous163:
  for name in ['husk-framework.dex','husk-framework-core.dex','husk-framework-build.json']:
   assert z.read(app+'java-runtime/'+name)==previous163.read(app+'java-runtime/'+name),name
 result['java_unchanged_from_verified163']=True
 result['java_framework']=receipt
 result['ipa_crc']='pass';result['source']=source
Path('/tmp/husk166-package-verification.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items()if k not in ['driver_manifest','driver_exports']},indent=2))
