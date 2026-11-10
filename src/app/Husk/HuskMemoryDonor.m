/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "HuskMemoryDonorProtocol.h"
#include "../../translation-layer-next/husk-tl-memory-reserve.h"
#include "../../translation-layer-next/husk-tl-bionic.h"
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <stdatomic.h>
#include <TargetConditionals.h>
#include <string.h>
#include <dlfcn.h>

/* These private extension entry points are already used by built-in StikJIT.
 * If unavailable, preparation fails closed and guest mmap stays ordinary. */
@interface NSExtension : NSObject
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))completion;
- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)identifier;
@end

@interface HuskMemoryDonor : NSObject
@property(nonatomic, strong) NSExtension *extension;
@property(nonatomic, strong) NSUUID *request;
@property(nonatomic, strong) xpc_connection_t listener;
@property(nonatomic, strong) xpc_connection_t peer;
@property(nonatomic, strong) xpc_object_t backing;
@property(nonatomic, strong) NSString *nonce;
@property(nonatomic, strong) dispatch_semaphore_t ready;
@property(nonatomic) BOOL abandoned;
@end

@implementation HuskMemoryDonor
- (void)stop
{
    @synchronized(self) {
        self.abandoned = YES;
        if (self.peer) xpc_connection_cancel(self.peer);
        if (self.listener) xpc_connection_cancel(self.listener);
    }
    /* Extension APIs belong on the main queue. No guest is running yet. */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.request && [self.extension respondsToSelector:@selector(cancelExtensionRequestWithIdentifier:)])
            [self.extension cancelExtensionRequestWithIdentifier:self.request];
        self.extension = nil;
    });
}
- (BOOL)prepare
{
    NSURL *helper = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"HuskMemoryDonor.appex"];
    if (!helper || ![NSFileManager.defaultManager fileExistsAtPath:helper.path]) return NO;
    self.ready = dispatch_semaphore_create(0);
    self.nonce = NSUUID.UUID.UUIDString;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    self.listener = xpc_connection_create(NULL, queue);
    if (!self.listener) return NO;
    __weak HuskMemoryDonor *weak = self;
    xpc_connection_set_event_handler(self.listener, ^(xpc_object_t event) {
        if (xpc_get_type(event) != XPC_TYPE_CONNECTION) return;
        xpc_connection_t connection = (xpc_connection_t)event;
        xpc_connection_set_event_handler(connection, ^(xpc_object_t message) {
            HuskMemoryDonor *owner = weak;
            if (!owner) { xpc_connection_cancel(connection); return; }
            if (xpc_get_type(message) == XPC_TYPE_DICTIONARY) {
                const char *nonce = xpc_dictionary_get_string(message, "nonce");
                @synchronized(owner) {
                    if (!owner.abandoned && !owner.peer && nonce && [owner.nonce isEqualToString:@(nonce)]) {
                        owner.peer = connection;
                        dispatch_semaphore_signal(owner.ready);
                    }
                }
            }
        });
        xpc_connection_resume(connection);
    });
    xpc_connection_resume(self.listener);
    NSXPCListenerEndpoint *endpoint = [NSXPCListenerEndpoint new];
    if (![endpoint respondsToSelector:@selector(_setEndpoint:)]) return NO;
    endpoint._endpoint = xpc_endpoint_create(self.listener);
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized(self) { if (self.abandoned) return; }
        Class cls = NSClassFromString(@"NSExtension");
        if (!cls) {
            /* Same lazy framework route as Husk built-in JIT; external
             * StikDebug launches may never have loaded it. */
            dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_NOW);
            cls = NSClassFromString(@"NSExtension");
        }
        NSError *error = nil;
        NSString *identifier = [NSBundle.mainBundle.bundleIdentifier stringByAppendingString:@".MemoryDonor"];
        if (![cls respondsToSelector:@selector(extensionWithIdentifier:error:)]) { dispatch_semaphore_signal(self.ready); return; }
        self.extension = [cls extensionWithIdentifier:identifier error:&error];
        if (![self.extension respondsToSelector:@selector(beginExtensionRequestWithInputItems:completion:)]) { dispatch_semaphore_signal(self.ready); return; }
        NSExtensionItem *item = [NSExtensionItem new];
        item.userInfo = @{ @"endpoint": endpoint, @"nonce": self.nonce };
        [self.extension beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *request) {
            self.request = request;
            @synchronized(self) { if (self.abandoned) [self stop]; }
        }];
    });
    if (dispatch_semaphore_wait(self.ready, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC))) return NO;
    if (!self.peer) return NO;
    xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(request, "op", "reserve");
    xpc_dictionary_set_uint64(request, "bytes", 256ull << 20);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block xpc_object_t result = nil;
    xpc_connection_send_message_with_reply(self.peer, request, queue, ^(xpc_object_t reply) {
        if (xpc_get_type(reply) == XPC_TYPE_DICTIONARY) result = reply;
        dispatch_semaphore_signal(done);
    });
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC)) || !result) return NO;
    xpc_object_t shmem = xpc_dictionary_get_value(result, "memory");
    if (!shmem || xpc_get_type(shmem) != XPC_TYPE_SHMEM) return NO;
    void *base = NULL;
    size_t bytes = xpc_shmem_map(shmem, &base);
    if (!base || !bytes) return NO;
    if (!tl_memory_reserve_install(base, bytes)) { vm_deallocate(mach_task_self(), (vm_address_t)base, bytes); return NO; }
    self.backing = shmem; /* Both mapping and owner stay alive for the process. */
    tl_log_line("memory reserve: %zu MiB shared game memory; no GPU/JIT donation, no virtual-address-limit guarantee", bytes >> 20);
    return YES;
}
@end

void husk_memory_donor_prepare(const char *game_data_dir)
{
    static atomic_bool attempted;
    if (atomic_exchange(&attempted, true) || !game_data_dir || NSThread.isMainThread) return;
    @autoreleasepool {
    /* Preserve the protected iPad baseline. Phones may opt out per game. */
    char model[64] = {0}; size_t count = sizeof(model);
    if (sysctlbyname("hw.machine", model, &count, NULL, 0) || strncmp(model, "iPhone", 6)) return;
    NSString *data = @(game_data_dir);
    NSString *file = [[data stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"settings.json"];
    NSData *json = [NSData dataWithContentsOfFile:file];
    id settings = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if ([settings isKindOfClass:NSDictionary.class] && [settings[@"sharedMemoryReserve"] isKindOfClass:NSNumber.class]
        && ![settings[@"sharedMemoryReserve"] boolValue]) return;
    static HuskMemoryDonor *donor;
    donor = [HuskMemoryDonor new];
    if (![donor prepare]) {
        [donor stop]; donor = nil;
        tl_log_line("memory reserve: helper unavailable; retaining ordinary guest mmap");
    }
    }
}
