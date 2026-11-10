#!/usr/bin/env python3
"""Actual adapted JNI lookup/registration and libUE4 math binding regressions."""
from pathlib import Path
import subprocess,tempfile,unittest,re
import shutil
ROOT=Path(__file__).resolve().parents[2];TL=ROOT/'src/translation-layer-next'
class UpstreamNativeTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.tmp.cleanup);p=Path(cls.tmp.name)
  jni=(TL/'husk-tl-jni.c').read_text();jni=jni[jni.index('typedef struct { const char *name, *sig; void *fn; } native_method;'):jni.index('void dvm_monitor_enter')]
  dvm=(TL/'husk-tl-dvm.c').read_text();dvm=dvm[dvm.index('static void mangle('):dvm.index('/* A call into a JNI function')]
  math=(TL/'husk-tl-bionic-str.c').read_text();methods='\n'.join(re.findall(r'^static int (?:b_isnan|b___isnanf)\([^\n]+',math,re.M))
  entries=[]
  for name in ['isnan','__isnan','isnanf','__isnanf']:
   match=re.search(r'TL_WRAP\("'+name+r'",\s*(\w+)\)',math);assert match,name
   entries.append('{"'+name+'",(void*)'+match.group(1)+'}')
  (p/'main.c').write_text(r'''
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <math.h>
#include "husk-tl-jni-internal.h"
typedef jobj *jo;
static pthread_mutex_t g_lock=PTHREAD_MUTEX_INITIALIZER;
static tl_jclass cls={.name="Example"};
tl_jclass *tl_jni_class(const char *name){assert(!strcmp(name,cls.name));return &cls;}
bool tl_dvm_declares(tl_jclass *c,const char *name,const char *sig){(void)c;(void)name;(void)sig;return true;}
#define TRACE(...) ((void)0)
static void tl_log_line(const char *fmt,...){(void)fmt;}
static unsigned symbol_queries;static void *exported;
static void *tl_ld_sym(void *library,const char *name){(void)library;(void)name;symbol_queries++;return exported;}
typedef struct{tl_jclass *cls;const char *name,*sig;void *jni;bool jni_looked;unsigned jni_gen;}dvm_method;
'''+jni+dvm+methods+'\nstatic struct{const char*name;void*fn;}math_entries[]={'+','.join(entries)+r'''};
static int first(void){return 1;}static int second(void){return 2;}
int main(int argc,char**argv){assert(argc==2);jobj object={.kind=TL_K_CLASS};object.klass.jc=&cls;dvm_method m={.cls=&cls,.name="run",.sig="()I"};
 if(!strcmp(argv[1],"late")){
  assert(!find_jni(&m));native_method methods[]={ {"run","()I",(void*)first} };unsigned old=tl_jni_natives_generation();assert(!jni_RegisterNatives(NULL,&object,methods,1));assert(tl_jni_natives_generation()!=old);assert(find_jni(&m)==(void*)first);
 }else if(!strcmp(argv[1],"replace")){
  native_method methods[]={ {"run","()I",(void*)first} };assert(!jni_RegisterNatives(NULL,&object,methods,1));assert(find_jni(&m)==(void*)first);methods[0].fn=(void*)second;assert(!jni_RegisterNatives(NULL,&object,methods,1));assert(find_jni(&m)==(void*)second);
 }else if(!strcmp(argv[1],"hit")){
  exported=(void*)first;assert(find_jni(&m)==exported);unsigned before=symbol_queries;assert(find_jni(&m)==exported&&symbol_queries==before);
 }else if(!strcmp(argv[1],"new-export")){
  assert(!find_jni(&m));exported=(void*)second;assert(find_jni(&m)==exported);
 }else if(!strcmp(argv[1],"invalid")){
  native_method methods[]={ {"run","()I",(void*)first} };unsigned before=tl_jni_natives_generation();assert(jni_RegisterNatives(NULL,NULL,methods,1)==-1&&tl_jni_natives_generation()==before);assert(jni_UnregisterNatives(NULL,NULL)==0);
 }else if(!strcmp(argv[1],"math")){
  for(unsigned i=0;i<4;i++){
   if(i<2){int(*f)(double)=math_entries[i].fn;assert(f(NAN)&&f(-NAN)&&!f(INFINITY)&&!f(-INFINITY)&&!f(0.0)&&!f(-0.0)&&!f(1e-300));}
   else{int(*f)(float)=math_entries[i].fn;assert(f(NAN)&&!f(INFINITY)&&!f(0.f)&&!f(-0.f));}
  }
 }else assert(0);
 for(int i=0;i<cls.nnatives;i++){free(cls.natives[i].name);free(cls.natives[i].sig);}free(cls.natives);
 return 0;
}
''')
  cls.exe=p/'check';subprocess.run(['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-pthread','-I',str(TL),str(p/'main.c'),'-lm','-o',str(cls.exe)],check=True)
 def case(self,name):subprocess.run([str(self.exe),name],check=True)
 def test_first_miss_does_not_hide_later_registered_native(self):self.case('late')
 def test_later_registration_replaces_cached_function(self):self.case('replace')
 def test_unchanged_successful_lookup_keeps_fast_cache(self):self.case('hit')
 def test_miss_is_retried_after_library_symbols_become_available(self):self.case('new-export')
 def test_failed_registration_does_not_publish_generation(self):self.case('invalid')
 def test_actual_symbol_bindings_classify_double_float_nan_and_finite_values(self):self.case('math')

