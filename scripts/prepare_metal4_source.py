#!/usr/bin/env python3
"""Apply Husk's typed bridge to the exact Playport-patched Mesa source.

Every structural edit is checked. A changed patch contract requires a fresh
dedicated source tree; never guess offsets or reuse an earlier patched tree.
"""
from pathlib import Path
import hashlib,json,shutil,sys
ROOT=Path(__file__).resolve().parents[1]
INPUTS=['patches/metal4/HuskMetal4Bridge.h','patches/metal4/HuskMetal4Framegen.mm',
        'patches/metal4/HuskMetal4Compiler.mm','patches/metalfx/HuskFramegen.inc',
        'patches/metalfx/HuskFramegen.metal','src/translation-layer-next/husk-tl-framegen.h',
        'src/translation-layer-next/husk-tl-native-archive.h','scripts/prepare_metal4_source.py']
def framegen_include():
    inc=(ROOT/'patches/metalfx/HuskFramegen.inc').read_text().replace('#if TARGET_OS_IOS','#if TARGET_OS_IOS || defined(HUSK_FG_METAL4)',1)
    # The same real GPU algorithm can be exercised by native Mac regression
    # hosts; only the platform display-link factory and memory admission differ.
    inc=inc.replace('    if(os_proc_available_memory() < (384ULL<<20)){[self release];return nil;}', '#if TARGET_OS_IOS\n    if(os_proc_available_memory() < (384ULL<<20)){[self release];return nil;}\n#endif')
    inc=inc.replace('        _link=[[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];', '#if TARGET_OS_IOS\n        _link=[[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];\n#else\n        _link=[[[NSScreen mainScreen] displayLinkWithTarget:self selector:@selector(tick:)] retain];\n#endif')
    return inc

