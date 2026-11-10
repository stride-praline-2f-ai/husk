/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_MEMORY_RESERVE_H
#define HUSK_TL_MEMORY_RESERVE_H
#include <stdbool.h>
#include <stddef.h>
/* A non-executable donor mapping retained until process exit. Ordinary guest
 * allocations use this first; exhaustion returns NULL to the normal mmap path. */
bool tl_memory_reserve_install(void *base, size_t bytes);
void *tl_memory_reserve_alloc(size_t bytes);
bool tl_memory_reserve_contains(const void *base, size_t bytes);
bool tl_memory_reserve_overlaps(const void *base, size_t bytes);
bool tl_memory_reserve_replace(void *base, size_t bytes, int protection);
bool tl_memory_reserve_release(void *base, size_t bytes);
/* Runs once on the native launch worker, never during a failing allocation. */
void husk_memory_donor_prepare(const char *game_data_dir);
#endif
