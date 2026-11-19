/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_RENDER_INVENTORY_H
#define HUSK_TL_RENDER_INVENTORY_H
#include <stdbool.h>
#include <stdint.h>
/* Requested base fields only; no GPU reads or proof of scene/HUD contents. */
typedef struct { uint32_t kind,width,height,depth,format,usage,samples; uint64_t count; } tl_ri_group;
typedef struct {
    bool requested,active;
    uint64_t observed_images,observed_render_areas,dropped;
    uint64_t dropped_capacity,dropped_contention,hash_probes;
    uint32_t asset_groups,target_groups,area_groups;
} tl_ri_stats;
/* Advisory format/usage/extent screen only. These counters CANNOT prove that
 * an image holds Unreal scene velocity or depth at presentation time.
 * Never admit MetalFX frame interpolation using this result alone. */
typedef struct {
    uint32_t version, size;
    bool active;
    uint32_t depth_attachment_groups, readable_depth_groups;
    uint32_t vector_format_groups, writable_vector_groups;
    uint32_t renderable_color_groups, readable_color_groups;
    uint64_t retained_image_groups, lost_observations;
} tl_ri_metalfx_candidates;
void tl_ri_metalfx_snapshot(tl_ri_metalfx_candidates *out);

void husk_ue4_set_render_inventory(bool value);
void tl_ri_activate(const char *project);
bool tl_ri_active(void);
void tl_ri_image(const void *create_info);
void tl_ri_render_area(const void *begin_info);
uint32_t tl_ri_snapshot(tl_ri_group *out,uint32_t capacity,tl_ri_stats *stats);
#endif
