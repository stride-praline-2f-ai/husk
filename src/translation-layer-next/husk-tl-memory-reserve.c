/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-memory-reserve.h"
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
enum { PAGE = 16384, MAX_PAGES = 16384 }; /* 256 MiB hard ceiling */
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned char used[MAX_PAGES]; /* 0 untouched/zero, 1 mapped, 2 released */
static uintptr_t arena;
static size_t pages;
static bool rounded_pages(size_t n, size_t *out)
{
    if (!n || n > (size_t)MAX_PAGES * PAGE) return false;
    *out = (n + PAGE - 1) / PAGE;
    return true;
}
bool tl_memory_reserve_install(void *base, size_t bytes)
{
    if (!base || (uintptr_t)base % PAGE || !bytes || bytes % PAGE || bytes > (size_t)MAX_PAGES * PAGE
        || bytes > UINTPTR_MAX - (uintptr_t)base) return false;
    pthread_mutex_lock(&lock);
    bool ok = !arena;
    if (ok) { arena = (uintptr_t)base; pages = bytes / PAGE; }
    pthread_mutex_unlock(&lock);
    return ok;
}
void *tl_memory_reserve_alloc(size_t bytes)
{
    size_t need;
    if (!rounded_pages(bytes, &need)) return NULL;
    pthread_mutex_lock(&lock);
    size_t run = 0;
    for (size_t i = 0; i < pages; i++) {
        run = used[i] == 1 ? 0 : run + 1;
        if (run != need) continue;
        size_t start = i + 1 - need;
        void *p = (void *)(arena + start * PAGE);
        /* A previous user may have changed protections. Never publish stale
         * contents or claim success if restoring writable pages fails. */
        if (mprotect(p, need * PAGE, PROT_READ | PROT_WRITE)) break;
        /* Fresh donor pages are already zero-fill-on-demand. Do not touch the
         * entire reserve at launch; only previously used pages need clearing. */
        for (size_t j = start; j <= i; j++)
            if (used[j] == 2) memset((void *)(arena + j * PAGE), 0, PAGE);
        memset(used + start, 1, need);
        pthread_mutex_unlock(&lock);
        return p;
    }
    pthread_mutex_unlock(&lock);
    return NULL;
}
bool tl_memory_reserve_contains(const void *base, size_t bytes)
{
    pthread_mutex_lock(&lock);
    uintptr_t a = (uintptr_t)base;
    bool ok = arena && a >= arena && a - arena < pages * PAGE && bytes <= pages * PAGE - (a - arena);
    pthread_mutex_unlock(&lock);
    return ok;
}
bool tl_memory_reserve_release(void *base, size_t bytes)
{
    size_t count;
    if ((uintptr_t)base % PAGE || !rounded_pages(bytes, &count)) return false;
    pthread_mutex_lock(&lock);
    uintptr_t a = (uintptr_t)base;
    bool ok = arena && a >= arena && a - arena < pages * PAGE && count <= pages - (a - arena) / PAGE;
    if (ok) {
        ok = mprotect(base, count * PAGE, PROT_NONE) == 0;
        if (ok) memset(used + (a - arena) / PAGE, 2, count);
    }
    /* Keep shared backing and its owner alive; reuse zeroes on allocation.
     * In particular, never munmap/MAP_FIXED these pages into private memory. */
    pthread_mutex_unlock(&lock);
    return ok;
}
bool tl_memory_reserve_overlaps(const void *base, size_t bytes)
{
    uintptr_t a = (uintptr_t)base;
    pthread_mutex_lock(&lock);
    bool ok = arena && bytes && a < arena + pages * PAGE && (a >= arena || bytes > arena - a);
    pthread_mutex_unlock(&lock);
    return ok;
}
bool tl_memory_reserve_replace(void *base, size_t bytes, int protection)
{
    size_t count;
    if ((uintptr_t)base % PAGE || !rounded_pages(bytes, &count) || (protection & ~(PROT_READ | PROT_WRITE))) return false;
    pthread_mutex_lock(&lock);
    uintptr_t a = (uintptr_t)base;
    bool ok = arena && a >= arena && a - arena < pages * PAGE && count <= pages - (a - arena) / PAGE;
    if (ok) {
        ok = mprotect(base, count * PAGE, PROT_READ | PROT_WRITE) == 0;
        if (ok) {
            size_t first = (a - arena) / PAGE;
            for (size_t j = first; j < first + count; j++)
                if (used[j]) memset((void *)(arena + j * PAGE), 0, PAGE);
            /* Keep mapped pages claimed even if the final protect fails. */
            memset(used + (a - arena) / PAGE, 1, count);
            ok = mprotect(base, count * PAGE, protection) == 0;
        }
    }
    pthread_mutex_unlock(&lock);
    return ok;
}
