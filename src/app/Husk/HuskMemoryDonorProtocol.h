/* SPDX-License-Identifier: GPL-2.0-or-later
 * Shared-memory donor mechanism inspired by MeloNX 2.7 (Stossy11).
 * Independently implemented for Husk; see docs/performance/43-memory-resilience.md. */
#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
@interface NSXPCListenerEndpoint (HuskMemoryEndpoint)
@property(nonatomic, setter=_setEndpoint:) xpc_object_t _endpoint;
@end
