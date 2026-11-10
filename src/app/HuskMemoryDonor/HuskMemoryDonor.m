/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "../Husk/HuskMemoryDonorProtocol.h"
#include <mach/mach.h>
#include <os/proc.h>
#include <objc/runtime.h>
#include <string.h>
#include <stdlib.h>
#ifndef VM_FLAGS_PURGABLE
#define VM_FLAGS_PURGABLE 0x2
#endif

/* Allow only the endpoint transport class that the private extension decoder
 * otherwise refuses. All other validation continues through Apple's original
 * implementation. Never replace validation with an unconditional no-op. */
static IMP validate_original;
static void validate_endpoint(id self, SEL cmd, Class cls, id key, BOOL invocations)
{
    if (cls == NSXPCListenerEndpoint.class) return;
    ((void (*)(id, SEL, Class, id, BOOL))validate_original)(self, cmd, cls, key, invocations);
}
__attribute__((constructor)) static void endpoint_transport(void)
{
    Class decoder = NSClassFromString(@"NSXPCDecoder");
    Method method = class_getInstanceMethod(decoder, NSSelectorFromString(@"_validateAllowedClass:forKey:allowingInvocations:"));
    char result[16] = {0}, cls[16] = {0}, key[16] = {0}, flag[16] = {0};
    if (method) {
        method_getReturnType(method, result, sizeof(result));
        method_getArgumentType(method, 2, cls, sizeof(cls));
        method_getArgumentType(method, 3, key, sizeof(key));
        method_getArgumentType(method, 4, flag, sizeof(flag));
    }
    if (method && method_getNumberOfArguments(method) == 5 && result[0] == 'v'
        && cls[0] == '#' && key[0] == '@' && (flag[0] == 'B' || flag[0] == 'c'))
        validate_original = method_setImplementation(method, (IMP)validate_endpoint);
}

@interface HuskMemoryDonorHandler : NSObject <NSExtensionRequestHandling>
@property(nonatomic, strong) xpc_connection_t channel;
@property(nonatomic, strong) xpc_object_t memory;
@property(nonatomic) vm_address_t base;
@property(nonatomic) size_t bytes;
@end
@implementation HuskMemoryDonorHandler
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context
{
    NSExtensionItem *item = context.inputItems.firstObject;
    if (![item isKindOfClass:NSExtensionItem.class]) return;
    id endpoint = item.userInfo[@"endpoint"], nonce = item.userInfo[@"nonce"];
    if (![endpoint isKindOfClass:NSXPCListenerEndpoint.class] || ![nonce isKindOfClass:NSString.class]) return;
    if (![endpoint respondsToSelector:@selector(_endpoint)]) return;
    xpc_object_t raw = [(NSXPCListenerEndpoint *)endpoint _endpoint];
    if (!raw || xpc_get_type(raw) != XPC_TYPE_ENDPOINT) return;
    self.channel = xpc_connection_create_from_endpoint(raw);
    if (!self.channel) return;
    xpc_connection_set_target_queue(self.channel, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    xpc_connection_set_event_handler(self.channel, ^(xpc_object_t request) {
        if (xpc_get_type(request) == XPC_TYPE_ERROR) { exit(0); }
        if (xpc_get_type(request) != XPC_TYPE_DICTIONARY) return;
        xpc_object_t reply = xpc_dictionary_create_reply(request);
        if (!reply) return;
        const char *op = xpc_dictionary_get_string(request, "op");
        uint64_t bytes = xpc_dictionary_get_uint64(request, "bytes");
        /* One non-volatile region, with 256 MiB donor headroom. Never grow in a
         * gameplay loop, touch it eagerly, or report a grant before it exists. */
        if (op && !strcmp(op, "reserve") && bytes == (256ull << 20) && !self.memory
            && os_proc_available_memory() >= bytes + (256ull << 20)) {
            vm_address_t base = 0;
            if (vm_allocate(mach_task_self(), &base, bytes, VM_FLAGS_ANYWHERE | VM_FLAGS_PURGABLE) == KERN_SUCCESS) {
                xpc_object_t memory = xpc_shmem_create((void *)base, bytes);
                if (memory) { self.memory = memory; self.base = base; self.bytes = bytes; }
                else vm_deallocate(mach_task_self(), base, bytes);
            }
        }
        if (self.memory) xpc_dictionary_set_value(reply, "memory", self.memory);
        xpc_connection_send_message(self.channel, reply);
    });
    xpc_connection_resume(self.channel);
    xpc_object_t hello = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(hello, "nonce", [nonce UTF8String]);
    xpc_connection_send_message(self.channel, hello);
}
@end
