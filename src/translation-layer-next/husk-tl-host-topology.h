/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_HOST_TOPOLOGY_H
#define HUSK_TL_HOST_TOPOLOGY_H
#include <stdbool.h>
/* Runtime scheduling capacity, not thread affinity or measured core residency.
 * Inspired by Henge's Duo host/scheduling.c: query once, validate, stay unknown
 * when the kernel supplies no complete performance/efficiency split. */
typedef struct { int total, active, performance, efficiency; } tl_host_cpu_info;
bool tl_host_cpu_topology_valid(const tl_host_cpu_info *info);
void tl_host_cpu_topology(tl_host_cpu_info *out);
#endif
