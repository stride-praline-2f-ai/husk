/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_FRAMEGEN_H
#define HUSK_TL_FRAMEGEN_H
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    uint32_t version,size,enabled,width,height,reserved;
} tl_fg_config;
typedef struct {
    uint32_t version,size,active,failed;
    uint64_t rendered,generated,presented_real,dropped,resets,gpu_errors;
} tl_fg_stats;
/* Optional bounded visual evidence; independent of the unchanged framegen ABI.
 * directory must be a new empty absolute directory. No capture is automatic.
 */
typedef struct {
    uint32_t version,size,enabled,pair_limit,first_frame,frame_stride;
    char directory[768];
} tl_fg_capture_config;
void husk_ue4_set_diagnostic_session(const char *session);
void husk_ue4_set_framegen_capture_directory(const char *directory);
int tl_vk_framegen_capture_arm(const char *directory,uint32_t first_frame,uint32_t stride,uint32_t pairs);
void husk_ue4_set_frame_generation(bool enabled);
bool tl_vk_framegen_prepare(const char *project,int width,int height);
void tl_vk_framegen_pause(bool paused);
bool tl_vk_framegen_snapshot(tl_fg_stats *out);
#ifdef __cplusplus
}
#endif
#endif
