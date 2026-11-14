#!/usr/bin/env python3
"""Execute the actual host input/continuation components, without Anki or a device."""
import platform
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INC = ROOT / 'src/translation-layer-next'

INPUT = r'''
#include "husk-tl-java-input.h"
#include <assert.h>
static atomic_bool pending;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static void *notify(void *unused) {
    (void)unused;
    for (int i=0;i<100000;i++) tl_java_web_notify(&pending);
    return NULL;
}
int main(void) {
    int32_t queue[4096], out[4100]; int n=0;
    assert(tl_java_input_snapshot(&lock,queue,&n,&pending,out)==0);
    /* WebKit notifications must finish while the input consumer owns its lock. */
    pthread_mutex_lock(&lock);
    pthread_t host; assert(!pthread_create(&host,NULL,notify,NULL));
    assert(!pthread_join(host,NULL));
    pthread_mutex_unlock(&lock);
    assert(tl_java_input_snapshot(&lock,queue,&n,&pending,out)==4);
    assert(out[0]==9 && out[1]==0 && out[2]==0 && out[3]==0);
    assert(tl_java_input_snapshot(&lock,queue,&n,&pending,out)==0);
    for(int i=0;i<4096;i++) queue[i]=i;
    n=4096; tl_java_web_notify(&pending);
    assert(tl_java_input_snapshot(&lock,queue,&n,&pending,out)==4100);
    for(int i=0;i<4096;i++) assert(out[i]==i);
    assert(n==0 && out[4096]==9);
    assert(!pthread_mutex_trylock(&lock)); pthread_mutex_unlock(&lock);
    tl_java_web_notify(&pending);
    assert(tl_java_input_snapshot(&lock,queue,&n,&pending,out)==4);
    return 0;
}
'''

PENDING = r'''
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <assert.h>
#include "husk-tl-web-pending.inc"
@interface FakeTask : NSObject
@property int cancels;
@end
@implementation FakeTask
- (void)cancel { self.cancels++; }
@end
int main(void) { @autoreleasepool {
    __block int canceled=0;
    int human=pending_add(1,HuskWebPrompt,@"human",0,^{canceled++;});
    assert(!g_pending_timer);
    int timed=pending_add(2,HuskWebBridge,@"bridge",30,^{canceled++;});
    assert(g_pending_timer);
    FakeTask *network=[FakeTask new]; g_pending[@(timed)].network=(id)network;
    pending_cancel_owner(2);
    assert(canceled==1 && network.cancels==1 && g_pending[@(human)]);
    assert(!g_pending_timer); /* no periodic wakeups for a human dialog */
    pending_cancel(timed); assert(canceled==1 && network.cancels==1);
    int done=pending_add(3,HuskWebNavigation,@"nav",30,^{canceled++;});
    HuskWebPending *p=pending_take(done);
    assert(p.kind==HuskWebNavigation && p.owner==3);
    assert(!pending_take(done));
    pending_expire(DBL_MAX); assert(canceled==1); /* taken never canceled */
    int expires=pending_add(4,HuskWebScheme,@"resource",60,^{canceled++;});
    double deadline=g_pending[@(expires)].deadline;
    pending_expire(deadline-1); assert(g_pending[@(expires)]);
    pending_expire(deadline); assert(!g_pending[@(expires)] && canceled==2);
    assert(g_pending[@(human)]); /* untimed dialogs survive expiration */
    g_next_call=INT_MAX;
    int last=pending_add(5,HuskWebAlert,@"last",0,^{canceled++;});
    int wrapped=pending_add(5,HuskWebConfirm,@"wrapped",0,^{canceled++;});
    assert(last==INT_MAX && wrapped>0 && wrapped!=human);
    /* cancellation removes first; reentrant late completion sees nothing */
    __block int reentrant=0;
    __block int call=0;
    call=pending_add(6,HuskWebBridge,@"reenter",1,^{assert(!pending_take(call)); reentrant++;});
    pending_cancel(call); pending_cancel(call); assert(reentrant==1);
    pending_cancel_all();
    assert(canceled==5 && !g_pending.count && !g_pending_timer);
    pending_cancel_all(); assert(canceled==5);
    return 0;
} }
'''

class WebResilience(unittest.TestCase):
    def compile_run(self, source, objc=False):
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/('test.m' if objc else 'test.c'); path.write_text(source)
            compiler='clang' if objc else (shutil.which('clang') or shutil.which('cc'))
            cmd=[compiler,'-Wall','-Wextra','-Werror','-I',str(INC),str(path),'-o',td+'/test']
            cmd+=['-fobjc-arc','-fblocks','-framework','Foundation'] if objc else ['-std=c11','-pthread']
            subprocess.run(cmd,check=True,capture_output=True,text=True)
            subprocess.run([td+'/test'],check=True,timeout=15,capture_output=True,text=True)

    def test_input_is_bounded_coalesced_and_does_not_wait_on_guest_lock(self):
        self.compile_run(INPUT)

    @unittest.skipUnless(platform.system()=='Darwin','Foundation component executes on Apple cloud runner')
    def test_pending_exact_once_owner_cleanup_deadlines_and_idle_timer(self):
        self.compile_run('#include <float.h>\n'+PENDING,True)

    def test_host_locks_are_released_before_guest_allocation(self):
        s=(INC/'husk-tl-dvm-web.m').read_text()
        poll=s.split('NAT(W_poll)',1)[1].split('/* ---- CookieManager',1)[0]
        self.assertLess(poll.index('pthread_mutex_unlock'),poll.index('tl_jni_new_obj_array'))
        self.assertNotIn('tl_javaapp_touch(9',s)
        self.assertIn('tl_javaapp_web_events();',s)
        self.assertIn('pending_cancel_owner(_wid);',s)
        self.assertIn('g_pending[@(call)] != entry',s)
        s=(INC/'husk-tl-dvm-android.c').read_text().split('NAT(N_pollInput)',1)[1].split('NAT(',1)[0]
        self.assertLess(s.index('tl_java_input_snapshot'),s.index('tl_jni_new_prim_array'))

if __name__=='__main__': unittest.main(verbosity=2)
