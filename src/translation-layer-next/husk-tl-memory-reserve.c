/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-memory-reserve.h"
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#define PAGE_BYTES ((size_t)16384)
#define MAX_REGION_BYTES ((size_t)256 << 20)
#define MAX_TOTAL_BYTES ((size_t)6 << 30)
#define LOW_WATER_BYTES ((size_t)64 << 20)
#define MAX_REGIONS 128
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
/* One byte per 16 KiB page: <=384 KiB metadata for the entire 6 GiB ceiling.
 * 0 untouched/zero-fill, 1 live, 2 released. No allocation in this bookkeeping. */
static unsigned char states[MAX_TOTAL_BYTES / PAGE_BYTES];
static struct region { uintptr_t base; size_t pages, first, live; } regions[MAX_REGIONS];
static size_t region_count, state_count, mapped_bytes, used_bytes;
static uint64_t served, misses;
static tl_memory_growth_fn growth;
static void *growth_context;
static bool growth_pending;
static bool rounded_pages(size_t bytes, size_t *out)
{
    if (!bytes || bytes > MAX_REGION_BYTES) return false;
    *out = (bytes + PAGE_BYTES - 1) / PAGE_BYTES;
    return true;
}
static struct region *containing(uintptr_t a, size_t bytes)
{
    for (size_t i = 0; i < region_count; i++) {
        struct region *r = &regions[i];
        if (a >= r->base && a - r->base < r->pages * PAGE_BYTES
            && bytes <= r->pages * PAGE_BYTES - (a - r->base)) return r;
    }
    return NULL;
}
/* Captured under the lock, invoked after unlocking. The provider only enqueues
 * work; it must never perform IPC or wait on the allocation thread. */
