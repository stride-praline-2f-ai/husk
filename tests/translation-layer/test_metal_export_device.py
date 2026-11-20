#!/usr/bin/env python3
"""Compile actual MoltenVK optional Metal-object device admission with fail-closed fallback."""
import ctypes
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class MetalExportDeviceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = (ROOT / "src/translation-layer-next/husk-tl-vulkan.m").read_text()
        begin = src.index("/* The game does not request VK_EXT_metal_objects itself.")
        end = src.index("static int w_vkCreateDevice(", begin)
        native = src[begin:end]
        assert "VK_EXT_metal_objects" in native
        assert "if(result!=VK_SUCCESS)" in native
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        folder = Path(cls.tmp.name)
        harness = r'''
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "husk-tl-pipeline-feedback.h"
typedef tl_pf_device_info vk_device_ci;
typedef tl_pf_create_fn pfn_create_device;
#define VK_SUCCESS 0
#define VK_ERROR_EXTENSION_NOT_PRESENT (-7)
static int metal4_backend;
static int active, offered, reject, calls, included, last_included;
static void tl_log_line(const char *msg, ...) {(void)msg;}
static bool tl_ri_active(void){return active!=0;}
static bool real_dev_ext(void *pd, const char *name) {
 (void)pd;
 return offered && !strcmp(name,"VK_EXT_metal_objects");
}
static int enum_ext(void*pd,const char*layer,uint32_t*n,tl_pf_extension*list){
 (void)pd;(void)layer;(void)n;(void)list;return 0;
}
static tl_pf_enum_fn g_real_enum_dev_ext=enum_ext;
static int fake_create(void*pd,const vk_device_ci*info,const void*a,void**out) {
 (void)pd;(void)a;
 calls++;last_included=0;
 for(unsigned i=0;i<info->extCount;i++)
  if(!strcmp(info->exts[i],"VK_EXT_metal_objects"))last_included=1;
 included+=last_included;
 if(reject&&last_included)return reject==2 ? -8 : VK_ERROR_EXTENSION_NOT_PRESENT;
 *out=(void *)123;return 0;
}
static pfn_create_device g_real_create_device=fake_create;
''' + native + r'''
int try_device(int mode){
 metal4_backend=0;active=mode!=0;offered=mode!=2;reject=mode==3 ? 1 : mode==4 ? 2 : 0;
 calls=included=last_included=0;
 const char *names[]={"VK_KHR_swapchain"};
 vk_device_ci ci={0};ci.extCount=1;ci.exts=names;void *created=NULL;
 int result=create_with_optional_metal_export((void *)1,&ci,NULL,&created);
 if(result!=0||created!=(void *)123||ci.extCount!=1||strcmp(ci.exts[0],"VK_KHR_swapchain"))return 1;
 if(mode==0||mode==2){if(calls!=1||included!=0||last_included)return 2;}
 if(mode==1){if(calls!=1||included!=1||!last_included)return 3;}
 if(mode==3||mode==4){if(calls!=2||included!=1||last_included)return 4;}
 return 0;
}
int guest_requested(void){
 active=offered=1;reject=0;calls=included=0;metal4_backend=0;
 const char *names[]={"VK_KHR_swapchain","VK_EXT_metal_objects"};
 vk_device_ci ci={0};ci.extCount=2;ci.exts=names;void*out=NULL;
 int r=create_with_optional_metal_export((void*)1,&ci,NULL,&out);
 return (r||calls!=1||included!=1||ci.extCount!=2)?1:0;
}
'''
        (folder/"check.c").write_text(harness)
        subprocess.run([os.environ.get("CC","cc"),"-std=c11","-Wall","-Wextra","-Werror",
                        "-shared","-fPIC","-pthread","-I",str(ROOT/"src/translation-layer-next"),
                        str(folder/"check.c"),"-o",str(folder/"check.so")],check=True)
        cls.lib=ctypes.CDLL(str(folder/"check.so"))
        cls.lib.try_device.argtypes=[ctypes.c_int]

    def test_disabled_and_unsupported_do_not_change_guest_extensions(self):
        self.assertEqual(self.lib.try_device(0),0)
        self.assertEqual(self.lib.try_device(2),0)

    def test_supported_extension_added_without_modifying_guest_request(self):
        self.assertEqual(self.lib.try_device(1),0)

    def test_any_optional_extension_failure_retries_original_once(self):
        self.assertEqual(self.lib.try_device(3),0)
        self.assertEqual(self.lib.try_device(4),0)

    def test_guest_requested_extension_is_not_duplicated(self):
        self.assertEqual(self.lib.guest_requested(),0)

if __name__=="__main__":
    unittest.main()
