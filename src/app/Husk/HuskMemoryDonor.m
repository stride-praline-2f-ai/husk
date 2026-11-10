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
#import <UIKit/UIKit.h>
#include "../../translation-layer-next/husk-tl-memory-donor-policy.h"

/* These private extension entry points are already used by built-in StikJIT.
 * If unavailable, preparation fails closed and guest mmap stays ordinary. */
@interface NSExtension : NSObject
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))completion;
- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)identifier;
@end

typedef NS_ENUM(NSInteger, HuskDonationResult) { HuskDonationOK, HuskDonationCapacity, HuskDonationTransport, HuskDonationClientMap };

@interface HuskMemoryDonor : NSObject
@property(nonatomic, strong) NSExtension *extension;
@property(nonatomic, strong) NSUUID *request;
@property(nonatomic, strong) xpc_connection_t listener;
@property(nonatomic, strong) xpc_connection_t peer;
@property(nonatomic, strong) NSMutableArray *backings;
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
    /* Extension APIs belong on the main queue. This failed instance has no
     * live donated mappings; owners with game memory are retained. */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.request && [self.extension respondsToSelector:@selector(cancelExtensionRequestWithIdentifier:)])
            [self.extension cancelExtensionRequestWithIdentifier:self.request];
        self.extension = nil;
    });
}
- (BOOL)connect
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
    return YES;
}
- (HuskDonationResult)donateBytes:(uint64_t)requested
{
    xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(request, "version", 2);
    xpc_dictionary_set_string(request, "op", "reserve");
    xpc_dictionary_set_uint64(request, "bytes", requested);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block xpc_object_t result = nil;
    xpc_connection_send_message_with_reply(self.peer, request, queue, ^(xpc_object_t reply) {
        if (xpc_get_type(reply) == XPC_TYPE_DICTIONARY) result = reply;
        dispatch_semaphore_signal(done);
    });
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC)) || !result) return HuskDonationTransport;
    if (xpc_dictionary_get_uint64(result, "version") != 2) return HuskDonationTransport;
    const char *reason = xpc_dictionary_get_string(result, "reason");
    if (reason) return !strcmp(reason, "capacity") ? HuskDonationCapacity : HuskDonationTransport;
    xpc_object_t shmem = xpc_dictionary_get_value(result, "memory");
    if (!shmem || xpc_get_type(shmem) != XPC_TYPE_SHMEM
        || xpc_dictionary_get_uint64(result, "bytes") != requested) return HuskDonationTransport;
    void *base = NULL;
    size_t bytes = xpc_shmem_map(shmem, &base);
    if (!base || !bytes) return HuskDonationClientMap;
    if (bytes != requested || !tl_memory_reserve_install(base, bytes)) {
        vm_deallocate(mach_task_self(), (vm_address_t)base, bytes); return HuskDonationClientMap;
    }
    if (!self.backings) self.backings = [NSMutableArray array];
    [self.backings addObject:shmem]; /* Preserve backing and its owner, including after pauses. */
    return HuskDonationOK;
}
@end


