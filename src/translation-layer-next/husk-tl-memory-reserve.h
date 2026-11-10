/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_MEMORY_RESERVE_H
#define HUSK_TL_MEMORY_RESERVE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
/* A non-executable donor mapping retained until process exit. Ordinary guest
 * allocations use this first; exhaustion returns NULL to the normal mmap path. */
typedef struct {
    size_t mapped_bytes, used_bytes, free_bytes;
    uint64_t served_allocations, fallback_allocations;
    unsigned regions;
} tl_memory_reserve_stats;
typedef void (*tl_memory_growth_fn)(void *context, size_t minimum_bytes);
void tl_memory_reserve_set_growth_handler(tl_memory_growth_fn handler, void *context);
void tl_memory_reserve_growth_finished(void);
void tl_memory_reserve_snapshot(tl_memory_reserve_stats *out);
bool tl_memory_reserve_install(void *base, size_t bytes);
void *tl_memory_reserve_alloc(size_t bytes);
bool tl_memory_reserve_can_allocate(size_t bytes);
bool tl_memory_reserve_contains(const void *base, size_t bytes);
bool tl_memory_reserve_overlaps(const void *base, size_t bytes);
bool tl_memory_reserve_replace(void *base, size_t bytes, int protection);
bool tl_memory_reserve_release(void *base, size_t bytes);
/* Runs once on the native launch worker, never during a failing allocation. */
void husk_memory_donor_prepare(const char *game_data_dir);
#endif
