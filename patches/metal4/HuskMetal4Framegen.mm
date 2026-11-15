/* SPDX-License-Identifier: GPL-2.0-or-later
 * The Mesa producer hands over a retained offscreen lease only in its real
 * MTL4CommitOptions GPU-completion feedback. Its CPU present callback cannot
 * publish an unfinished frame. A lease is never given to wait/signalDrawable.
 * The original colour-flow presenter owns output drawables and retirement.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif
#include <atomic>
#include <mutex>
#include "HuskMetal4Bridge.h"
#define HuskFGDrawable HuskMetal4FGDrawable
#define HuskFGPresenter HuskMetal4FGPresenter
#define HuskFGCaptureSession HuskMetal4FGCaptureSession
#define HuskFGCaptureTicket HuskMetal4FGCaptureTicket
#define HUSK_FG_METAL4 1
#include "HuskFramegen.inc"

@interface HuskMetal4FGResidency : NSObject {
@public
    id<MTLResidencySet> _set;
    NSMutableArray *_queues;
    std::mutex _lock;
}
- (instancetype)initWithPresenter:(HuskFGPresenter *)presenter;
- (void)attach:(id<MTL4CommandQueue>)queue;
@end
@implementation HuskMetal4FGResidency
- (instancetype)initWithPresenter:(HuskFGPresenter *)p {
    if(!(self=[super init]))return nil;
    MTLResidencySetDescriptor *d=[MTLResidencySetDescriptor new];d.initialCapacity=4;
    NSError *error=nil;_set=[p->_device newResidencySetWithDescriptor:d error:&error];[d release];
    _queues=[NSMutableArray new];
    if(!_set){[self release];return nil;}
    for(unsigned i=0;i<4;i++)[_set addAllocation:p->_textures[i]];
    [_set commit];[_set requestResidency];return self;
}
- (void)attach:(id<MTL4CommandQueue>)queue {
    std::lock_guard<std::mutex> guard(_lock);
    if(![_queues containsObject:queue]){[queue addResidencySet:_set];[_queues addObject:queue];}
}
- (void)dealloc {
    for(id<MTL4CommandQueue> q in _queues)[q removeResidencySet:_set];
    [_set endResidency];[_set release];[_queues release];[super dealloc];
}
@end

static const void *residencyKey=&residencyKey;
extern "C" bool husk_metal4_framegen_requested(void){return huskFramegenRequested();}
extern "C" void *husk_metal4_framegen_new(void *raw){
    CAMetalLayer *layer=(CAMetalLayer *)raw;
    // A recreated swapchain supersedes output to this layer. Old leases and
    // feedback keep their stopped owner alive until all GPU sampling retires.
    {std::lock_guard<std::mutex> guard(fgManagerLock);
     for(HuskFGPresenter *p:fgOwners)if(p->_layer==layer)[p stop];}
    HuskFGPresenter *p=(HuskFGPresenter *)huskFramegenNew(layer);
    if(!p)return nullptr;
    HuskMetal4FGResidency *residency=[[HuskMetal4FGResidency alloc]initWithPresenter:p];
    if(!residency){huskFramegenDelete(p);fgFail();return nullptr;}
    objc_setAssociatedObject(p,residencyKey,residency,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[residency release];return p;
}
extern "C" void husk_metal4_framegen_delete(void *p){huskFramegenDelete(p);}
extern "C" void *husk_metal4_framegen_drawable(void *p,void *layer){
    // Vulkan callers may have no autorelease pool, or one spanning the entire
    // game loop. Balance the presenter's autoreleased lease here while keeping
    // exactly one owned reference for WSI. Otherwise four finished leases can
    // remain retained until thread exit and permanently exhaust the pool.
    @autoreleasepool {
        return (void *)[huskFramegenDrawable(p,(CAMetalLayer *)layer) retain];
    }
}
extern "C" bool husk_metal4_framegen_wait(void *rawQueue,void *raw){
    id d=(id)raw;if(![d isKindOfClass:[HuskFGDrawable class]])return false;
    HuskFGDrawable *frame=(HuskFGDrawable *)d;
    HuskMetal4FGResidency *r=objc_getAssociatedObject(frame->_owner,residencyKey);
    [r attach:(id<MTL4CommandQueue>)rawQueue];return true;
}
extern "C" bool husk_metal4_framegen_signal(void *raw){return [(id)raw isKindOfClass:[HuskFGDrawable class]];}
extern "C" void husk_metal4_framegen_feedback(void *rawOptions,void *raw){
    if(![(id)raw isKindOfClass:[HuskFGDrawable class]])return;
    HuskFGDrawable *frame=(HuskFGDrawable *)raw;
    MTL4CommitOptions *options=(MTL4CommitOptions *)rawOptions;
    [options addFeedbackHandler:^(id<MTL4CommitFeedback> feedback){@autoreleasepool{
        // Captured frame is retained by the copied MRC block. Producer success
        // means GPU writes finished before another queue samples this lease.
        if(feedback.error){++fgErrors;fgFail();[frame finish:0];}
        else{frame->_sequence=fgRendered.fetch_add(1)+1;frame->_sourceCompletedHost=CACurrentMediaTime();[frame->_owner enqueue:frame];}
    }}];
}
