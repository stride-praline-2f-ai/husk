/* Java input snapshots never hold a host-facing lock while allocating guest objects. */
#ifndef HUSK_TL_JAVA_INPUT_H
#define HUSK_TL_JAVA_INPUT_H
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

static inline void tl_java_web_notify(atomic_bool *pending)
{
    atomic_store_explicit(pending, true, memory_order_release);
}
/* out has room for the bounded 4096-int queue plus one coalesced WebKit event. */
static inline int tl_java_input_snapshot(pthread_mutex_t *lock, int32_t *queue, int *count,
                                         atomic_bool *web_pending, int32_t out[4100])
{
    pthread_mutex_lock(lock);
    int n = *count;
    if (n) memcpy(out, queue, (size_t)n * sizeof(*out));
    *count = 0;
    pthread_mutex_unlock(lock);
    if (atomic_exchange_explicit(web_pending, false, memory_order_acq_rel)) {
        out[n++] = 9; out[n++] = 0; out[n++] = 0; out[n++] = 0;
    }
    return n;
}
#endif