def prepare(mesa):
    digest=hashlib.sha256()
    for name in INPUTS:digest.update(name.encode()+b'\0'+(ROOT/name).read_bytes()+b'\0')
    contract=digest.hexdigest();marker=mesa/'HuskMetal4Patch.json'
    if marker.exists():
        recorded=json.loads(marker.read_text())
        if recorded['patch_sha256']!=contract:raise ValueError('Changed Metal4 patch: use a fresh source tree')
        for name,sha in recorded['generated_files'].items():
            if hashlib.sha256((mesa/name).read_bytes()).hexdigest()!=sha:raise ValueError('Generated source changed: '+name)
        return
    changed={}
    def edit(path,old,new,count=1):
        p=mesa/path;s=changed.get(p,p.read_text())
        if s.count(old)!=count:raise ValueError(f'Unexpected pinned source: {path}: wanted {count} anchors, got {s.count(old)}')
        changed[p]=s.replace(old,new)
    bridge='src/kosmickrisp/bridge/'
    edit('meson.build',"add_languages('objc', native : false)","add_languages('objc', 'objcpp', native : false)")
    edit(bridge+'meson.build',"    'mtl_compiler.m',","    'mtl_compiler.m',\n    'HuskMetal4Compiler.mm',\n    'HuskMetal4Framegen.mm',")
    edit(bridge+'meson.build',"    'stubs/mtl_compiler.c',","    'stubs/mtl_compiler.c',\n    'stubs/HuskMetal4Bridge.c',")
    edit(bridge+'mtl_compiler.m','#include "mtl_compiler.h"','#include "mtl_compiler.h"\nextern void *husk_metal4_new_compiler(void *device);')
    p=mesa/(bridge+'mtl_compiler.m');s=changed[p]
    start=s.index('mtl_compiler *\nmtl_new_compiler(');end=s.index('/* Library */',start)
    changed[p]=s[:start]+'''mtl_compiler *
mtl_new_compiler(mtl_device *device)
{
   return husk_metal4_new_compiler(device);
}

'''+s[end:]
    edit(bridge+'mtl_command_queue.m','#include "mtl_command_queue.h"','#include "mtl_command_queue.h"\n#include "HuskMetal4Bridge.h"')
    edit(bridge+'mtl_command_queue.m','      [q waitForDrawable:d];','      if (!husk_metal4_framegen_wait(queue, drawable)) [q waitForDrawable:d];')
    edit(bridge+'mtl_command_queue.m','      [q signalDrawable:d];','      if (!husk_metal4_framegen_signal(drawable)) [q signalDrawable:d];')
    q='src/kosmickrisp/vulkan/kk_queue.c'
    edit(q,'#include "kk_queue.h"','#include "kk_queue.h"\n#include "../bridge/HuskMetal4Bridge.h"')
    edit(q,'mtl_feedback_handler_callback callback, void *user_data)','mtl_feedback_handler_callback callback, void *user_data, void *drawable)')
    edit(q,'   mtl_commit_options_add_feedback_handler(options, callback, user_data);','   mtl_commit_options_add_feedback_handler(options, callback, user_data);\n   husk_metal4_framegen_feedback(options, drawable);')
    edit(q,'kk_queue_commit(queue, rerecord, rerecord_commit_callback, commit);','kk_queue_commit(queue, rerecord, rerecord_commit_callback, commit, cmd->drawable);')
    edit(q,'kk_queue_commit(queue, cmd_buffer, retire_commit_callback, retire);','kk_queue_commit(queue, cmd_buffer, retire_commit_callback, retire, cmd_buffer->drawable);')
    edit(q,'kk_queue_commit(queue, cmd_buffer, commit_callback, dev);','kk_queue_commit(queue, cmd_buffer, commit_callback, dev, cmd_buffer->drawable);')
    wsi='src/vulkan/wsi/wsi_common_metal.c'
    edit(wsi,'struct wsi_metal_swapchain {','\n#include "../../kosmickrisp/bridge/HuskMetal4Bridge.h"\nstruct wsi_metal_swapchain {')
    edit(wsi,'   struct wsi_swapchain base;','   struct wsi_swapchain base;\n   void *husk_framegen;')
    edit(wsi,'CAMetalDrawable *drawable = wsi_metal_layer_acquire_drawable(layer);','CAMetalDrawable *drawable = chain->husk_framegen && !chain->offscreen\n         ? husk_metal4_framegen_drawable(chain->husk_framegen, (void *)layer)\n         : wsi_metal_layer_acquire_drawable(layer);')
    edit(wsi,'   const bool framebuffer_only = !wsi_device->sw;','   const bool framebuffer_only = !wsi_device->sw && !husk_metal4_framegen_requested();')
    edit(wsi,'   *swapchain_out = &chain->base;','   if (!is_sw_driver && wsi_metal_surface_shown(metal_surface) && husk_metal4_framegen_requested())\n      chain->husk_framegen = husk_metal4_framegen_new((void *)metal_surface->pLayer);\n\n   *swapchain_out = &chain->base;')
    # Restrict the destruction anchor to this function; other loops also walk images.
    p=mesa/wsi;s=changed[p];start=s.index('wsi_metal_swapchain_destroy(');pos=s.index('   for (uint32_t i = 0;',start)
    changed[p]=s[:pos]+'   husk_metal4_framegen_delete(chain->husk_framegen);\n   chain->husk_framegen = NULL;\n\n'+s[pos:]
    # Write only after every pinned structural precondition passed.
    for p,s in changed.items():p.write_text(s)
    out=mesa/bridge
    for name in ['HuskMetal4Bridge.h','HuskMetal4Framegen.mm','HuskMetal4Compiler.mm']:shutil.copy2(ROOT/'patches/metal4'/name,out/name)
    shutil.copy2(ROOT/'src/translation-layer-next/husk-tl-framegen.h',out/'HuskFramegenABI.h')
    shutil.copy2(ROOT/'src/translation-layer-next/husk-tl-native-archive.h',out/'HuskNativeArchiveABI.h')
    inc=framegen_include()
    (out/'HuskFramegen.inc').write_text(inc)
    shader=(ROOT/'patches/metalfx/HuskFramegen.metal').read_text()
    (out/'HuskFramegenShader.inc').write_text('static const char *huskFramegenShader=R"HUSKFG('+shader+')HUSKFG";\n')
    (out/'stubs/HuskMetal4Bridge.c').write_text('''#include "../HuskMetal4Bridge.h"
bool husk_metal4_framegen_requested(void){return false;}
void *husk_metal4_framegen_new(void *p){(void)p;return 0;}
void husk_metal4_framegen_delete(void *p){(void)p;}
void *husk_metal4_framegen_drawable(void *p,void *l){(void)p;(void)l;return 0;}
bool husk_metal4_framegen_wait(void *q,void *d){(void)q;(void)d;return false;}
bool husk_metal4_framegen_signal(void *d){(void)d;return false;}
void husk_metal4_framegen_feedback(void *o,void *d){(void)o;(void)d;}
''')
    outputs=list(changed)+[out/n for n in ['HuskMetal4Bridge.h','HuskMetal4Framegen.mm','HuskMetal4Compiler.mm','HuskFramegenABI.h','HuskNativeArchiveABI.h','HuskFramegen.inc','HuskFramegenShader.inc','stubs/HuskMetal4Bridge.c']]
    generated={str(p.relative_to(mesa)):hashlib.sha256(p.read_bytes()).hexdigest()for p in outputs}
    marker.write_text(json.dumps({'schema':1,'patch_sha256':contract,'native_archive_abi':2,'framegen_abi':1,'mesa':'b39d173ca9369c19fda2635be6655d308067e52d','playport':'26620bf5319a0f5a5cca47cfecec797cafe45493','generated_files':generated},indent=2)+'\n')
if __name__=='__main__':prepare(Path(sys.argv[1]))
