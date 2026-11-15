#!/usr/bin/env python3
"""Execute real public Metal prerequisites; unsupported GPUs must decline without submitting work."""
import platform,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
@unittest.skipUnless(platform.system()=='Darwin','Real Metal objects require the Apple build runner')
class Metal4AdmissionTests(unittest.TestCase):
 def test_real_device_admission_is_bounded_and_cached(self):
  code=r'''
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <assert.h>
#include <stdio.h>
#include "husk-tl-metal4-admission.h"
static int logs;
void tl_log_line(const char *s,...){(void)s;logs++;}
int main(void){@autoreleasepool{
 bool family=false;
#if (defined(__IPHONE_26_0) || defined(__MAC_26_0))
 if(@available(macOS 26.0,*))family=[MTLCreateSystemDefaultDevice() supportsFamily:MTLGPUFamilyMetal4];
#endif
 bool first=husk_metal4_preflight();assert(first==family);
 for(int i=0;i<100;i++)assert(husk_metal4_preflight()==first);
 assert(logs==1);
 printf("actual Metal4 object preflight: %s; one initialization, no GPU commands submitted\n",first?"admitted":"unsupported GPU declined");
 return 0;
}}
'''
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'main.m').write_text(code);exe=p/'test'
   r=subprocess.run(['clang','-fobjc-arc','-fblocks','-I',str(ROOT/'src/translation-layer-next'),str(ROOT/'src/translation-layer-next/husk-tl-metal4-admission.m'),str(p/'main.m'),'-framework','Metal','-framework','Foundation','-o',str(exe)],capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr)
   r=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);self.assertEqual(r.returncode,0,r.stdout+r.stderr);print(r.stdout.strip())
if __name__=='__main__':unittest.main(verbosity=2)
