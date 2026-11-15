#!/usr/bin/env python3
"""Production topology reader: complete/unknown layouts, validation and one-time concurrent query."""
import shutil,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PROGRAM=r'''
#include "husk-tl-host-topology.h"
#include <assert.h>
#include <pthread.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <limits.h>
static const char *mode;static int reads;
int sysctlbyname(const char *name,void *out,size_t *bytes,const void *in,size_t n){
 (void)in;(void)n;reads++;int v=0;
 if(!strcmp(mode,"missing"))return -1;
 if(!strcmp(name,"hw.logicalcpu_max")){if(!strcmp(mode,"fallback"))return -1;v=6;}
 else if(!strcmp(name,"hw.logicalcpu"))v=6;
 else if(!strcmp(name,"hw.perflevel0.logicalcpu"))v=!strcmp(mode,"partial")?0:!strcmp(mode,"oversized")?INT_MAX:2;
 else if(!strcmp(name,"hw.perflevel1.logicalcpu"))v=!strcmp(mode,"inconsistent")?3:4;
 else return -1;
 if(!strcmp(mode,"bad-size")&&strstr(name,"perflevel")){*bytes=1;return 0;}
 assert(*bytes==sizeof(v));memcpy(out,&v,sizeof(v));return 0;
}
static void *reader(void *p){(void)p;tl_host_cpu_info info;tl_host_cpu_topology(&info);assert(info.total==6&&info.active==6&&info.performance==2&&info.efficiency==4);return NULL;}
int main(int argc,char **argv){
 assert(argc==2);mode=argv[1];
 tl_host_cpu_info known={6,6,2,4},bad={INT_MAX,6,2,4};
 assert(tl_host_cpu_topology_valid(&known)&&!tl_host_cpu_topology_valid(NULL)&&!tl_host_cpu_topology_valid(&bad));
 bad=known;bad.active=7;assert(!tl_host_cpu_topology_valid(&bad));bad=known;bad.performance=INT_MAX;assert(!tl_host_cpu_topology_valid(&bad));
 if(!strcmp(mode,"parallel")){pthread_t ts[32];for(int i=0;i<32;i++)assert(!pthread_create(ts+i,NULL,reader,NULL));for(int i=0;i<32;i++)pthread_join(ts[i],NULL);assert(reads==4);}
 else{tl_host_cpu_info info;tl_host_cpu_topology(&info);int prior=reads;for(int i=0;i<100;i++)tl_host_cpu_topology(&info);assert(prior==reads);
  if(!strcmp(mode,"valid")||!strcmp(mode,"fallback"))assert(tl_host_cpu_topology_valid(&info)&&info.performance==2&&info.efficiency==4);
  else assert(!tl_host_cpu_topology_valid(&info)&&info.performance==0&&info.efficiency==0);
 }
 puts("PASS topology query, validation, cached immutable result");return 0;
}
'''
class HostTopologyTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.tmp.cleanup);p=Path(cls.tmp.name);(p/'sys').mkdir()
  (p/'sys/sysctl.h').write_text('#include <stddef.h>\nint sysctlbyname(const char *,void *,size_t *,const void *,size_t);\n')
  (p/'main.c').write_text(PROGRAM);cls.exe=p/'test'
  subprocess.run([shutil.which('clang') or 'cc','-std=c11','-Wall','-Wextra','-Werror','-D__APPLE__','-pthread','-I',str(p),'-I',str(ROOT/'src/translation-layer-next'),str(ROOT/'src/translation-layer-next/husk-tl-host-topology.c'),str(p/'main.c'),'-o',str(cls.exe)],check=True)
 def test_complete_kernel_layout_and_logicalcpu_fallback(self):
  for mode in ['valid','fallback']:subprocess.run([str(self.exe),mode],check=True)
 def test_missing_partial_inconsistent_oversized_and_wrong_size_stay_unknown(self):
  for mode in ['missing','partial','inconsistent','oversized','bad-size']:subprocess.run([str(self.exe),mode],check=True)
 def test_simultaneous_first_queries_initialize_once(self):subprocess.run([str(self.exe),'parallel'],check=True)
if __name__=='__main__':unittest.main(verbosity=2)
