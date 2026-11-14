#include <limits.h>
/* Main-thread-only ownership for WebKit completions. Included by the real bridge and host tests. */
typedef NS_ENUM(int, HuskWebPendingKind) {
    HuskWebNavigation, HuskWebAlert, HuskWebConfirm, HuskWebPrompt, HuskWebBridge, HuskWebScheme
};
@interface HuskWebPending : NSObject
@property int owner;
@property HuskWebPendingKind kind;
@property (nonatomic, strong) id value;
@property (nonatomic, copy) void (^cancel)(void);
@property (nonatomic, strong) NSURLSessionTask *network;
@property double deadline;
@end
@implementation HuskWebPending
@end

static NSMutableDictionary<NSNumber *, HuskWebPending *> *g_pending;
static dispatch_source_t g_pending_timer;
static int g_next_call = 1;

static void pending_stop_timer_if_idle(void)
{
    if (!g_pending_timer) return;
    for (HuskWebPending *p in g_pending.allValues) if (p.deadline > 0) return;
    dispatch_source_cancel(g_pending_timer); g_pending_timer = nil;
}
static HuskWebPending *pending_take(int call)
{
    HuskWebPending *p = g_pending[@(call)];
    if (p) [g_pending removeObjectForKey:@(call)];
    pending_stop_timer_if_idle();
    return p;
}
static void pending_cancel(int call)
{
    HuskWebPending *p = pending_take(call);
    if (!p) return;
    NSURLSessionTask *network = p.network; p.network = nil;
    [network cancel];
    if (p.cancel) p.cancel();
}
static void pending_expire(double now)
{
    for (NSNumber *key in g_pending.allKeys) {
        HuskWebPending *p = g_pending[key];
        if (p.deadline > 0 && p.deadline <= now) pending_cancel(key.intValue);
    }
}
static int pending_add(int owner, HuskWebPendingKind kind, id value, double timeout, void (^cancel)(void))
{
    if (!g_pending) g_pending = [NSMutableDictionary dictionary];
    HuskWebPending *p = [HuskWebPending new];
    p.owner = owner; p.kind = kind; p.value = value; p.cancel = cancel;
    p.deadline = timeout > 0 ? NSProcessInfo.processInfo.systemUptime + timeout : 0;
    /* Positive IDs only; never overwrite a live waiter on wraparound. */
    while (g_pending[@(g_next_call)]) g_next_call = g_next_call == INT_MAX ? 1 : g_next_call + 1;
    int call = g_next_call;
    g_next_call = g_next_call == INT_MAX ? 1 : g_next_call + 1;
    g_pending[@(call)] = p;
    if (timeout > 0 && !g_pending_timer) {
        g_pending_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(g_pending_timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
        dispatch_source_set_event_handler(g_pending_timer, ^{ pending_expire(NSProcessInfo.processInfo.systemUptime); });
        dispatch_resume(g_pending_timer);
    }
    return call;
}
static void pending_cancel_owner(int owner)
{
    for (NSNumber *key in g_pending.allKeys) if (g_pending[key].owner == owner) pending_cancel(key.intValue);
}
static void pending_cancel_all(void)
{
    for (NSNumber *key in g_pending.allKeys) pending_cancel(key.intValue);
}