def extracted(text, signature):
 start=text.index(signature); at=text.index('{',start); depth=1; end=at+1
 while depth:
  depth+=(text[end]=='{')-(text[end]=='}');end+=1
 return text[start:end]

class MemoryResilienceTests(unittest.TestCase):
 def compile_run(self,source,modules=(),args=()):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'test.c').write_text(source)
   subprocess.run(['cc','-std=c11','-D_DEFAULT_SOURCE','-Wall','-Wextra','-Werror','-pthread','-I',str(TL),str(p/'test.c'),*[str(TL/x)for x in modules],'-o',str(p/'test')],check=True)
   subprocess.run([str(p/'test'),*args],check=True,timeout=20)

 def test_shared_arena_zero_reuse_partial_free_protection_and_concurrency(self):
  self.compile_run(r'''
#include "husk-tl-memory-reserve.h"
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <pthread.h>
static void *worker(void *unused){(void)unused;for(int i=0;i<400;i++){
 void *p=tl_memory_reserve_alloc(16384);assert(p);assert(!((unsigned char*)p)[0]);
 memset(p,0x55,16384);assert(tl_memory_reserve_release(p,16384));}return NULL;}
int main(void){
 size_t bytes=16*16384;void *base=mmap(NULL,bytes+16384,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);assert(base!=MAP_FAILED);
 uintptr_t aligned=((uintptr_t)base+16383)&~(uintptr_t)16383;
 assert(!tl_memory_reserve_alloc(1));assert(!tl_memory_reserve_install((void*)(aligned+1),bytes));
 assert(!tl_memory_reserve_install((void*)aligned,(size_t)-1));assert(tl_memory_reserve_install((void*)aligned,bytes));
 assert(!tl_memory_reserve_install((void*)aligned,bytes));
 assert(!tl_memory_reserve_alloc(0));assert(!tl_memory_reserve_alloc((size_t)-1));
 unsigned char *p=tl_memory_reserve_alloc(32768);assert(p==(void*)aligned);memset(p,0x7f,32768);
 assert(tl_memory_reserve_contains(p,32768));assert(!tl_memory_reserve_contains(p,(size_t)-1));
 assert(!tl_memory_reserve_release(p+1,16384));assert(!tl_memory_reserve_release(p,bytes+1));
 assert(tl_memory_reserve_release(p+16384,16384));
 unsigned char *q=tl_memory_reserve_alloc(16384);assert(q==p+16384);
 for(size_t i=0;i<16384;i++){assert(!q[i]);}assert(p[0]==0x7f);
 assert(!mprotect(q,16384,PROT_READ));assert(tl_memory_reserve_release(q,16384));
 q=tl_memory_reserve_alloc(16384);assert(q==p+16384);q[0]=1;
 assert(tl_memory_reserve_release(p,32768));
 assert(tl_memory_reserve_overlaps(p,1));assert(!tl_memory_reserve_overlaps(p-1,1));
 assert(tl_memory_reserve_overlaps(p-1,2));assert(!tl_memory_reserve_overlaps(p+bytes,1));
 assert(!tl_memory_reserve_replace(p,16384,PROT_EXEC));
 assert(tl_memory_reserve_replace(p,16384,PROT_READ|PROT_WRITE));assert(!p[0]);
 assert(tl_memory_reserve_release(p,16384));
 void *all=tl_memory_reserve_alloc(bytes);assert(all==p);assert(!tl_memory_reserve_alloc(1));
 assert(tl_memory_reserve_release(all,bytes));
 pthread_t threads[4];for(int i=0;i<4;i++)assert(!pthread_create(&threads[i],NULL,worker,NULL));
 for(int i=0;i<4;i++)pthread_join(threads[i],NULL);
 return 0;}
''',['husk-tl-memory-reserve.c'])

 def test_actual_memory_apis_share_current_bounded_headroom_and_preserve_errno(self):
  text=(TL/'husk-tl-bionic.c').read_text()
  functions=extracted(text,'void tl_bionic_memory_info(')+extracted(text,'static int bionic_sysinfo(')+extracted(text,'static long bionic_sysconf(')
  typedef=text[text.index('typedef struct { long uptime;'):text.index('void tl_bionic_memory_info(')]
  io=(TL/'husk-tl-bionic-io.c').read_text();proc=extracted(io,'    if (!strcmp(path, "/proc/meminfo"))')
  prefix=r'''
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
static uint64_t total=8ull<<30,available=500ull<<20;static int fail_sysctl;
static int sysctlbyname(const char *n,void *p,size_t *l,void *v,size_t z){(void)n;(void)l;(void)v;(void)z;if(fail_sysctl){errno=EIO;return -1;}memcpy(p,&total,8);return 0;}
static void tl_set_guest_errno(int n){(void)n;}
'''
  for ios in (0,1):
   platform=('#define TARGET_OS_IPHONE 1\nstatic uint64_t os_proc_available_memory(void){return available;}\n' if ios else r'''
#define TARGET_OS_IPHONE 0
typedef unsigned mach_msg_type_number_t;typedef unsigned long vm_size_t;typedef int mach_port_t;
typedef struct { uint64_t free_count; } vm_statistics64_data_t;typedef void *host_info64_t;
static int rights;
#define HOST_VM_INFO64_COUNT 1
#define HOST_VM_INFO64 1
#define KERN_SUCCESS 0
static int mach_host_self(void){rights++;return 7;}static int mach_task_self(void){return 1;}
static int mach_port_deallocate(int task,int port){assert(task==1&&port==7);rights--;return 0;}
static int host_statistics64(int h,int k,host_info64_t p,mach_msg_type_number_t*c){(void)h;(void)k;(void)c;((vm_statistics64_data_t*)p)->free_count=available/16384;return 0;}
static int host_page_size(int h,vm_size_t*p){(void)h;*p=16384;return 0;}
''')
   main=r'''
static const char *proc_memory(const char *path,char *buf,size_t n){PROC return NULL;}
int main(void){uint64_t t,a;errno=EDOM;tl_bionic_memory_info(&t,&a);assert(t==total&&a==available&&errno==EDOM);
 guest_sysinfo si;assert(!bionic_sysinfo(&si)&&si.totalram==total&&si.freeram==available&&si.mem_unit==1);
 assert(bionic_sysconf(98)==(long)(total/16384)&&bionic_sysconf(99)==(long)(available/16384));
 char buf[1024];proc_memory("/proc/meminfo",buf,sizeof(buf));unsigned long long kb=0;assert(sscanf(strstr(buf,"MemAvailable:"),"MemAvailable: %llu",&kb)==1&&kb==available/1024);
 available=0;tl_bionic_memory_info(&t,&a);assert(!a);assert(bionic_sysconf(99)==0);
 available=total+16384;tl_bionic_memory_info(&t,&a);assert(a==total);
 fail_sysctl=1;tl_bionic_memory_info(&t,&a);assert(!t&&!a&&errno==EDOM);
#if !TARGET_OS_IPHONE
 assert(rights==0);
#endif
 return 0;}
'''.replace('PROC',proc)
   self.compile_run(prefix+platform+typedef+functions+main)

 def test_vm_region_object_rights_released_and_shared_discard_retains_backing(self):
  text=(TL/'husk-tl-bionic-io.c').read_text()
  funcs=extracted(text,'static void anon_zap(')+extracted(text,'static bool b_mprotect_writable(')
  self.compile_run(r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <pthread.h>
typedef uintptr_t vm_address_t;typedef size_t vm_size_t;typedef unsigned mach_msg_type_number_t;
typedef struct{int protection;}vm_region_basic_info_data_64_t;typedef void*vm_region_info_t;typedef int mach_port_t;
#define MACH_PORT_NULL 0
#define VM_REGION_BASIC_INFO_COUNT_64 1
#define VM_REGION_BASIC_INFO_64 1
#define VM_PROT_READ 1
#define VM_PROT_WRITE 2
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_FIXED 1
#define MAP_PRIVATE 2
#define MAP_ANON 4
#define KERN_SUCCESS 0
static unsigned char memory[16384] __attribute__((aligned(16384)));
static struct{uintptr_t addr;size_t len;}g_anon[1];static int g_nanon=1;
static pthread_mutex_t g_anon_lock=PTHREAD_MUTEX_INITIALIZER;
static int rights,fail_query,shared,remaps;
static int mach_task_self(void){return 1;}
static int vm_region_64(int task,vm_address_t*a,vm_size_t*s,int flavor,vm_region_info_t info,mach_msg_type_number_t*c,mach_port_t*o){(void)task;(void)flavor;(void)c;if(fail_query)return -1;*a=(uintptr_t)memory;*s=sizeof(memory);((vm_region_basic_info_data_64_t*)info)->protection=3;*o=5;rights++;return 0;}
static int mach_port_deallocate(int task,int port){assert(task==1&&port==5);rights--;return 0;}
static bool tl_ld_covers(const void*p,size_t n){(void)p;(void)n;return false;}
static bool tl_xmem_contains(const void*p){(void)p;return false;}
static bool tl_memory_reserve_contains(const void*p,size_t n){(void)p;(void)n;return shared;}
static int mprotect(void*p,size_t n,int prot){(void)p;(void)n;(void)prot;return 0;}
static void *mmap(void*p,size_t n,int prot,int flags,int fd,int offset){(void)n;(void)prot;(void)flags;(void)fd;(void)offset;remaps++;return p;}
'''+funcs+r'''
int main(void){g_anon[0].addr=(uintptr_t)memory;g_anon[0].len=sizeof(memory);
 for(int i=0;i<1000;i++){assert(b_mprotect_writable(memory,sizeof(memory)));anon_zap((uintptr_t)memory,sizeof(memory));assert(!rights);}
 assert(remaps==1000);shared=1;memset(memory,9,sizeof(memory));anon_zap((uintptr_t)memory,sizeof(memory));
 assert(!rights&&remaps==1000);for(size_t i=0;i<sizeof(memory);i++)assert(!memory[i]);
 fail_query=1;assert(!b_mprotect_writable(memory,sizeof(memory)));anon_zap((uintptr_t)memory,sizeof(memory));assert(!rights);return 0;}
''')

 def test_mremap_uses_wrappers_and_preserves_original_on_failure(self):
  func=extracted((TL/'husk-tl-bionic-io.c').read_text(),'static void *b_mremap(')
  self.compile_run(r'''
#include <assert.h>
#include <string.h>
#include <stddef.h>
#include <sys/mman.h>
static char fresh[64];static int failed,freed,guest_errno;
static void mm_trace(const char*s,void*p,size_t n,long a,long b){(void)s;(void)p;(void)n;(void)a;(void)b;}
static void *b_mmap(void*a,size_t n,int p,int f,int fd,long off){assert(!a&&n<=64&&p==3&&f==0x22&&fd==-1&&!off);memset(fresh,0,64);return failed?MAP_FAILED:fresh;}
static int b_munmap(void*a,size_t n){assert(a&&n);freed++;return 0;}
static void tl_set_guest_errno(int n){guest_errno=n;}
'''+func+r'''
int main(void){char old[32];memset(old,7,sizeof(old));
 assert(b_mremap(old,32,64,1,NULL)==fresh&&freed==1);for(int i=0;i<32;i++)assert(fresh[i]==7);
 for(int i=32;i<64;i++)assert(!fresh[i]);
 assert(b_mremap(old,32,16,1,NULL)==fresh&&freed==2);for(int i=0;i<16;i++)assert(fresh[i]==7);
 failed=1;assert(b_mremap(old,32,64,1,NULL)==MAP_FAILED&&freed==2&&guest_errno==12&&old[0]==7);return 0;}
''')

if __name__=='__main__':unittest.main()