static tl_memory_growth_fn request_growth(void **context)
{
    if (!growth || growth_pending || mapped_bytes >= MAX_TOTAL_BYTES) return NULL;
    growth_pending = true; *context = growth_context;
    return growth;
}
void tl_memory_reserve_set_growth_handler(tl_memory_growth_fn handler, void *context)
{
    pthread_mutex_lock(&lock);
    growth = handler; growth_context = context; growth_pending = false;
    pthread_mutex_unlock(&lock);
}
void tl_memory_reserve_growth_finished(void)
{
    pthread_mutex_lock(&lock); growth_pending = false; pthread_mutex_unlock(&lock);
}
void tl_memory_reserve_snapshot(tl_memory_reserve_stats *out)
{
    if (!out) return;
    pthread_mutex_lock(&lock);
    *out = (tl_memory_reserve_stats){mapped_bytes, used_bytes, mapped_bytes - used_bytes,
                                   served, misses, (unsigned)region_count};
    pthread_mutex_unlock(&lock);
}
bool tl_memory_reserve_install(void *base, size_t bytes)
{
    uintptr_t a = (uintptr_t)base;
    if (!a || a % PAGE_BYTES || !bytes || bytes % PAGE_BYTES || bytes > MAX_REGION_BYTES
        || bytes > UINTPTR_MAX - a) return false;
    pthread_mutex_lock(&lock);
    bool ok = region_count < MAX_REGIONS && bytes <= MAX_TOTAL_BYTES - mapped_bytes;
    for (size_t i = 0; i < region_count && ok; i++) {
        struct region *r = &regions[i];
        if (a < r->base + r->pages * PAGE_BYTES && r->base < a + bytes) ok = false;
    }
    if (ok) {
        regions[region_count++] = (struct region){a, bytes / PAGE_BYTES, state_count, 0};
        state_count += bytes / PAGE_BYTES; mapped_bytes += bytes;
    }
    pthread_mutex_unlock(&lock);
    return ok;
}
void *tl_memory_reserve_alloc(size_t bytes)
{
    size_t need;
    if (!rounded_pages(bytes, &need)) return NULL;
    void *answer = NULL, *context = NULL; tl_memory_growth_fn callback = NULL;
    pthread_mutex_lock(&lock);
    for (size_t k = 0; k < region_count && !answer; k++) {
        struct region *r = &regions[k]; size_t run = 0;
        if (r->pages - r->live < need) continue;
        for (size_t i = 0; i < r->pages; i++) {
            run = states[r->first + i] == 1 ? 0 : run + 1;
            if (run != need) continue;
            size_t start = i + 1 - need;
            void *p = (void *)(r->base + start * PAGE_BYTES);
            if (mprotect(p, need * PAGE_BYTES, PROT_READ | PROT_WRITE)) break;
            /* Never eagerly touch unused donated RAM. Clear recycled pages. */
            for (size_t j = start; j <= i; j++)
                if (states[r->first + j] == 2) memset((void *)(r->base + j * PAGE_BYTES), 0, PAGE_BYTES);
            memset(states + r->first + start, 1, need);
            used_bytes += need * PAGE_BYTES; r->live += need; served++; answer = p; break;
        }
    }
    if (!answer) misses++;
    if (!answer || mapped_bytes - used_bytes < LOW_WATER_BYTES) callback = request_growth(&context);
    pthread_mutex_unlock(&lock);
    if (callback) callback(context, answer ? 0 : bytes);
    return answer;
}
bool tl_memory_reserve_can_allocate(size_t bytes)
{
    size_t need; bool yes = false;
    if (!rounded_pages(bytes, &need)) return false;
    pthread_mutex_lock(&lock);
    for (size_t k = 0; k < region_count && !yes; k++) {
        struct region *r = &regions[k]; size_t run = 0;
        if (r->pages - r->live < need) continue;
        for (size_t i = 0; i < r->pages; i++) {
            run = states[r->first + i] == 1 ? 0 : run + 1;
            if (run == need) { yes = true; break; }
        }
    }
    pthread_mutex_unlock(&lock); return yes;
}
bool tl_memory_reserve_contains(const void *base, size_t bytes)
{
    pthread_mutex_lock(&lock); bool ok = containing((uintptr_t)base, bytes) != NULL;
    pthread_mutex_unlock(&lock); return ok;
}
bool tl_memory_reserve_release(void *base, size_t bytes)
{
    size_t count;
    if ((uintptr_t)base % PAGE_BYTES || !rounded_pages(bytes, &count)) return false;
    pthread_mutex_lock(&lock);
    struct region *r = containing((uintptr_t)base, count * PAGE_BYTES);
    bool ok = r && mprotect(base, count * PAGE_BYTES, PROT_NONE) == 0;
    if (ok) {
        size_t first = r->first + ((uintptr_t)base - r->base) / PAGE_BYTES;
        for (size_t i = first; i < first + count; i++) {
            if (states[i] == 1) { used_bytes -= PAGE_BYTES; r->live--; }
            states[i] = 2;
        }
    }
    pthread_mutex_unlock(&lock); return ok;
}
bool tl_memory_reserve_overlaps(const void *base, size_t bytes)
{
    uintptr_t a = (uintptr_t)base; bool yes = false;
    pthread_mutex_lock(&lock);
    for (size_t i = 0; i < region_count && !yes; i++) {
        struct region *r = &regions[i];
        yes = bytes && a < r->base + r->pages * PAGE_BYTES && (a >= r->base || bytes > r->base - a);
    }
    pthread_mutex_unlock(&lock); return yes;
}
bool tl_memory_reserve_replace(void *base, size_t bytes, int protection)
{
    size_t count;
    if ((uintptr_t)base % PAGE_BYTES || !rounded_pages(bytes, &count) || (protection & ~(PROT_READ | PROT_WRITE))) return false;
    pthread_mutex_lock(&lock);
    struct region *r = containing((uintptr_t)base, count * PAGE_BYTES);
    bool ok = r && mprotect(base, count * PAGE_BYTES, PROT_READ | PROT_WRITE) == 0;
    if (ok) {
        size_t first = r->first + ((uintptr_t)base - r->base) / PAGE_BYTES;
        for (size_t i = first; i < first + count; i++) {
            if (states[i]) memset((void *)(r->base + (i - r->first) * PAGE_BYTES), 0, PAGE_BYTES);
            if (states[i] != 1) { used_bytes += PAGE_BYTES; r->live++; }
            states[i] = 1;
        }
        ok = mprotect(base, count * PAGE_BYTES, protection) == 0;
    }
    pthread_mutex_unlock(&lock); return ok;
}
