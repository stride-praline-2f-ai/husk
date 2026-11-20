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
    /* Capacity loss counted by resource class; excludes lock contention. */
    uint64_t dropped_capacity_assets,dropped_capacity_targets,dropped_capacity_areas;
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
    /* Asset-only overflow must not automatically invalidate retained
     * attachment-format evidence; all results remain metadata-only. */
    uint64_t lost_asset_observations,lost_target_observations;
    uint64_t lost_render_area_observations,lost_contention_observations;
} tl_ri_metalfx_candidates;
void tl_ri_metalfx_snapshot(tl_ri_metalfx_candidates *out);

/* 0=off, 1=lightweight image allocations only, 2=explicit full inventory.
 * Mode 1 never wraps or samples per-frame renderpass calls. */
void husk_ue4_set_render_inventory_mode(uint32_t mode);
bool tl_ri_area_active(void);
uint32_t tl_ri_inventory_mode(void);
void husk_ue4_set_render_inventory(bool value);
void tl_ri_activate(const char *project);
bool tl_ri_active(void);
/* Bounded create-time Vulkan object lineage, not pixels or GPU completion.
 * Default Dungeons image-only mode traces allocations/views/framebuffers, with
 * NO per-frame command interception. Full mode alone samples render-pass uses.
 * Passing Vulkan handles never transfers ownership to MetalFX. */
typedef struct {
    uint32_t version, size;
    uint64_t tracked_target_images, tracked_target_views, tracked_framebuffers;
    uint64_t depth_framebuffers, vector_like_framebuffers, mixed_depth_vector_framebuffers;
    uint64_t used_depth_framebuffers, used_vector_like_framebuffers;
    uint64_t missing_image_view_links, missing_framebuffer_view_links, dropped_records;
} tl_ri_lineage_stats;
void tl_ri_image_created(void *device,uint64_t image,const void *create_info);
void tl_ri_image_destroyed(void *device,uint64_t image);
void tl_ri_view_created(void *device,uint64_t view,const void *create_info);
void tl_ri_view_destroyed(void *device,uint64_t view);
void tl_ri_framebuffer_created(void *device,uint64_t framebuffer,const void *create_info);
void tl_ri_framebuffer_destroyed(void *device,uint64_t framebuffer);
void tl_ri_pass_begin(const void *begin_info);
void tl_ri_lineage_snapshot(tl_ri_lineage_stats *out);
void tl_ri_image(const void *create_info);
void tl_ri_render_area(const void *begin_info);
uint32_t tl_ri_snapshot(tl_ri_group *out,uint32_t capacity,tl_ri_stats *stats);
#endif
