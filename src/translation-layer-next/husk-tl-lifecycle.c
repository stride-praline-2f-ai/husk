/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef __APPLE__
#define _DARWIN_C_SOURCE 1
#else
#define _POSIX_C_SOURCE 200809L
#endif
#include "husk-tl-lifecycle.h"
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>

static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t once=PTHREAD_ONCE_INIT;
static pthread_cond_t changed;
static pthread_t owner;
static bool bound;
static void (*wake_owner)(void *);
static void *owner_looper;
static tl_lifecycle_stats state;
static bool claimed_paused;
static uint64_t claimed_sequence;
static atomic_bool gpu_paused;
static uint64_t gpu_parked_calls, gpu_parked_wall_ns;
static uint32_t gpu_waiting_calls;
static void initialise(void){
 pthread_condattr_t attributes;pthread_condattr_init(&attributes);
#ifndef __APPLE__
 pthread_condattr_setclock(&attributes,CLOCK_MONOTONIC);
#endif
 pthread_cond_init(&changed,&attributes);pthread_condattr_destroy(&attributes);
}
static uint64_t monotonic_ns(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint64_t)t.tv_sec*1000000000ull+(uint64_t)t.tv_nsec;}
void tl_lifecycle_bind(void (*wake)(void *),void *looper){
 pthread_once(&once,initialise);pthread_mutex_lock(&lock);
 owner=pthread_self();bound=true;wake_owner=wake;owner_looper=looper;
 /* A fresh activity instance cannot inherit an old background gate. */
 atomic_store_explicit(&gpu_paused,false,memory_order_release);
 pthread_mutex_unlock(&lock);
}
void tl_lifecycle_ready(bool initially_paused){
 pthread_once(&once,initialise);pthread_mutex_lock(&lock);
 if(bound&&pthread_equal(owner,pthread_self())){
  state.ready=1;state.applied_paused=initially_paused;pthread_cond_broadcast(&changed);
 }
 pthread_mutex_unlock(&lock);
}
void tl_lifecycle_request(bool paused){
 pthread_once(&once,initialise);pthread_mutex_lock(&lock);
 state.requests++;
 /* iOS may revoke Metal GPU permission as soon as the UI becomes background.
  * Set this before waking the NativeActivity owner, not only after onPause. */
 atomic_store_explicit(&gpu_paused,paused,memory_order_release);
 if(state.requested_paused==(uint32_t)paused){
  state.duplicates++;
  if(!paused)pthread_cond_broadcast(&changed);
  pthread_mutex_unlock(&lock);return;
 }
 state.requested_paused=paused;state.requested_sequence++;
 void (*wake)(void*)=wake_owner;void *looper=owner_looper;
 pthread_cond_broadcast(&changed);pthread_mutex_unlock(&lock);
 /* The shim's nonblocking wake pipe is process-lifetime; never call guest code
  * or wait for the activity here, including while its callback is blocked. */
 if(wake&&looper)wake(looper);
}
bool tl_lifecycle_next(bool *paused,uint64_t *sequence){
 if(!paused||!sequence)return false;
 pthread_once(&once,initialise);pthread_mutex_lock(&lock);
 bool valid=bound&&pthread_equal(owner,pthread_self())&&state.ready&&!state.applying;
 if(valid&&state.requested_paused==state.applied_paused){
  state.applied_sequence=state.requested_sequence;pthread_cond_broadcast(&changed);valid=false;
 }
 if(valid){state.applying=1;*paused=claimed_paused=state.requested_paused;*sequence=claimed_sequence=state.requested_sequence;}
 pthread_mutex_unlock(&lock);return valid;
}
void tl_lifecycle_complete(bool paused,uint64_t sequence){
 pthread_once(&once,initialise);pthread_mutex_lock(&lock);
 if(bound&&pthread_equal(owner,pthread_self())&&state.applying&&paused==claimed_paused&&sequence==claimed_sequence){
  state.applying=0;state.applied_paused=paused;state.applied_sequence=sequence;state.transitions++;
  pthread_cond_broadcast(&changed);
 }
 pthread_mutex_unlock(&lock);
}
bool tl_lifecycle_wait_paused(uint32_t milliseconds){
 if(milliseconds>5000)milliseconds=5000;
 pthread_once(&once,initialise);pthread_mutex_lock(&lock);
 uint64_t deadline=monotonic_ns()+(uint64_t)milliseconds*1000000ull;
 for(;;){
  bool done=state.ready&&state.requested_paused&&state.applied_paused&&!state.applying;
  if(done){pthread_mutex_unlock(&lock);return true;}
  uint64_t current=monotonic_ns();
  if(!state.requested_paused||current>=deadline||(bound&&pthread_equal(owner,pthread_self()))){pthread_mutex_unlock(&lock);return false;}
#ifdef __APPLE__
  uint64_t left=deadline-current;
  struct timespec until={(time_t)(left/1000000000ull),(long)(left%1000000000ull)};
  pthread_cond_timedwait_relative_np(&changed,&lock,&until);
#else
  struct timespec until={(time_t)(deadline/1000000000ull),(long)(deadline%1000000000ull)};
  pthread_cond_timedwait(&changed,&lock,&until);
#endif
 }
}
void tl_lifecycle_snapshot(tl_lifecycle_stats *out){
 if(!out)return;
 pthread_once(&once,initialise);pthread_mutex_lock(&lock);*out=state;pthread_mutex_unlock(&lock);
}

void tl_lifecycle_gpu_gate_wait(void){
 /* Fully inactive path costs one relaxed atomic, no mutex or sleep. */
 if(!atomic_load_explicit(&gpu_paused,memory_order_acquire))return;
 pthread_once(&once,initialise);
 pthread_mutex_lock(&lock);
 if(atomic_load_explicit(&gpu_paused,memory_order_acquire)){
  const uint64_t started=monotonic_ns();
  gpu_waiting_calls++;
  /* A Vulkan wrapper must NEVER synthesize DEVICE_LOST or re-enter MoltenVK
   * after iOS revokes GPU work. This wait releases the lifecycle mutex. */
  while(atomic_load_explicit(&gpu_paused,memory_order_acquire))
   pthread_cond_wait(&changed,&lock);
  gpu_waiting_calls--;
  gpu_parked_calls++;
  uint64_t ended=monotonic_ns();
  if(ended>=started)gpu_parked_wall_ns+=ended-started;
 }
 pthread_mutex_unlock(&lock);
}
void tl_lifecycle_gpu_gate_snapshot(tl_lifecycle_gpu_gate_stats *out){
 if(!out)return;
 pthread_once(&once,initialise);pthread_mutex_lock(&lock);
 *out=(tl_lifecycle_gpu_gate_stats){
  .parked_calls=gpu_parked_calls,.parked_wall_ns=gpu_parked_wall_ns,
  .waiting_calls=gpu_waiting_calls,.paused=atomic_load_explicit(&gpu_paused,memory_order_acquire)};
 pthread_mutex_unlock(&lock);
}
