/* SPDX-License-Identifier: GPL-2.0-or-later
 * Apple MetalFX interpolation boundary. No Vulkan handles or fabricated
 * optical-flow fields are accepted. The caller must own real engine buffers.
 */
#ifndef HUSK_NATIVE_METALFX_H
#define HUSK_NATIVE_METALFX_H
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    uint32_t abi, size, width, height;
    uint32_t color_format, depth_format, motion_format, output_format;
} husk_metalfx_config;
typedef struct {
    uint32_t abi, size;
    void *previous_color, *current_color, *depth, *motion, *output;
    float delta_seconds, motion_scale_x, motion_scale_y;
    float field_of_view, near_plane, far_plane, aspect_ratio;
    bool depth_reversed, reset_history;
} husk_metalfx_inputs;
/* Availability says nothing about engine integration or active interpolation. */
bool husk_native_metalfx_supported(void);
void *husk_native_metalfx_create(void *metal_device, const husk_metalfx_config *config);
bool husk_native_metalfx_encode(void *instance, void *metal_command_buffer,
                                const husk_metalfx_inputs *inputs);
void husk_native_metalfx_destroy(void *instance);
#ifdef __cplusplus
}
#endif
#endif
