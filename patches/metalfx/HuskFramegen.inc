/* SPDX-License-Identifier: Apache-2.0
 * Optional colour-only optical-flow presentation for the pinned MoltenVK WSI.
 * Fake drawables below are host-owned offscreen leases. They are NEVER passed
 * to a Metal command queue/present API: only real CAMetalLayer drawables are.
 * The pinned WSI calls their public present methods from scheduled handlers.
 */
#include "HuskFramegenABI.h"
#include "HuskFramegenShader.inc"
#include <condition_variable>
#include <chrono>
#include <vector>
#include <algorithm>
#if TARGET_OS_IOS
#import <QuartzCore/CADisplayLink.h>
#include <os/proc.h>
static std::mutex fgManagerLock;
static tl_fg_config fgConfig={};
static std::atomic<bool> fgPaused{false},fgFailed{false};
static std::atomic<uint64_t> fgRendered{0},fgGenerated{0},fgReal{0},fgDropped{0},fgResets{0},fgErrors{0};
@class HuskFGPresenter;
static std::vector<HuskFGPresenter*> fgOwners;
extern "C" void vkHuskFramegenPause(int);
static void fgFail(){fgFailed=true;vkHuskFramegenPause(1);}
@interface HuskFGDrawable : NSObject<CAMetalDrawable> {
@public
    HuskFGPresenter* _owner;
    unsigned _slot;
    uint64_t _epoch;
    std::mutex _handlersLock;
    NSMutableArray* _handlers;
    bool _finished;
    CFTimeInterval _presented;
}
- (void)finish:(CFTimeInterval)time;
@end
@interface HuskFGPresenter : NSObject {
@public
    CAMetalLayer* _layer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLComputePipelineState> _flowPSO,_interpolatePSO,_copyPSO;
    id<MTLTexture> _textures[4],_forward,_backward,_motionPrevious,_motionCurrent;
    std::mutex _poolLock;
    std::condition_variable _poolWake;
    bool _used[4];
    std::atomic<bool> _stopped,_paused,_tickPending;
    std::atomic<unsigned> _inFlight;
    std::atomic<uint64_t> _epoch;
    dispatch_queue_t _work;
    CADisplayLink* _link;
    NSMutableArray* _ready;
    HuskFGDrawable* _previous;
    HuskFGDrawable* _current;
    bool _realNext;
    double _lastInput;
}
- (instancetype)initWithLayer:(CAMetalLayer*)layer config:(tl_fg_config)c;
- (void)resetHistory;
- (void)stop;
- (void)tick:(CADisplayLink*)link;
- (void)drawTick;
- (void)enqueue:(HuskFGDrawable*)frame;
- (BOOL)encodePrevious:(HuskFGDrawable*)previous current:(HuskFGDrawable*)current generated:(BOOL)generated;
@end

@implementation HuskFGDrawable
- (instancetype)init { if((self=[super init]))_handlers=[NSMutableArray new]; return self; }
- (id<MTLTexture>)texture { return _owner->_textures[_slot]; }
- (CAMetalLayer*)layer { return _owner->_layer; }
- (NSUInteger)drawableID { return (NSUInteger)self; }
- (CFTimeInterval)presentedTime { std::lock_guard<std::mutex> l(_handlersLock);return _presented; }
// Presentation is driven by GPU completion + the display clock, never by the
// WSI's CPU scheduled callback, which can precede GPU writes to this texture.
- (void)present {}
- (void)presentAtTime:(CFTimeInterval)t { (void)t; }
- (void)presentAfterMinimumDuration:(CFTimeInterval)t { (void)t; }
- (void)addPresentedHandler:(MTLDrawablePresentedHandler)handler {
    bool done;
    {std::lock_guard<std::mutex> l(_handlersLock);done=_finished;if(!done){id b=[handler copy];[_handlers addObject:b];[b release];}}
    if(done)handler(self);
}
- (void)finish:(CFTimeInterval)time {
    NSArray* handlers;
    {std::lock_guard<std::mutex> l(_handlersLock);if(_finished)return;_finished=true;_presented=time;handlers=[_handlers copy];[_handlers removeAllObjects];}
    for(MTLDrawablePresentedHandler block in handlers)block(self);
    [handlers release];
}
- (void)dealloc {
    [self finish:0];
    if(_owner){
        {std::lock_guard<std::mutex> l(_owner->_poolLock);_owner->_used[_slot]=false;}
        _owner->_poolWake.notify_all();[_owner release];
    }
    [_handlers release];[super dealloc];
}
@end

