/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_VK_DISPATCH_H
#define HUSK_TL_VK_DISPATCH_H
#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>

/* A directly loaded ICD need only export GIPA/GDPA, not each Vulkan command.
 * Keep live instances for resolving its generic dispatch trampolines. Never
 * query a destroyed probe instance, and never hold the lock during a GPU call.
 * Library and callbacks are immutable after the launch-time bind. */
typedef void *(*tl_vkd_gipa)(void *, const char *);
typedef void *(*tl_vkd_symbol)(void *, const char *);
typedef struct {
    pthread_mutex_t lock;
    void *instances[16];
    void *library;
    tl_vkd_symbol symbol;
    tl_vkd_gipa gipa;
} tl_vkd_dispatch;
#define TL_VKD_INITIALIZER { .lock = PTHREAD_MUTEX_INITIALIZER }

static inline bool tl_vkd_add(tl_vkd_dispatch *d, void *instance) {
    if (!instance) return false;
    pthread_mutex_lock(&d->lock);
    for (size_t i=0;i<16;i++) if(d->instances[i]==instance) {
        pthread_mutex_unlock(&d->lock); return true;
    }
    for (size_t i=0;i<16;i++) if(!d->instances[i]) {
        d->instances[i]=instance; pthread_mutex_unlock(&d->lock); return true;
    }
    pthread_mutex_unlock(&d->lock); return false;
}
static inline void tl_vkd_remove(tl_vkd_dispatch *d, void *instance) {
    pthread_mutex_lock(&d->lock);
    for(size_t i=0;i<16;i++) if(d->instances[i]==instance) d->instances[i]=NULL;
    pthread_mutex_unlock(&d->lock);
}
static inline void *tl_vkd_lookup(tl_vkd_dispatch *d, const char *name) {
    if (!name) return NULL;
    void *fn=d->symbol ? d->symbol(d->library,name) : NULL;
    if(fn || !d->gipa) return fn;
    pthread_mutex_lock(&d->lock);
    for(size_t i=0;i<16 && !fn;i++) if(d->instances[i]) fn=d->gipa(d->instances[i],name);
    if(!fn) fn=d->gipa(NULL,name);
    pthread_mutex_unlock(&d->lock);
    return fn;
}
#endif
