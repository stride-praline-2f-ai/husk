/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "husk-tl-metal4-admission.h"
#include <dispatch/dispatch.h>
void tl_log_line(const char *fmt, ...);
/* NX18/Henge use the GPU family and concrete queue/compiler/residency objects,
 * not just respondsToSelector:. Keep MoltenVK available when these fail. */
bool husk_metal4_preflight(void) {
    static dispatch_once_t once;
    static bool ready;
    dispatch_once(&once, ^{
        @autoreleasepool {
            const char *reason = "Metal 4 requires iOS/macOS 26 and an appropriate SDK";
#if (defined(__IPHONE_26_0) || defined(__MAC_26_0))
            if (@available(iOS 26.0, macOS 26.0, *)) {
                id<MTLDevice> device = MTLCreateSystemDefaultDevice();
                reason = "Metal 4 GPU family unavailable";
                if ([device supportsFamily:MTLGPUFamilyMetal4]) {
                    NSError *error = nil;
                    id<MTL4CommandQueue> queue = [device newMTL4CommandQueueWithDescriptor:[MTL4CommandQueueDescriptor new] error:&error];
                    id<MTL4Compiler> compiler = [device newCompilerWithDescriptor:[MTL4CompilerDescriptor new] error:&error];
                    id<MTL4CommandAllocator> allocator = [device newCommandAllocatorWithDescriptor:[MTL4CommandAllocatorDescriptor new] error:&error];
                    MTLResidencySetDescriptor *rd = [MTLResidencySetDescriptor new]; rd.initialCapacity = 1;
                    id<MTLResidencySet> residency = [device newResidencySetWithDescriptor:rd error:&error];
                    MTL4ArgumentTableDescriptor *td = [MTL4ArgumentTableDescriptor new];
                    td.maxBufferBindCount = 1; td.maxTextureBindCount = 1; td.maxSamplerStateBindCount = 1;
                    id<MTL4ArgumentTable> table = [device newArgumentTableWithDescriptor:td error:&error];
                    id<MTLSharedEvent> event = [device newSharedEvent];
                    ready = queue && compiler && allocator && residency && table && event;
                    reason = ready ? "family/queue/compiler/allocator/residency/arguments/event available" : "required Metal 4 object creation failed";
                }
            }
#endif
            tl_log_line("[NX18-HENGE-A20-v1] Metal 4 admission: %s; %s; actual Dungeons rendering/energy pending", ready ? "passed" : "declined", reason);
        }
    });
    return ready;
}
