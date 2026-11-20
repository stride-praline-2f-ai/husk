/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_LIFECYCLE_H
#define HUSK_TL_LIFECYCLE_H
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* One process-lifetime NativeActivity. Producers publish desired state only;
 * the activity owner invokes guest/audio callbacks outside this module's lock. */
typedef struct {
 uint32_t ready,requested_paused,applied_paused,applying;
 uint64_t requested_sequence,applied_sequence,requests,duplicates,transitions;
} tl_lifecycle_stats;
void tl_lifecycle_bind(void (*wake)(void *),void *looper);
void tl_lifecycle_ready(bool initially_paused);
void tl_lifecycle_request(bool paused);
bool tl_lifecycle_next(bool *paused,uint64_t *sequence);
void tl_lifecycle_complete(bool paused,uint64_t sequence);
bool tl_lifecycle_wait_paused(uint32_t milliseconds); /* worker only, max5s */
void tl_lifecycle_snapshot(tl_lifecycle_stats *out);
/* Foreground protection for iOS GPU work. Pause is published from UIApplication
 * willResignActive, ahead of the background transition. Guest renderer calls
 * park without returning a synthetic VK_ERROR_DEVICE_LOST. No GPU-driver calls
 * or long waits on UIKit. A submission already in flight cannot be recalled. */
void tl_lifecycle_gpu_gate_wait(void);
typedef struct { uint64_t parked_calls, parked_wall_ns; uint32_t waiting_calls, paused; } tl_lifecycle_gpu_gate_stats;
void tl_lifecycle_gpu_gate_snapshot(tl_lifecycle_gpu_gate_stats *out);
#ifdef __cplusplus
}
#endif
#endif
