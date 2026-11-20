#!/usr/bin/env python3
"""Real lifecycle condition-variable test: background GPU calls park, never fail."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]
TL = ROOT / "src/translation-layer-next"

class GPUBackgroundGate(unittest.TestCase):
    def test_background_parks_vulkan_callers_and_resumes_without_fake_device_loss(self):
        with tempfile.TemporaryDirectory() as folder:
            src=Path(folder)/"test.c"
            src.write_text(r'''
#define _POSIX_C_SOURCE 200809L
#include "husk-tl-lifecycle.h"
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <time.h>
static atomic_int entered,passed;
static void *renderer(void *arg){
 (void)arg;
 atomic_store(&entered,1);
 tl_lifecycle_gpu_gate_wait();
 atomic_store(&passed,1);
 return NULL;
}
int main(void){
 tl_lifecycle_gpu_gate_wait(); /* unpaused path: never locks or stalls */
 tl_lifecycle_request(true);
 tl_lifecycle_gpu_gate_stats s={0};
 tl_lifecycle_gpu_gate_snapshot(&s);assert(s.paused);
 pthread_t thread;assert(!pthread_create(&thread,NULL,renderer,NULL));
 while(!atomic_load(&entered)){}
 struct timespec t={.tv_sec=0,.tv_nsec=30000000};
 nanosleep(&t,NULL);
 tl_lifecycle_gpu_gate_snapshot(&s);
 assert(s.waiting_calls==1 && !atomic_load(&passed));
 tl_lifecycle_request(false);
 pthread_join(thread,NULL);
 tl_lifecycle_gpu_gate_snapshot(&s);
 assert(atomic_load(&passed) && !s.paused && !s.waiting_calls &&
        s.parked_calls==1 && s.parked_wall_ns>=10000000);
 tl_lifecycle_request(true);
 tl_lifecycle_request(true); /* duplicate pause must not leave stuck state */
 tl_lifecycle_request(false);
 for(int i=0;i<10000;i++)tl_lifecycle_gpu_gate_wait();
 return 0;
}
''')
            exe=Path(folder)/"gate"
            subprocess.run(["cc","-std=c11","-O2","-Wall","-Wextra","-Werror",
                            "-pthread","-I",str(TL),str(src),str(TL/"husk-tl-lifecycle.c"),"-o",str(exe)],check=True)
            subprocess.run([str(exe)],check=True,timeout=15)

if __name__=="__main__":unittest.main()
