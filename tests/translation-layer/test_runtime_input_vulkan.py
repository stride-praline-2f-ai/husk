#!/usr/bin/env python3
"""Production controller fast path and Vulkan dispatch, with host API facades."""
from pathlib import Path
import os,re,subprocess,tempfile,unittest,sys
from test_lifecycle_resilience import function
ROOT=Path(__file__).resolve().parents[2];TL=ROOT/'src/translation-layer-next'
class RuntimeTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.tmp.cleanup);p=Path(cls.tmp.name)
  pad=(TL/'husk-tl-gamepad.c').read_text();pad=pad[pad.index('#define MAX_AXES'):pad.index('/* ------------------------------------------------------------- InputDevice */')]
  (p/'pad.c').write_text(r'''
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "husk-tl-gamepad.h"
static unsigned clocks,downs,ups,motions;static int last_key;
static int counted_clock(clockid_t clock,struct timespec*t){clocks++;return clock_gettime(clock,t);}
#define clock_gettime counted_clock
void tl_log_line(const char *fmt,...){(void)fmt;}
static jobj event;
jobj *tl_input_key_event(int a,int k,int d,int s,int r,int64_t down,int64_t ms){(void)a;(void)k;(void)d;(void)s;(void)r;(void)down;(void)ms;return &event;}
jobj *tl_input_joystick_event(int d,int s,int64_t down,int64_t ms,const float*axes){(void)d;(void)s;(void)down;(void)ms;(void)axes;return &event;}
'''+pad+r'''
static void key(jobj*ev,int dev,int action,int code,int64_t down,int64_t ms){(void)ev;(void)dev;(void)down;(void)ms;last_key=code;if(action==0)downs++;else ups++;tl_pad_state copy;assert(tl_pad_read(0,&copy));}
static void motion(jobj*ev,int dev,int src,int64_t down,int64_t ms){(void)ev;(void)dev;(void)src;(void)down;(void)ms;motions++;}
int main(int argc,char**argv){assert(argc==2);tl_pad_sink sink={key,motion};tl_pad_connect(0,"fixture");tl_pad_set_sink(&sink);tl_pad_state state={0};
 if(!strcmp(argv[1],"fast")){
  state.buttons=1u<<TL_PAD_A;state.lx=.25f;tl_pad_update(0,&state);assert(downs==1&&motions==1);
  unsigned before=clocks;for(unsigned i=0;i<100000;i++)tl_pad_update(0,&state);assert(clocks==before&&downs==1&&motions==1);
  state.buttons=0;tl_pad_update(0,&state);assert(ups==1&&last_key==96);
 }else if(!strcmp(argv[1],"accumulate")){
  tl_pad_update(0,&state);motions=0;state.lx=.002f;tl_pad_update(0,&state);assert(!motions);tl_pad_update(0,&state);assert(!motions);state.lx=.004f;tl_pad_update(0,&state);assert(motions==1);
 }else if(!strcmp(argv[1],"sink")){
  tl_pad_set_sink(NULL);state.buttons=1u<<TL_PAD_A;state.lt=.6f;state.lx=.5f;tl_pad_update(0,&state);assert(!downs&&!motions);
  tl_pad_set_sink(&sink);tl_pad_update(0,&state);assert(downs==2&&motions==1);
  tl_pad_update(0,&state);assert(downs==2&&motions==1);
 }else if(!strcmp(argv[1],"trigger")){
  state.lt=.6f;tl_pad_update(0,&state);assert(downs==1&&last_key==104);state.lt=.4f;tl_pad_update(0,&state);assert(!ups);state.lt=.2f;tl_pad_update(0,&state);assert(ups==1);
 }else if(!strcmp(argv[1],"mapping")){
  setenv("TL_PAD_DPAD","both",1);state.buttons=1u<<TL_PAD_DPAD_RIGHT;tl_pad_update(0,&state);assert(downs==1&&P.axes[0][AXIS_HAT_X]==1);
  setenv("TL_PAD_DPAD","keys",1);tl_pad_set_sink(&sink);tl_pad_update(0,&state);assert(P.axes[0][AXIS_HAT_X]==0&&downs==2);
 }else if(!strcmp(argv[1],"neutral")){
  state.buttons=1u<<TL_PAD_A;state.lt=.6f;state.rx=1;tl_pad_update(0,&state);assert(downs==2);
  state=(tl_pad_state){0};tl_pad_update(0,&state);assert(ups==2&&P.axes[0][AXIS_RZ]==0);tl_pad_disconnect(0);assert(!tl_pad_connected(0)&&!tl_pad_read(0,&state));
 }else assert(0);
 assert(!tl_pad_connected(-1)&&!tl_pad_connected(TL_PADS)&&!tl_pad_read(0,NULL));return 0;
}
''')
  vk=(TL/'husk-tl-vulkan.m').read_text();table=vk[vk.index('static const struct { const char *name; void *fn; } k_over[]'):vk.index('static void *overridden(')]
  names=re.findall(r'\{ "[^"]+", (\w+) \}',table);query_names={'w_vkGetInstanceProcAddr','w_vkGetDeviceProcAddr'}
  declarations='\n'.join('static void '+name+'(void){}'for name in names if name not in query_names)
  source=r'''
#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
static int identification,inventory;static void host(void){}
static void *gdpa(void*d,const char*n){(void)d;(void)n;return(void*)host;}
static void *gipa(void*d,const char*n){(void)d;(void)n;return(void*)host;}
static struct{void *lib;void*(*gipa)(void*,const char*);}V={(void*)1,gipa};
static bool vk_ready(void){return true;}static bool tl_ri_active(void){return inventory;}
static void resolve_feature_hooks(void*i){(void)i;}
#define LOG(...) do{}while(0)
static void *lookup(void*l,const char*n){(void)l;return !strcmp(n,"vkGetDeviceProcAddr")?(void*)gdpa:(void*)host;}
#define dlsym lookup
#define vk_symbol(name) lookup(V.lib,name)
static void *w_vkGetInstanceProcAddr(void*,const char*);static void *w_vkGetDeviceProcAddr(void*,const char*);
'''+declarations+'\n'+table+'\n'+function(vk,'static void *overridden(')+'\n'+function(vk,'static void *w_vkGetInstanceProcAddr(void *instance, const char *name)\n{')+'\n'+function(vk,'static void *w_vkGetDeviceProcAddr(void *device, const char *name)\n{')+'\n'+function(vk,'void *tl_vk_resolve(')+r'''
int main(void){const char*pure[]={"vkCreateShaderModule","vkDestroyShaderModule","vkCreateSampler","vkDestroySampler","vkCreateDescriptorSetLayout","vkDestroyDescriptorSetLayout","vkCreatePipelineLayout","vkDestroyPipelineLayout","vkCreateRenderPass","vkCreateRenderPass2","vkCreateRenderPass2KHR","vkDestroyRenderPass","vkDestroyPipeline"};
 for(unsigned enabled=0;enabled<2;enabled++){identification=enabled;
  for(unsigned i=0;i<sizeof(pure)/sizeof(*pure);i++){
   void *a=w_vkGetInstanceProcAddr((void*)1,pure[i]),*b=w_vkGetDeviceProcAddr((void*)1,pure[i]),*c=tl_vk_resolve(pure[i]);
   assert(a==b&&b==c);assert(a!=(void*)host);
  }
 }
 identification=0;const char*functional[]={"vkCreateGraphicsPipelines","vkCreateComputePipelines","vkCreatePipelineCache","vkDestroyPipelineCache","vkMergePipelineCaches","vkGetDeviceQueue","vkQueueSubmit","vkQueuePresentKHR","vkAcquireNextImageKHR","vkDestroyDevice","vkCreateDevice","vkCmdBindVertexBuffers"};
 for(unsigned i=0;i<sizeof(functional)/sizeof(*functional);i++)assert(tl_vk_resolve(functional[i])!=(void*)host);
 inventory=0;assert(tl_vk_resolve("vkCmdBeginRenderPass")==host);inventory=1;assert(tl_vk_resolve("vkCmdBeginRenderPass")!=host);
 assert(!w_vkGetInstanceProcAddr(NULL,NULL)&&!w_vkGetDeviceProcAddr(NULL,NULL));
 return 0;}
'''
  (p/'vulkan.c').write_text(source);cls.pad=p/'pad';cls.vk=p/'vulkan'
  for name,exe in [('pad',cls.pad),('vulkan',cls.vk)]:subprocess.run([os.environ.get('CC','cc'),'-std=c11','-O2','-Wall','-Wextra','-Werror','-pthread','-I',str(TL),str(p/(name+'.c')),'-lm','-o',str(exe)],check=True)
 def case(self,name):subprocess.run([str(self.pad),name],check=True,timeout=5)
 def test_identical_updates_skip_timestamp_and_axis_work(self):self.case('fast')
 def test_small_axis_changes_accumulate_against_last_emitted_axes(self):self.case('accumulate')
 def test_initial_sink_receives_held_buttons_triggers_and_motion(self):self.case('sink')
 def test_trigger_hysteresis_is_preserved(self):self.case('trigger')
 def test_mapping_epoch_forces_correct_republication(self):self.case('mapping')
 def test_frontend_neutralisation_releases_buttons_and_axes_before_disconnect(self):self.case('neutral')
 def test_all_proc_lookup_paths_retain_compatible_wrappers(self):subprocess.run([str(self.vk)],check=True,timeout=5)

class ICDDispatchTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.tmp.cleanup);p=Path(cls.tmp.name)
  (p/'icd.c').write_text(r"""
#include <string.h>
static int command(void){return 42;}
void *vkGetInstanceProcAddr(void *instance,const char *name){
 if(!strcmp(name,"vkCreateInstance"))return(void*)command;
 if(instance&&!strcmp(name,"vkCreateBuffer"))return(void*)command;
 return 0;
}
""")
  (p/'dispatch.c').write_text(r"""
#include <assert.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include "husk-tl-vk-dispatch.h"
static tl_vkd_dispatch d=TL_VKD_INITIALIZER;
static void *query(void*unused){(void)unused;for(unsigned i=0;i<50000;i++){
 void *fn=tl_vkd_lookup(&d,"vkCreateBuffer");if(fn)assert(((int(*)(void))fn)()==42);
 assert(tl_vkd_lookup(&d,"vkNeverInventAnExtension")==0);
}return 0;}
int main(int argc,char **argv){assert(argc==3);d.library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);assert(d.library);d.symbol=dlsym;d.gipa=(tl_vkd_gipa)dlsym(d.library,"vkGetInstanceProcAddr");assert(d.gipa);
 assert(!dlsym(d.library,"vkCreateBuffer"));assert(!tl_vkd_lookup(&d,0));
 assert(((int(*)(void))tl_vkd_lookup(&d,"vkCreateInstance"))()==42);
 assert(!tl_vkd_lookup(&d,"vkCreateBuffer"));assert(!tl_vkd_add(&d,0));
 if(!strcmp(argv[2],"lifetime")){
  assert(tl_vkd_add(&d,(void*)1));assert(tl_vkd_add(&d,(void*)1));
  assert(((int(*)(void))tl_vkd_lookup(&d,"vkCreateBuffer"))()==42);
  tl_vkd_remove(&d,(void*)1);assert(!tl_vkd_lookup(&d,"vkCreateBuffer"));
  assert(tl_vkd_add(&d,(void*)2));assert(tl_vkd_lookup(&d,"vkCreateBuffer"));
 }else if(!strcmp(argv[2],"capacity")){
  for(uintptr_t i=1;i<=16;i++)assert(tl_vkd_add(&d,(void*)i));assert(!tl_vkd_add(&d,(void*)17));
  tl_vkd_remove(&d,(void*)8);assert(tl_vkd_add(&d,(void*)17));
 }else if(!strcmp(argv[2],"concurrency")){
  pthread_t threads[4];for(unsigned i=0;i<4;i++)assert(!pthread_create(&threads[i],0,query,0));
  for(unsigned i=0;i<10000;i++){assert(tl_vkd_add(&d,(void*)1));tl_vkd_remove(&d,(void*)1);}
  for(unsigned i=0;i<4;i++)pthread_join(threads[i],0);
 }else assert(0);
 dlclose(d.library);return 0;
}
""")
  cc=os.environ.get('CC','cc');cls.driver=p/('icd.dylib' if sys.platform=='darwin'else'icd.so');cls.exe=p/'dispatch'
  subprocess.run([cc,'-dynamiclib'if sys.platform=='darwin'else'-shared','-fPIC',str(p/'icd.c'),'-o',str(cls.driver)],check=True)
  subprocess.run([cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-pthread','-I',str(TL),str(p/'dispatch.c'),'-o',str(cls.exe)]+([]if sys.platform=='darwin'else['-ldl']),check=True)
 def run_case(self,case):subprocess.run([str(self.exe),str(self.driver),case],check=True,timeout=15)
 def test_icd_only_exports_and_probe_instance_destruction(self):self.run_case('lifetime')
 def test_instance_capacity_is_bounded_and_slots_reusable(self):self.run_case('capacity')
 def test_lookups_and_instance_retirement_do_not_race(self):self.run_case('concurrency')


class FramegenAdmissionTests(unittest.TestCase):
 def test_real_framegen_admission_changes_rendered_cap_only_after_driver_accepts(self):
  vk=(TL/'husk-tl-vulkan.m').read_text()
  # This is the pure C admission contract. Objective-C session identity and
  # file export live outside this slice and are checked by the app/codec gates.
  part='static bool framegen_requested;\nstatic char framegen_capture_directory[768];\n'+vk[vk.index('static atomic_bool framegen_paused;'):vk.index('static bool spatial_requested;')]
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);f=p/'fg.c';f.write_text(r"""
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
#include <string.h>
#include "husk-tl-framegen.h"
static struct{void*lib;}V={(void*)1};
static bool efficient=true,available=true,accept=true,model_ok=true;static int fps=60,paused=-1,calls,captures;
int tl_vk_framegen_capture_arm(const char *directory,uint32_t first,uint32_t stride,uint32_t pairs){assert(directory&&first==180&&stride==90&&pairs==1);captures++;return 1;}
static bool tl_ue4_efficiency_enabled(void){return efficient;}
static void husk_ue4_set_efficiency(bool e,int f){assert(e);fps=f;}
static void tl_log_line(const char*fmt,...){(void)fmt;}
static int configure(const tl_fg_config*c){calls++;assert(c->version==1&&c->size==sizeof(*c)&&c->width==1816&&c->height==1280);return accept;}
static void pause_driver(int p){paused=p;}
static bool tl_vk_require_framegen_contract(void *entry){assert(entry);return model_ok;}
static void*vk_symbol(const char*n){if(!available)return 0;if(!strcmp(n,"vkHuskFramegenConfigure"))return(void*)configure;if(!strcmp(n,"vkHuskFramegenPause"))return(void*)pause_driver;return 0;}
"""+part+r"""
static bool vk_ready(void){return available;}
int main(void){
 assert(!tl_vk_framegen_prepare("Dungeons",1816,1280)&&fps==60&&!calls);
 husk_ue4_set_frame_generation(true);assert(!tl_vk_framegen_prepare(0,1816,1280));assert(!tl_vk_framegen_prepare("Other",1816,1280));
 efficient=false;assert(!tl_vk_framegen_prepare("Dungeons",1816,1280));efficient=true;
 available=false;assert(!tl_vk_framegen_prepare("Dungeons",1816,1280)&&fps==60&&!calls);available=true;
 model_ok=false;assert(!tl_vk_framegen_prepare("Dungeons",1816,1280)&&fps==60&&!calls);model_ok=true;
 strcpy(framegen_capture_directory,"/pending-evidence");
 accept=false;assert(!tl_vk_framegen_prepare("Dungeons",1816,1280)&&fps==60&&calls==1);
 assert(!captures&&framegen_capture_directory[0]);
 tl_vk_framegen_pause(true);accept=true;assert(tl_vk_framegen_prepare("Dungeons",1816,1280)&&fps==30&&paused==1&&calls==2);
 assert(captures==1&&!framegen_capture_directory[0]);
 tl_vk_framegen_pause(false);assert(paused==0);
 tl_fg_stats stats;assert(!tl_vk_framegen_snapshot(&stats)&&stats.version==1&&stats.size==sizeof(stats)&&!stats.active);
 return 0;
}
""")
   subprocess.run([os.environ.get('CC','cc'),'-std=c11','-Wall','-Wextra','-Werror','-I',str(TL),str(f),'-o',str(p/'fg')],check=True)
   subprocess.run([str(p/'fg')],check=True)

if __name__=='__main__':unittest.main()
