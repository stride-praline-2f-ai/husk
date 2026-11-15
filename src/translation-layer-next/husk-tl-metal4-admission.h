/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_METAL4_ADMISSION_H
#define HUSK_TL_METAL4_ADMISSION_H
#include <stdbool.h>
/* Public Metal 4 prerequisites, checked once when explicitly requested.
 * Does not load Vulkan, submit GPU work, or claim game/render correctness. */
bool husk_metal4_preflight(void);
#endif
