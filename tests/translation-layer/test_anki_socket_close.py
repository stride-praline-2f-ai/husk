#!/usr/bin/env python3
"""Actual Bionic signal wrappers: wake blocked accept when libandroidio closes a socket."""
import os, platform, shutil, subprocess, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def source(name):
    path = 'src/translation-layer-next/' + name
    ref = os.environ.get('HUSK_TEST_SOURCE_REF')
    return subprocess.check_output(['git', 'show', ref + ':' + path], cwd=ROOT, text=True) if ref else (ROOT/path).read_text()
def function(s, name):
    start = s.index(name + '(')
    start = s.rfind('\n', 0, start) + 1
    opening = s.index('{', start); depth = 1; end = opening + 1
    while depth:
        depth += (s[end] == '{') - (s[end] == '}'); end += 1
    return s[start:end] + '\n'
class SocketCloseTests(unittest.TestCase):
    def test_actual_signal_registration_masks_and_blocked_accept(self):
        base = source('husk-tl-bionic.c'); io = source('husk-tl-bionic-io.c'); thread = source('husk-tl-bionic-pthread.c')
        mapping = base[base.index('static const int k_sig_to_darwin'):base.index('/* ------------------------------------------------------------------ notes */')]
        signals = io[io.index('typedef struct { int sa_flags;'):io.index('static void *b_signal(')]
        code = r'''
#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#include <assert.h>
#include <signal.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/ucontext.h>
#ifdef __APPLE__
#include <mach/mach.h>
#if defined(__arm64__)
#include <mach/arm/thread_status.h>
#endif
#else
/* Linux-only harness aliases for Darwin's two otherwise-unmapped signal slots. */
#define SIGEMT SIGSTKFLT
#define SIGINFO SIGPWR
static int getname2(pthread_t t,char *s,size_t n){return pthread_getname_np(t,s,n);}
#define pthread_getname_np getname2
#endif
#define TL_ERRNO_BEGIN() do {} while (0)
#define TL_ERRNO_END() do {} while (0)
static int guest_errno;
static void tl_set_guest_errno(int e){guest_errno=e;}
static void tl_log_line(const char *s,...){(void)s;}
static void tl_note_once(const char *s){(void)s;}
static int rc(int r){return r;}
''' + mapping + signals + function(thread,'b_kill') + function(thread,'sigset_to_darwin') + function(thread,'sigset_from_darwin') + function(thread,'b_sigmask') + r'''
static volatile sig_atomic_t delivered;
static void interrupted(int sig){delivered=sig;}
static atomic_bool ready, closed, done;
static int listener, result, result_errno;
static void *accepting(void *p){
 (void)p; uint64_t bit=1ull<<33; assert(b_sigmask(1,&bit,NULL)==0);
 atomic_store(&ready,true);
 do { result=accept(listener,NULL,NULL); result_errno=errno; } while(result<0 && result_errno==EINTR && !atomic_load(&closed));
 atomic_store(&done,true);return NULL;
}
int main(void){
 alarm(8);
 assert(tl_signal_to_darwin(34)==SIGEMT);
 assert(tl_signal_from_darwin(SIGEMT)==34);
 assert(tl_signal_to_darwin(10)==SIGUSR1 && tl_signal_to_darwin(12)==SIGUSR2 && tl_signal_to_darwin(30)==SIGINFO);
 assert(tl_signal_to_darwin(0)==0 && tl_signal_to_darwin(32)==-1 && tl_signal_to_darwin(35)==-1 && tl_signal_to_darwin(65)==-1);
 uint64_t bit=1ull<<33; uint32_t mask=1u<<(SIGEMT-1);
 assert(sigset_to_darwin(bit)==mask && sigset_from_darwin(mask)==bit);
 guest_sigaction action={.handler=(void *)interrupted},old={0},saved={0};
 struct sigaction host_old;assert(sigaction(SIGEMT,NULL,&host_old)==0);
 assert(b_sigaction(34,&action,&saved)==0);
 assert(b_sigaction(34,NULL,&old)==0 && old.handler==action.handler);
 struct sigaction installed; assert(sigaction(SIGEMT,NULL,&installed)==0 && !(installed.sa_flags&SA_RESTART));
 uint64_t initial=0,blocked=0;assert(b_sigmask(0,&bit,&initial)==0);assert(b_sigmask(0,NULL,&blocked)==0 && (blocked&bit));
 assert(b_kill(pthread_self(),34)==0);assert(delivered==0);assert(b_sigmask(1,&bit,NULL)==0 && delivered==34);
 delivered=0; listener=socket(AF_INET,SOCK_STREAM,0);assert(listener>=0);
 struct sockaddr_in addr={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
 assert(bind(listener,(void *)&addr,sizeof(addr))==0 && listen(listener,1)==0);
 pthread_t worker;assert(pthread_create(&worker,NULL,accepting,NULL)==0);
 while(!atomic_load(&ready))usleep(100);
 /* Ensure the worker reaches its blocking syscall. Repeat the close signal if scheduling won the race. */
 usleep(10000);atomic_store(&closed,true);
 for(int n=0;n<1000 && !atomic_load(&done);n++){assert(b_kill(worker,34)==0);usleep(1000);}
 assert(atomic_load(&done));pthread_join(worker,NULL);
 assert(result==-1 && result_errno==EINTR && delivered==34);close(listener);
 assert(b_sigaction(35,&action,NULL)==-1 && guest_errno==22);
 assert(sigaction(SIGEMT,&host_old,NULL)==0);assert(b_sigmask(2,&initial,NULL)==0);
 puts("actual libcore close signal: registration, round-trip mask, no SA_RESTART, blocked accept interruption/join passed");
 return 0;
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp); (p/'test.c').write_text(code)
            compiler=shutil.which('clang') or shutil.which('cc')
            run=subprocess.run([compiler,'-std=gnu11','-pthread',str(p/'test.c'),'-o',str(p/'test')],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            run=subprocess.run([str(p/'test')],capture_output=True,text=True,timeout=12)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            print(run.stdout.strip())
if __name__=='__main__': unittest.main(verbosity=2)