@interface HuskMemoryCoordinator : NSObject
@property(nonatomic, strong) NSMutableArray<HuskMemoryDonor *> *donors;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic) uint64_t budget;
@property(nonatomic) unsigned failures;
@property(atomic) BOOL pressure;
- (BOOL)prepare;
- (void)enqueueGrowthFor:(size_t)minimum;
@end
static void schedule_growth(void *context, size_t minimum)
{
    /* Allocation thread: enqueue only. No semaphore, IPC or extension startup. */
    [(__bridge HuskMemoryCoordinator *)context enqueueGrowthFor:minimum];
}
@implementation HuskMemoryCoordinator
- (HuskDonationResult)appendBytes:(uint64_t)bytes
{
    for (unsigned attempt = 0; attempt < TL_DONOR_MAX_PROCESSES; attempt++) {
        HuskMemoryDonor *donor = self.donors.lastObject;
        if (!donor) {
            donor = [HuskMemoryDonor new];
            if (![donor connect]) { [donor stop]; return HuskDonationTransport; }
            [self.donors addObject:donor];
        }
        HuskDonationResult result = [donor donateBytes:bytes];
        if (result == HuskDonationOK || result == HuskDonationClientMap) return result;
        /* An empty identical helper is not a reason to spawn a process loop.
         * A used helper can be at its own cap; try another of the same appex. */
        if (!donor.backings.count || self.donors.count >= TL_DONOR_MAX_PROCESSES) return result;
        HuskMemoryDonor *next = [HuskMemoryDonor new];
        if (![next connect]) { [next stop]; return HuskDonationTransport; }
        [self.donors addObject:next];
    }
    return HuskDonationCapacity;
}
- (void)receipt
{
    tl_memory_reserve_stats stats; tl_memory_reserve_snapshot(&stats);
    tl_log_line("memory reserve: %zu MiB shared backing mapped, %zu MiB guest-mapped, %llu served allocations, %lu owner(s); separate from main-process tester/headroom, not RSS or a promised limit",
                stats.mapped_bytes >> 20, stats.used_bytes >> 20,
                (unsigned long long)stats.served_allocations, (unsigned long)self.donors.count);
}
- (BOOL)prepare
{
    self.donors = [NSMutableArray array];
    self.queue = dispatch_queue_create("com.husk.memory-donation", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    HuskDonationResult first = [self appendBytes:MIN(self.budget, TL_DONOR_INITIAL)];
    if (first == HuskDonationCapacity) first = [self appendBytes:TL_DONOR_CHUNK];
    if (first != HuskDonationOK) {
        for (HuskMemoryDonor *donor in self.donors) [donor stop];
        return NO;
    }
    [self receipt];
    __weak HuskMemoryCoordinator *weak = self;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        (void)note; HuskMemoryCoordinator *owner = weak; if (!owner) return;
        owner.pressure = YES;
        dispatch_async(owner.queue, ^{ tl_memory_reserve_set_growth_handler(NULL, NULL); });
    }];
    tl_memory_reserve_set_growth_handler(schedule_growth, (__bridge void *)self);
    return YES;
}
- (void)enqueueGrowthFor:(size_t)minimum
{
    dispatch_async(self.queue, ^{ @autoreleasepool {
        tl_memory_reserve_stats stats; tl_memory_reserve_snapshot(&stats);
        if (self.pressure || stats.mapped_bytes > self.budget || self.budget - stats.mapped_bytes < TL_DONOR_CHUNK) {
            tl_memory_reserve_set_growth_handler(NULL, NULL); return;
        }
        /* The game may have freed memory while this request was queued. */
        if ((!minimum && stats.free_bytes >= TL_DONOR_CHUNK) || (minimum && tl_memory_reserve_can_allocate(minimum))) {
            tl_memory_reserve_growth_finished(); return;
        }
        uint64_t request = MAX((uint64_t)minimum, TL_DONOR_CHUNK);
        request = (request + TL_DONOR_CHUNK - 1) / TL_DONOR_CHUNK * TL_DONOR_CHUNK;
        request = MIN(request, (self.budget - stats.mapped_bytes) / TL_DONOR_CHUNK * TL_DONOR_CHUNK);
        HuskDonationResult result = [self appendBytes:request];
        if (result == HuskDonationOK) {
            self.failures = 0; [self receipt]; tl_memory_reserve_growth_finished();
        } else if (result == HuskDonationClientMap || ++self.failures >= 2) {
            /* More donor processes cannot fix a client VA mapping failure. */
            tl_memory_reserve_set_growth_handler(NULL, NULL);
            tl_log_line("memory reserve: growth stopped; existing shared mappings retained, ordinary mmap fallback available");
        } else {
            /* At most one retry per 30 seconds, driven by later demand. */
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), self.queue, ^{
                if (!self.pressure) tl_memory_reserve_growth_finished();
            });
        }
    }});
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
        uint64_t physical = 0; count = sizeof(physical);
        if (sysctlbyname("hw.memsize", &physical, &count, NULL, 0)) return;
        uint64_t budget = tl_memory_donor_budget(physical);
        if (budget < TL_DONOR_CHUNK) return;
        NSString *file = [[@(game_data_dir) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"settings.json"];
        NSData *json = [NSData dataWithContentsOfFile:file];
        id settings = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
        if ([settings isKindOfClass:NSDictionary.class] && [settings[@"sharedMemoryReserve"] isKindOfClass:NSNumber.class]
            && ![settings[@"sharedMemoryReserve"] boolValue]) return;
        static HuskMemoryCoordinator *coordinator;
        coordinator = [HuskMemoryCoordinator new]; coordinator.budget = budget;
        if (![coordinator prepare]) {
            coordinator = nil;
            tl_log_line("memory reserve: helper unavailable; retaining ordinary guest mmap");
        }
    }
}
