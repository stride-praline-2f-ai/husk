/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_METAL4_BRIDGE_H
#define HUSK_METAL4_BRIDGE_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
bool husk_metal4_framegen_requested(void);
void *husk_metal4_framegen_new(void *layer);
void husk_metal4_framegen_delete(void *owner);
void *husk_metal4_framegen_drawable(void *owner, void *layer);
bool husk_metal4_framegen_wait(void *queue, void *drawable);
bool husk_metal4_framegen_signal(void *drawable);
void husk_metal4_framegen_feedback(void *options, void *drawable);
#ifdef __cplusplus
}
#endif
#endif
