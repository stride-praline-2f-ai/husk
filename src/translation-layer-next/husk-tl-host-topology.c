/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-host-topology.h"
#include <pthread.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <sys/sysctl.h>
#endif
static pthread_once_t once = PTHREAD_ONCE_INIT;
static tl_host_cpu_info cached;
bool tl_host_cpu_topology_valid(const tl_host_cpu_info *info) {
    return info && info->total > 0 && info->total <= 256 && info->active > 0 && info->active <= info->total &&
           info->performance > 0 && info->performance < info->total &&
           info->efficiency > 0 && info->efficiency < info->total &&
           info->performance + info->efficiency == info->total;
}
#if defined(__APPLE__)
static int positive_sysctl(const char *name) {
    int value = 0; size_t bytes = sizeof(value);
    return !sysctlbyname(name, &value, &bytes, NULL, 0) && bytes == sizeof(value) && value > 0 && value <= 256 ? value : 0;
}
#endif
static void detect(void) {
#if defined(__APPLE__)
    cached.total = positive_sysctl("hw.logicalcpu_max");
    if (!cached.total) cached.total = positive_sysctl("hw.logicalcpu");
    cached.active = positive_sysctl("hw.logicalcpu");
    cached.performance = positive_sysctl("hw.perflevel0.logicalcpu");
    cached.efficiency = positive_sysctl("hw.perflevel1.logicalcpu");
#else
    long total = sysconf(_SC_NPROCESSORS_CONF), active = sysconf(_SC_NPROCESSORS_ONLN);
    cached.total = total > 0 && total <= 256 ? (int)total : 0;
    cached.active = active > 0 && active <= 256 ? (int)active : 0;
#endif
    if (!tl_host_cpu_topology_valid(&cached)) cached.performance = cached.efficiency = 0;
}
void tl_host_cpu_topology(tl_host_cpu_info *out) {
    if (!out) return;
    pthread_once(&once, detect);
    *out = cached;
}