static uint64_t fgStorageBytes(unsigned w,unsigned h){
    uint64_t sources=uint64_t(w)*h*16,mips=0;
    uint64_t flow=uint64_t((w+15)/16)*((h+15)/16)*16;
    for(;;){mips+=uint64_t(w)*h*4;if(w==1&&h==1)break;w=std::max(1u,w/2);h=std::max(1u,h/2);}
    return sources+2*mips+flow;
}
static id<MTLTexture> fgTexture(id<MTLDevice> device,NSUInteger w,NSUInteger h,MTLPixelFormat fmt,bool mipmapped=false){
    MTLTextureDescriptor* d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:fmt width:w height:h mipmapped:mipmapped];
    d.storageMode=MTLStorageModePrivate;d.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;
    return [device newTextureWithDescriptor:d];
}
static void fgDispatch(id<MTLComputeCommandEncoder> e,id<MTLComputePipelineState> p,NSUInteger w,NSUInteger h){
    [e setComputePipelineState:p];[e dispatchThreads:MTLSizeMake(w,h,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
}
@implementation HuskFGPresenter
- (instancetype)init {
    if((self=[super init])){_stopped=false;_paused=false;_tickPending=false;_inFlight=0;_epoch=1;_ready=[NSMutableArray new];}
    return self;
}
- (instancetype)initWithLayer:(CAMetalLayer*)layer config:(tl_fg_config)c {
    if(!(self=[self init]))return nil;
    _layer=[layer retain];_device=[layer.device retain];_epoch=1;_paused=fgPaused.load();
    _work=dispatch_queue_create("com.husk.frame-generation",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_USER_INITIATED,0));
    if(!_device||layer.pixelFormat!=MTLPixelFormatBGRA8Unorm||layer.drawableSize.width!=c.width||layer.drawableSize.height!=c.height){[self release];return nil;}
    if(os_proc_available_memory() < (384ULL<<20)){[self release];return nil;}
    NSError* error=nil;
    MTLCompileOptions* options=[MTLCompileOptions new];options.fastMathEnabled=NO;
    id<MTLLibrary> lib=[_device newLibraryWithSource:[NSString stringWithUTF8String:huskFramegenShader] options:options error:&error];[options release];
    if(lib){
        id<MTLFunction> flow=[lib newFunctionWithName:@"huskFlow"],interp=[lib newFunctionWithName:@"huskInterpolate"],copy=[lib newFunctionWithName:@"huskCopyFrame"];
        if(flow)_flowPSO=[_device newComputePipelineStateWithFunction:flow error:&error];
        if(interp)_interpolatePSO=[_device newComputePipelineStateWithFunction:interp error:&error];
        if(copy)_copyPSO=[_device newComputePipelineStateWithFunction:copy error:&error];
        [flow release];[interp release];[copy release];[lib release];
    }
    _queue=[_device newCommandQueue];
    for(unsigned i=0;i<4;i++)_textures[i]=fgTexture(_device,c.width,c.height,MTLPixelFormatBGRA8Unorm);
    // Private motion-only scratch leaves guest/WSI texture levels unchanged.
    // No CPU readback, queue-idle wait or new lease lifetime is introduced.
    _motionPrevious=fgTexture(_device,c.width,c.height,MTLPixelFormatBGRA8Unorm,true);
    _motionCurrent=fgTexture(_device,c.width,c.height,MTLPixelFormatBGRA8Unorm,true);
    NSUInteger fw=(c.width+15)/16,fh=(c.height+15)/16;
    _forward=fgTexture(_device,fw,fh,MTLPixelFormatRGBA16Float);_backward=fgTexture(_device,fw,fh,MTLPixelFormatRGBA16Float);
    if(!_queue||!_flowPSO||!_interpolatePSO||!_copyPSO||!_textures[0]||!_textures[1]||!_textures[2]||!_textures[3]||!_forward||!_backward||!_motionPrevious||!_motionCurrent){[self release];return nil;}
    dispatch_async(dispatch_get_main_queue(),^{
        if(_stopped.load())return;
        _link=[[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];
        _link.preferredFrameRateRange=CAFrameRateRangeMake(60,60,60);
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    });
    return self;
}
- (void)resetHistory {
    [_previous finish:0];[_previous release];_previous=nil;
    [_current finish:0];[_current release];_current=nil;
    for(HuskFGDrawable* f in _ready){++fgDropped;[f finish:0];}
    [_ready removeAllObjects];_realNext=false;_lastInput=0;++fgResets;
}
- (void)stop {
    _stopped=true;_epoch.fetch_add(1);_poolWake.notify_all();
    dispatch_async(dispatch_get_main_queue(),^{[_link invalidate];[_link release];_link=nil;});
    dispatch_async(_work,^{[self resetHistory];});
}
- (void)tick:(CADisplayLink*)link {
    (void)link;
    if(_stopped.load()||_paused.load()||fgFailed.load())return;
    bool expected=false;if(!_tickPending.compare_exchange_strong(expected,true))return;
    dispatch_async(_work,^{@autoreleasepool{[self drawTick];_tickPending=false;}});
}
- (void)enqueue:(HuskFGDrawable*)frame {
    dispatch_async(_work,^{@autoreleasepool{
        if(_stopped.load()||_paused.load()||fgFailed.load()||frame->_epoch!=_epoch.load()){++fgDropped;[frame finish:0];return;}
        while(_ready.count>=2){HuskFGDrawable* old=[[_ready objectAtIndex:0] retain];[_ready removeObjectAtIndex:0];++fgDropped;[old finish:0];[old release];}
        [_ready addObject:frame];
    }});
}
- (void)drawTick {
    if(_stopped.load()||_paused.load()||fgFailed.load()||_inFlight.load()>=2)return;
    if(_realNext){
        if(![self encodePrevious:nil current:_current generated:NO])return;
        [_previous release];_previous=_current;_current=nil;_realNext=false;return;
    }
    if(!_ready.count)return;
    HuskFGDrawable* next=[[_ready objectAtIndex:0] retain];
    double now=CACurrentMediaTime();bool fresh=(_lastInput>0 && now-_lastInput<0.15);
    BOOL generated=(_previous && fresh);
    if(![self encodePrevious:_previous current:next generated:generated]){[next release];return;}
    [_ready removeObjectAtIndex:0];_lastInput=now;
    if(generated){_current=next;_realNext=true;}
    else{[_previous release];_previous=next;}
}
- (BOOL)encodePrevious:(HuskFGDrawable*)previous current:(HuskFGDrawable*)current generated:(BOOL)generated {
    if(!current)return NO;
    uint64_t epoch=_epoch.load();
    id<CAMetalDrawable> drawable=[_layer nextDrawable];
    if(!drawable||_stopped.load()||_paused.load()||epoch!=_epoch.load())return NO;
    id<MTLTexture> output=drawable.texture;
    if(output.pixelFormat!=MTLPixelFormatBGRA8Unorm||output.width!=current.texture.width||output.height!=current.texture.height){fgFail();[self resetHistory];return NO;}
    id<MTLCommandBuffer> command=[_queue commandBuffer];if(!command)return NO;
    if(generated){
        id<MTLBlitCommandEncoder> reduce=[command blitCommandEncoder];if(!reduce)return NO;
        for(unsigned image=0;image<2;image++){
            id<MTLTexture> source=image?current.texture:previous.texture;
            id<MTLTexture> pyramid=image?_motionCurrent:_motionPrevious;
            [reduce copyFromTexture:source sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
                sourceSize:MTLSizeMake(source.width,source.height,1) toTexture:pyramid destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
            [reduce generateMipmapsForTexture:pyramid];
        }
        [reduce endEncoding];
        for(unsigned reverse=0;reverse<2;reverse++){
            id<MTLComputeCommandEncoder> e=[command computeCommandEncoder];
            [e setTexture:reverse?_motionCurrent:_motionPrevious atIndex:0];
            [e setTexture:reverse?_motionPrevious:_motionCurrent atIndex:1];
            [e setTexture:reverse?_backward:_forward atIndex:2];
            fgDispatch(e,_flowPSO,_forward.width,_forward.height);[e endEncoding];
        }
        id<MTLComputeCommandEncoder> e=[command computeCommandEncoder];
        [e setTexture:previous.texture atIndex:0];[e setTexture:current.texture atIndex:1];
        [e setTexture:_forward atIndex:2];[e setTexture:_backward atIndex:3];[e setTexture:output atIndex:4];
        fgDispatch(e,_interpolatePSO,output.width,output.height);[e endEncoding];
    }else{
        id<MTLComputeCommandEncoder> e=[command computeCommandEncoder];[e setTexture:current.texture atIndex:0];[e setTexture:output atIndex:1];
        fgDispatch(e,_copyPSO,output.width,output.height);[e endEncoding];
    }
    _inFlight.fetch_add(1);
    [drawable addPresentedHandler:^(id<MTLDrawable> displayed){
        (void)displayed;if(generated)++fgGenerated;else ++fgReal;
    }];
    // Capture both leases until the GPU has finished sampling them; MRC heap
    // blocks retain captured Objective-C objects independently of history reset.
    [command addCompletedHandler:^(id<MTLCommandBuffer> completed){
        (void)previous.texture;(void)current.texture;
        if(completed.status==MTLCommandBufferStatusError){++fgErrors;fgFail();}
        // WSI leases retire on GPU completion even if an OS presentation
        // callback stalls. A zero timestamp explicitly means unavailable;
        // actual output counts come from the real drawable callback above.
        if(!generated || completed.status==MTLCommandBufferStatusError)[current finish:0];
        _inFlight.fetch_sub(1);
    }];
    [command presentDrawable:drawable];[command commit];return YES;
}
- (void)dealloc {
    for(unsigned i=0;i<4;i++)[_textures[i] release];
    [_forward release];[_backward release];[_flowPSO release];[_interpolatePSO release];[_copyPSO release];
    [_motionPrevious release];[_motionCurrent release];
    [_queue release];[_device release];[_layer release];[_ready release];
    [_previous release];[_current release];
#if OS_OBJECT_USE_OBJC
    [(id)_work release];
#else
    if(_work)dispatch_release(_work);
#endif
    [super dealloc];
}
@end

extern "C" __attribute__((visibility("default"))) int vkHuskFramegenConfigure(const tl_fg_config* c){
    if(!c||c->version!=1||c->size!=sizeof(*c)||c->enabled>1||c->reserved)return 0;
    std::lock_guard<std::mutex> guard(fgManagerLock);if(!fgOwners.empty())return 0;
    if(c->enabled && (c->width<64||c->height<64||c->width>4096||c->height>4096||fgStorageBytes(c->width,c->height)>(96ULL<<20)))return 0;
    fgConfig=*c;fgFailed=false;fgPaused=false;return 1;
}
extern "C" __attribute__((visibility("default"))) int vkHuskFramegenSnapshot(tl_fg_stats* s){
    if(!s||s->version!=1||s->size!=sizeof(*s))return 0;
    std::lock_guard<std::mutex> guard(fgManagerLock);
    *s={1,sizeof(*s),uint32_t(!fgOwners.empty()&&!fgPaused.load()&&!fgFailed.load()),uint32_t(fgFailed.load()),fgRendered.load(),fgGenerated.load(),fgReal.load(),fgDropped.load(),fgResets.load(),fgErrors.load()};return 1;
}
extern "C" __attribute__((visibility("default"))) void vkHuskFramegenPause(int paused){
    fgPaused=paused!=0;std::lock_guard<std::mutex> guard(fgManagerLock);
    for(HuskFGPresenter* p:fgOwners){p->_paused=paused!=0;p->_epoch.fetch_add(1);p->_poolWake.notify_all();dispatch_async(p->_work,^{[p resetHistory];});}
}
bool huskFramegenRequested(){std::lock_guard<std::mutex> guard(fgManagerLock);return fgConfig.enabled!=0;}
void* huskFramegenNew(CAMetalLayer* layer){
    tl_fg_config c;
    {std::lock_guard<std::mutex> guard(fgManagerLock);if(!fgConfig.enabled||fgFailed.load())return nullptr;c=fgConfig;}
    HuskFGPresenter* p=[[HuskFGPresenter alloc] initWithLayer:layer config:c];
    if(!p){fgFail();return nullptr;}
    {std::lock_guard<std::mutex> guard(fgManagerLock);p->_paused=fgPaused.load();fgOwners.push_back(p);}
    return p;
}
void huskFramegenDelete(void* raw){
    if(!raw)return;HuskFGPresenter* p=(HuskFGPresenter*)raw;
    {std::lock_guard<std::mutex> guard(fgManagerLock);auto i=std::find(fgOwners.begin(),fgOwners.end(),p);if(i!=fgOwners.end())fgOwners.erase(i);}
    [p stop];[p release];
}
id<CAMetalDrawable> huskFramegenDrawable(void* raw,CAMetalLayer* layer){
    HuskFGPresenter* p=(HuskFGPresenter*)raw;if(!p||fgFailed.load())return layer.nextDrawable;
    std::unique_lock<std::mutex> lock(p->_poolLock);
    for(;;){
        // Resigning active must not poison a still-live Vulkan swapchain.
        // Allow an already-running producer to finish into an offscreen lease;
        // enqueue rejects paused/stale frames without touching a real drawable.
        if(p->_stopped.load())return nil;
        for(unsigned i=0;i<4;i++)if(!p->_used[i]){
            p->_used[i]=true;HuskFGDrawable* f=[HuskFGDrawable new];f->_owner=[p retain];f->_slot=i;f->_epoch=p->_epoch.load();return [f autorelease];
        }
        if(p->_poolWake.wait_for(lock,std::chrono::milliseconds(250))==std::cv_status::timeout)return nil;
    }
}
void huskFramegenSubmitted(id<CAMetalDrawable> drawable,id<MTLCommandBuffer> command){
    if(![drawable isKindOfClass:[HuskFGDrawable class]])return;
    HuskFGDrawable* frame=(HuskFGDrawable*)drawable;
    [command addCompletedHandler:^(id<MTLCommandBuffer> completed){
        if(completed.status==MTLCommandBufferStatusCompleted){++fgRendered;[frame->_owner enqueue:frame];}
        else{++fgErrors;fgFail();[frame finish:0];}
    }];
}
#else
bool huskFramegenRequested(){return false;}
void* huskFramegenNew(CAMetalLayer*){return nullptr;}
void huskFramegenDelete(void*){}
id<CAMetalDrawable> huskFramegenDrawable(void*,CAMetalLayer* layer){return layer.nextDrawable;}
void huskFramegenSubmitted(id<CAMetalDrawable>,id<MTLCommandBuffer>){}
extern "C" __attribute__((visibility("default"))) int vkHuskFramegenConfigure(const tl_fg_config*){return 0;}
extern "C" __attribute__((visibility("default"))) int vkHuskFramegenSnapshot(tl_fg_stats*){return 0;}
extern "C" __attribute__((visibility("default"))) void vkHuskFramegenPause(int){}
#endif
