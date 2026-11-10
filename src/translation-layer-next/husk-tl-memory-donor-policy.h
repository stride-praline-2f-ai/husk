/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_MEMORY_DONOR_POLICY_H
#define HUSK_TL_MEMORY_DONOR_POLICY_H
#include <stdint.h>
#include <stdbool.h>
#define TL_DONOR_CHUNK (UINT64_C(64) << 20)
#define TL_DONOR_INITIAL (UINT64_C(256) << 20)
#define TL_DONOR_HEADROOM (UINT64_C(256) << 20)
#define TL_DONOR_MAX_BYTES (UINT64_C(6) << 30)
#define TL_DONOR_MAX_PROCESSES 4
/* A ceiling for on-demand shared backing, never an advertised process limit or
 * a reservation/touch of half the device's RAM. Actual OS grants may be less. */
static inline uint64_t tl_memory_donor_budget(uint64_t physical)
{
    uint64_t value = physical / 2;
    if (value > TL_DONOR_MAX_BYTES) value = TL_DONOR_MAX_BYTES;
    return value / TL_DONOR_CHUNK * TL_DONOR_CHUNK;
}
static inline bool tl_memory_donor_request_allowed(uint64_t bytes, uint64_t available, uint64_t already)
{
    return bytes >= TL_DONOR_CHUNK && bytes <= TL_DONOR_INITIAL
        && bytes % TL_DONOR_CHUNK == 0 && already <= TL_DONOR_MAX_BYTES - bytes
        && available >= bytes && available - bytes >= TL_DONOR_HEADROOM;
}
#endif
