#!/usr/bin/env python3
"""Actual Vulkan wrappers and bounded observer: forwarding, opt-in and scope."""
import ctypes, os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class RenderInventoryTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.tmp.cleanup);p=Path(cls.tmp.name)
  src=(ROOT/'src/translation-layer-next/husk-tl-vulkan.m').read_text()
  wrappers=src[src.index('static int w_vkCreateImage('):src.index('typedef int (*pfn_create_swapchain)')]
  lookup=src[src.index('static void *overridden('):src.index('static void *w_vkGetInstanceProcAddr(void *instance, const char *name)\n{')]
  harness=r'''
#include "husk-tl-render-inventory.c"
#define VK_SUCCESS 0
static struct{void *lib;}V={(void *)1};
static int status,calls,begins,errors;
static const void *expected;
static int image(void*d,const void*ci,const void*a,uint64_t*out){calls++;if(d!=(void *)7||a!=(void *)11||ci!=expected)errors++;*out=17;return status;}
static void begin(void*c,const void*ci,uint32_t contents){begins++;if(c!=(void *)19||ci!=expected||contents!=2)errors++;}
static void *get(void*lib,const char*name){(void)lib;if(!strcmp(name,"vkCreateImage"))return(void *)image;if(!strcmp(name,"vkCmdBeginRenderPass"))return(void *)begin;return NULL;}
#define dlsym get
#define vk_symbol(name) get(V.lib,name)
'''+wrappers+r'''
static const struct{const char*name;void*fn;}k_over[]={{"vkCreateImage",w_vkCreateImage},{"vkCmdBeginRenderPass",w_vkCmdBeginRenderPass}};
'''+lookup+r'''
int exercise(int mode){
 husk_ue4_set_render_inventory(mode!=0);tl_ri_activate(mode==2?"Other":"Dungeons");status=calls=begins=errors=0;
 image_info ci={.type=14,.width=1784,.height=1336,.depth=1,.format=44,.usage=0x14,.samples=1},copy=ci;uint64_t out=0;
 if(mode==0||mode==2){if(overridden("vkCreateImage")||overridden("vkCmdBeginRenderPass"))return 1;expected=(void *)1;if(w_vkCreateImage((void *)7,expected,(void *)11,&out)||out!=17)return 2;}
 else {
  if(overridden("vkCreateImage")!=(void *)w_vkCreateImage)return 3;
  expected=&ci;if(w_vkCreateImage((void *)7,&ci,(void *)11,&out)||memcmp(&ci,&copy,sizeof(ci))||out!=17)return 4;
  status=-4;if(w_vkCreateImage((void *)7,&ci,(void *)11,&out)!=-4)return 5;
  begin_info b={.type=43,.x=5,.y=7,.width=1784,.height=1336},original=b;expected=&b;
  w_vkCmdBeginRenderPass((void *)19,&b,2);w_vkCmdBeginRenderPass((void *)19,&b,2);
  if(memcmp(&b,&original,sizeof(b)))return 6;
 }
 tl_ri_group g[256];tl_ri_stats s;uint32_t n=tl_ri_snapshot(g,256,&s);
 if(errors)return 7;
 if(mode==0||mode==2)return n||s.active||s.observed_images||s.observed_render_areas;
 if(n!=2||s.observed_images!=1||s.observed_render_areas!=2||g[0].width!=1784||g[1].count!=2)return 8;
 return 0;
}
int bounded(void){husk_ue4_set_render_inventory(true);tl_ri_activate("Dungeons");image_info p={.type=14,.height=100,.depth=1};for(unsigned i=1;i<=300;i++){p.width=i;tl_ri_image(&p);}tl_ri_stats s;tl_ri_group g[256];return tl_ri_snapshot(g,256,&s)==64&&s.asset_groups==64&&s.dropped_capacity==236&&s.dropped==236&&s.observed_images==300?0:1;}
int contended(void){husk_ue4_set_render_inventory(true);tl_ri_activate("Dungeons");image_info p={.type=14,.width=100,.height=100};pthread_mutex_lock(&mu);tl_ri_image(&p);pthread_mutex_unlock(&mu);tl_ri_stats s;tl_ri_snapshot(NULL,0,&s);return s.dropped==1&&s.dropped_contention==1&&s.observed_images==1?0:1;}
int reserved(void){
 husk_ue4_set_render_inventory(true);tl_ri_activate("Dungeons");
 image_info p={.type=14,.height=100,.depth=1};
 for(unsigned i=1;i<=300;i++){p.width=i;tl_ri_image(&p);}
 p.width=1696;p.height=1280;p.usage=0x10;tl_ri_image(&p);tl_ri_image(&p);
 begin_info b={.type=43,.width=1696,.height=1280};tl_ri_render_area(&b);
 tl_ri_stats s;tl_ri_group g[256];unsigned n=tl_ri_snapshot(g,256,&s);
 if(n!=66||s.target_groups!=1||s.area_groups!=1||g[64].count!=2||g[65].width!=1696)return 1;
 if(s.hash_probes>4000||s.observed_images!=302||s.observed_render_areas!=1)return 2;
 return 0;
}

int framegen_candidates(void){
 tl_ri_metalfx_candidates v={0};
 husk_ue4_set_render_inventory(false);tl_ri_activate("Dungeons");
 tl_ri_metalfx_snapshot(&v);
 if(v.version!=1||v.size!=sizeof(v)||v.active||v.readable_depth_groups||v.writable_vector_groups)return 1;
 husk_ue4_set_render_inventory(true);tl_ri_activate("Dungeons");
 image_info p={.type=14,.width=1088,.height=768,.depth=1,.samples=1,.format=126,.usage=0x24};
 tl_ri_image(&p);tl_ri_image(&p); /* same depth group */
 p.format=83;p.usage=0x14;tl_ri_image(&p); /* motion-like RG16F, not verified motion */
 p.format=44;p.usage=0x14;tl_ri_image(&p); /* ordinary colour */
 p.format=127;p.usage=0x24;tl_ri_image(&p); /* stencil-only: not depth */
 p.format=103;p.usage=0x10;tl_ri_image(&p); /* unsampleable motion-like format */
 tl_ri_metalfx_snapshot(&v);
 if(!v.active||v.depth_attachment_groups!=1||v.readable_depth_groups!=1)return 2;
 if(v.vector_format_groups!=2||v.writable_vector_groups!=1)return 3;
 if(v.renderable_color_groups!=3||v.readable_color_groups!=2)return 4;
 if(v.retained_image_groups!=5||v.lost_observations!=0)return 5;
 tl_ri_activate("Other");tl_ri_metalfx_snapshot(&v);
 if(v.active||v.retained_image_groups||v.readable_depth_groups||v.writable_vector_groups)return 6;
 return 0;
}

'''
  (p/'test.c').write_text(harness);subprocess.run([os.environ.get('CC','cc'),'-std=c11','-Wall','-Wextra','-Werror','-shared','-fPIC','-pthread','-I',str(ROOT/'src/translation-layer-next'),str(p/'test.c'),'-o',str(p/'test.so')],check=True);cls.lib=ctypes.CDLL(str(p/'test.so'))
 def test_disabled_lookup_does_not_interpose_or_read_input(self):self.assertEqual(self.lib.exercise(0),0)
 def test_success_failure_and_command_arguments_preserved(self):self.assertEqual(self.lib.exercise(1),0)
 def test_only_exact_dungeons_project_activates(self):self.assertEqual(self.lib.exercise(2),0)
 def test_registry_capacity_and_loss_are_disclosed(self):self.assertEqual(self.lib.bounded(),0)
 def test_assets_cannot_starve_targets_or_areas_and_existing_counts_survive(self):self.assertEqual(self.lib.reserved(),0)
 def test_render_thread_never_waits_for_diagnostic_mutex(self):self.assertEqual(self.lib.contended(),0)
 def test_native_metalfx_candidates_are_only_bounded_requested_metadata(self):self.assertEqual(self.lib.framegen_candidates(),0)
if __name__=='__main__':unittest.main()
