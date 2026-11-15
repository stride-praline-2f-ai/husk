// SPDX-License-Identifier: GPL-2.0-or-later
// Actual bridge/presenter ownership with controlled producer feedback. No
// invented GPU completion or physical frame-generation performance claim.
#include <cassert>
#include "HuskMetal4Framegen.mm"
@interface ContractFeedback : NSObject
@property(retain) NSError *error;
@end
@implementation ContractFeedback
- (void)dealloc {[_error release];[super dealloc];}
@end
@interface ContractFeedbackOptions : NSObject {NSMutableArray *_blocks;}
- (void)fire:(BOOL)error;
@end
@implementation ContractFeedbackOptions
- (instancetype)init {if((self=[super init]))_blocks=[NSMutableArray new];return self;}
- (void)addFeedbackHandler:(void(^)(id<MTL4CommitFeedback>))handler {id copy=[handler copy];[_blocks addObject:copy];[copy release];}
- (void)fire:(BOOL)error {
    ContractFeedback *f=[ContractFeedback new];if(error)f.error=[NSError errorWithDomain:@"CONTROL-ONLY" code:1 userInfo:nil];
    for(void(^b)(id<MTL4CommitFeedback>) in _blocks)b((id)f);[_blocks removeAllObjects];[f release];
}
- (void)dealloc {[_blocks release];[super dealloc];}
@end
static HuskFGDrawable *lease(HuskFGPresenter *p,unsigned slot){
    HuskFGDrawable *d=[HuskFGDrawable new];d->_owner=[p retain];d->_slot=slot;d->_epoch=p->_epoch.load();p->_used[slot]=true;return d;
}
int main(){@autoreleasepool{
    tl_fg_config config={1,sizeof(config),0,1816,1280,0};assert(vkHuskFramegenConfigure(&config));
    config.version++;assert(!vkHuskFramegenConfigure(&config));config.version--;
    HuskFGPresenter *p=[HuskFGPresenter new];p->_work=dispatch_queue_create("com.husk.contract",DISPATCH_QUEUE_SERIAL);
    // Reproduce build165's C acquire boundary on a thread whose outer pool
    // spans the game loop: releasing the caller's ownership cannot drain the
    // extra autoreleased lease. The original four-slot pool then stalls.
    @autoreleasepool {
        for(unsigned i=0;i<4;i++){
            id oldBoundary=[huskFramegenDrawable(p,nil) retain];assert(oldBoundary);
            [oldBoundary release];assert(p->_used[i]);
        }
        assert(!huskFramegenDrawable(p,nil));
    }
    for(unsigned i=0;i<4;i++)assert(!p->_used[i]);
    // Exercise the real C bridge repeatedly inside one long-lived outer pool.
    // WSI's release must return every completed lease without a caller drain.
    for(unsigned i=0;i<32;i++){
        auto *owned=(HuskFGDrawable *)husk_metal4_framegen_drawable(p,nullptr);
        assert(owned);assert(p->_used[owned->_slot]);
        auto *completion=[ContractFeedbackOptions new];
        husk_metal4_framegen_feedback(completion,owned);
        [owned present];assert(!p->_ready.count);
        [completion fire:NO];dispatch_sync(p->_work,^{});assert(p->_ready.count==1);
        dispatch_sync(p->_work,^{[p resetHistory];});
        [owned release];[completion release];
        for(unsigned slot=0;slot<4;slot++)assert(!p->_used[slot]);
    }
    fgRendered=0;fgDropped=0;
    HuskFGDrawable *frame=lease(p,0);ContractFeedbackOptions *opt=[ContractFeedbackOptions new];
    husk_metal4_framegen_feedback(opt,frame);
    assert(fgRendered==0&&p->_ready.count==0); // CPU submission cannot publish.
    [frame present];assert(fgRendered==0&&p->_ready.count==0); // CPU present cannot publish.
    assert(husk_metal4_framegen_wait(nullptr,frame));assert(husk_metal4_framegen_signal(frame));
    NSObject *ordinary=[NSObject new];assert(!husk_metal4_framegen_signal(ordinary));[ordinary release];
    [opt fire:NO];dispatch_sync(p->_work,^{});assert(fgRendered==1&&p->_ready.count==1);
    __block unsigned callbacks=0;[frame addPresentedHandler:^(id<MTLDrawable>d){(void)d;callbacks++;}];
    [frame finish:0];[frame finish:0];assert(callbacks==1);
    dispatch_sync(p->_work,^{[p resetHistory];});[frame release];[opt release];assert(!p->_used[0]);
    // Pause/resize epoch invalidates a completed producer's old lease.
    frame=lease(p,1);opt=[ContractFeedbackOptions new];husk_metal4_framegen_feedback(opt,frame);p->_epoch.fetch_add(1);
    [opt fire:NO];dispatch_sync(p->_work,^{});assert(!p->_ready.count&&frame->_finished&&fgDropped>0);
    [frame release];[opt release];assert(!p->_used[1]);
    // A real producer error retires once, marks failure and never enqueues.
    frame=lease(p,2);opt=[ContractFeedbackOptions new];husk_metal4_framegen_feedback(opt,frame);
    [opt fire:YES];dispatch_sync(p->_work,^{});assert(!p->_ready.count&&frame->_finished&&fgFailed&&fgErrors==1);
    [frame release];[opt release];[p release];
    puts("PASS: production Metal4 feedback/lease/error/epoch contracts; controlled feedback, physical GPU output unverified");return 0;
}}
