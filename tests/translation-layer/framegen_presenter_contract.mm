// Real GPU reconstruction/copies with controlled display callbacks and shared-
// event stalls. Presentation is a protocol facade, never physical panel proof.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <atomic>
#include <mutex>
#include <cassert>
#include <thread>
#include <vector>
#include "HuskFramegen.inc"

@interface OutputDrawable:NSObject {
@public id<MTLTexture> _texture; NSMutableArray *_callbacks; double _time;
}
- (void)fire:(double)time;
@end
@implementation OutputDrawable
- (instancetype)init {if((self=[super init]))_callbacks=[NSMutableArray new];return self;}
- (id<MTLTexture>)texture{return _texture;}
- (double)presentedTime{return _time;}
- (void)addPresentedHandler:(MTLDrawablePresentedHandler)handler{id b=[handler copy];[_callbacks addObject:b];[b release];}
- (void)fire:(double)time{_time=time;for(MTLDrawablePresentedHandler b in _callbacks)b((id)self);[_callbacks removeAllObjects];}
- (void)dealloc{[_texture release];[_callbacks release];[super dealloc];}
@end
@interface OutputLayer:NSObject {
@public id<MTLDevice> _device; NSMutableArray *_drawables;
}
@end
@implementation OutputLayer
- (instancetype)init{if((self=[super init]))_drawables=[NSMutableArray new];return self;}
- (id<MTLDevice>)device{return _device;}
- (MTLPixelFormat)pixelFormat{return MTLPixelFormatBGRA8Unorm;}
- (CGSize)drawableSize{return CGSizeMake(64,64);}
- (id<CAMetalDrawable>)nextDrawable{
    OutputDrawable*d=[OutputDrawable new];auto*desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:64 height:64 mipmapped:NO];
    desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead;
    d->_texture=[_device newTextureWithDescriptor:desc];assert(d->_texture);[_drawables addObject:d];return (id)[d autorelease];
}
- (void)dealloc{[_device release];[_drawables release];[super dealloc];}
@end
@class QueueFacade;
@interface EncoderFacade:NSObject {@public id<MTLComputeCommandEncoder> _real;QueueFacade *_owner;}
@end
@interface CommandFacade:NSObject {@public id<MTLCommandBuffer> _real;QueueFacade *_owner;double _target;}
@end
@interface QueueFacade:NSObject {
@public id<MTLCommandQueue> _real;id<MTLComputePipelineState> _copy;
    NSMutableArray *_commands;id<MTLSharedEvent> _gate;NSUInteger _holdIndex,_issued;
    std::atomic<unsigned> _heavy,_copies;
}
@end
@implementation EncoderFacade
- (id)forwardingTargetForSelector:(SEL)selector{(void)selector;return _real;}
- (void)setComputePipelineState:(id<MTLComputePipelineState>)state{
    if(state==_owner->_copy)++_owner->_copies;else ++_owner->_heavy;[_real setComputePipelineState:state];
}
- (void)dealloc{[_real release];[_owner release];[super dealloc];}
@end
@implementation CommandFacade
- (id)forwardingTargetForSelector:(SEL)selector{(void)selector;return _real;}
- (id<MTLComputeCommandEncoder>)computeCommandEncoder{
    auto *e=[EncoderFacade new];e->_real=[[_real computeCommandEncoder] retain];e->_owner=[_owner retain];return (id)[e autorelease];
}
- (void)presentDrawable:(id<MTLDrawable>)drawable atTime:(double)time{
    _target=time;[_real addCompletedHandler:^(id<MTLCommandBuffer>done){assert(done.status==MTLCommandBufferStatusCompleted);[(OutputDrawable*)drawable fire:time?time:CACurrentMediaTime()];}];
}
- (void)presentDrawable:(id<MTLDrawable>)drawable{[self presentDrawable:drawable atTime:0];}
- (void)dealloc{[_real release];[super dealloc];}
@end
@implementation QueueFacade
- (instancetype)init{if((self=[super init])){_commands=[NSMutableArray new];_holdIndex=NSUIntegerMax;_heavy=0;_copies=0;}return self;}
- (id<MTLCommandBuffer>)commandBuffer{
    auto *c=[CommandFacade new];c->_real=[[_real commandBuffer]retain];c->_owner=self;
    if(_gate&&_issued==_holdIndex)[c->_real encodeWaitForEvent:_gate value:1];++_issued;
    [_commands addObject:c];return (id)[c autorelease];
}
- (void)dealloc{[_real release];[_commands release];[_gate release];[super dealloc];}
@end
@interface TickClock:NSObject
@property(nonatomic) double targetTimestamp;
@end
@implementation TickClock
@end
static QueueFacade *wrap(id<MTLCommandQueue> queue,id<MTLComputePipelineState>copy){
    QueueFacade *q=[QueueFacade new];q->_real=[queue retain];q->_copy=copy;return q;
}
static HuskFGDrawable *source(HuskFGPresenter*p,unsigned sequence){@autoreleasepool{
    auto *d=[(HuskFGDrawable*)huskFramegenDrawable(p,nil)retain];assert(d);d->_sequence=sequence;
    std::vector<uint8_t> data(64*64*4);for(unsigned i=0;i<64*64;i++){data[4*i]=20+sequence;data[4*i+1]=50;data[4*i+2]=80;data[4*i+3]=255;}
    id<MTLBuffer>b=[p->_device newBufferWithBytes:data.data() length:data.size() options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer>c=[p->_queue commandBuffer];id<MTLBlitCommandEncoder>e=[c blitCommandEncoder];
    [e copyFromBuffer:b sourceOffset:0 sourceBytesPerRow:64*4 sourceBytesPerImage:data.size() sourceSize:MTLSizeMake(64,64,1) toTexture:d.texture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];[e endEncoding];[c commit];[c waitUntilCompleted];[b release];assert(c.status==MTLCommandBufferStatusCompleted);d->_sourceCompletedHost=CACurrentMediaTime();return d;
}}
static void flush(HuskFGPresenter*p){dispatch_sync(p->_work,^{});}
static bool eventually(HuskFGPresenter*p,bool(^condition)(void)){
    for(unsigned i=0;i<2000;i++){@autoreleasepool{__block bool ready=false;dispatch_sync(p->_work,^{ready=condition();});if(ready)return true;}std::this_thread::sleep_for(std::chrono::milliseconds(1));}return false;
}
static void tick(HuskFGPresenter*p,double target){TickClock*c=[TickClock new];c.targetTimestamp=target;[p tick:(id)c];[c release];flush(p);}
static bool completed(id<MTLCommandBuffer>command){return command.status==MTLCommandBufferStatusCompleted;}
int main(int argc,char**argv){@autoreleasepool{
    assert(argc==2);id<MTLDevice>device=MTLCreateSystemDefaultDevice();assert(device);
    OutputLayer*layer=[OutputLayer new];layer->_device=[device retain];
    tl_fg_config config={1,sizeof config,1,64,64,0};assert(vkHuskFramegenConfigure(&config));
    auto*p=[[HuskFGPresenter alloc]initWithLayer:(id)layer config:config];assert(p);
    auto*out=wrap(p->_queue,p->_copyPSO);[p->_queue release];p->_queue=(id)out;
    auto*a=source(p,1);[p enqueue:a];flush(p);tick(p,CACurrentMediaTime()+1); // Invalid distant target must not be used.
    CommandFacade *initial=[out->_commands lastObject];assert(eventually(p,^{return completed(initial->_real);}));assert(initial->_target==0&&layer->_drawables.count==1);
    auto*b=source(p,2);
#ifndef HUSK_PREPARED_PRESENTATION
    [p enqueue:b];flush(p);tick(p,CACurrentMediaTime()+0.02);
    CommandFacade *old=[out->_commands lastObject];assert(eventually(p,^{return completed(old->_real);}));
    if(out->_heavy.load()>0){fprintf(stderr,"QUALITY_REJECT: frozen170 starts expensive reconstruction on the display-output queue at the tick\n");return 9;}
    return 10;
#else
    auto*prep=wrap(p->_prepareQueue,p->_copyPSO);[p->_prepareQueue release];p->_prepareQueue=(id)prep;
    id<MTLSharedEvent>firstGate=[device newSharedEvent];assert(firstGate);prep->_gate=[firstGate retain];prep->_holdIndex=0;
    tl_fg_capture_config capture={1,sizeof capture,1,1,1,1,{0}};snprintf(capture.directory,sizeof capture.directory,"%s",argv[1]);assert(vkHuskFramegenCaptureConfigure(&capture));
    [p enqueue:b];flush(p);
    assert(prep->_issued==1&&p->_preparedCurrent==b&&p->_prepareInFlight.load()==1&&layer->_drawables.count==1);
    tick(p,CACurrentMediaTime()+0.02);assert(layer->_drawables.count==1&&!p->_realNext); // No drawable acquired, GPU waited or unfinished image output.
    firstGate.signaledValue=1;assert(eventually(p,^{return p->_preparedReady;}));b->_sourceCompletedHost=CACurrentMediaTime();assert(prep->_heavy.load()>0&&out->_heavy.load()==0);
    id<MTLSharedEvent>copyGate=[device newSharedEvent];out->_gate=[copyGate retain];out->_holdIndex=out->_issued;
    double target=CACurrentMediaTime()+0.02;tick(p,target);
    CommandFacade*generated=[out->_commands lastObject];assert(generated->_target==target&&p->_realNext&&p->_scratchReaders.load()==1);
    // A third producer completes while B's generated copy still owns scratch.
    // Upload via a different real queue, since the output-copy queue is gated.
    id<MTLCommandQueue>upload=[device newCommandQueue];auto*oldOut=p->_queue;p->_queue=upload;auto*c=source(p,3);p->_queue=oldOut;[upload release];
    [prep->_gate release];id<MTLSharedEvent>secondGate=[device newSharedEvent];prep->_gate=[secondGate retain];prep->_holdIndex=prep->_issued;
    [p enqueue:c];flush(p);assert(prep->_issued==1); // Writer cannot overwrite scratch still being copied.
    copyGate.signaledValue=1;assert(eventually(p,^{return prep->_issued==2;}));assert(p->_prepareInFlight.load()==1&&!p->_preparedReady);
    tick(p,CACurrentMediaTime()+0.02);CommandFacade*real=[out->_commands lastObject];
    assert(real!=generated&&eventually(p,^{return completed(real->_real);})); // A blocked next reconstruction must not block B's real output.
    assert(!p->_preparedReady&&p->_preparedCurrent==c&&out->_heavy.load()==0&&out->_copies.load()==3);
    OutputDrawable*shown=[layer->_drawables lastObject];uint8_t pixels[64*64*4];[shown.texture getBytes:pixels bytesPerRow:64*4 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
    for(unsigned i=0;i<64*64;i++)assert(pixels[4*i]==22&&pixels[4*i+1]==50&&pixels[4*i+2]==80&&pixels[4*i+3]==255);
    // Epoch reset during actual in-flight GPU sampling cannot publish old work
    // or free a guest lease still used by that GPU command.
    p->_epoch.fetch_add(1);dispatch_sync(p->_work,^{[p resetHistory];});[a release];[b release];[c release];assert(p->_used[1]||p->_used[2]);
    secondGate.signaledValue=1;assert(eventually(p,^{return p->_prepareInFlight.load()==0;}));flush(p);
    assert(!p->_preparedCurrent&&!p->_preparedReady&&!p->_current&&!p->_ready.count&&out->_heavy.load()==0);
    [out->_commands removeAllObjects];[prep->_commands removeAllObjects];
    assert(eventually(p,^{for(unsigned i=0;i<4;i++)if(p->_used[i])return false;return true;}));
    HuskFGDrawable*reuse[4];for(unsigned i=0;i<4;i++){@autoreleasepool{reuse[i]=[(HuskFGDrawable*)huskFramegenDrawable(p,nil)retain];assert(reuse[i]);}}
    for(auto*d:reuse)[d release];for(unsigned i=0;i<4;i++)assert(!p->_used[i]);
    NSString*root=[NSString stringWithUTF8String:argv[1]];__block NSDictionary*record=nil;
    assert(eventually(p,^{NSData*d=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"pair-01.json"]];if(d){[record release];record=[[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]retain];}return [record[@"state"]isEqual:@"complete"];}));
    assert([record[@"files"]count]==11&&[record[@"generated_gpu_stage"]hasPrefix:@"reconstruction"]);
    // Pair metadata is published before the writer flushes timing metadata.
    // Serialize this explicit flush with that writer: racing two O_EXCL temp
    // writes can otherwise leave no completed timing file at this instant.
    dispatch_sync(fgCaptureWriter(),^{fgCaptureFlushTimings(fgCaptureSession);});
    NSData*timingData=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"consumer-timing.json"]];assert(timingData);
    NSDictionary*timing=[NSJSONSerialization JSONObjectWithData:timingData options:0 error:nil];
    bool sawPrep=false,sawGenerated=false,sawReal=false;for(NSDictionary*r in timing[@"records"]){if([r[@"kind"]isEqual:@"reconstruction"])sawPrep=true;if([r[@"kind"]isEqual:@"generated"])sawGenerated=true;if([r[@"kind"]isEqual:@"real"])sawReal=true;}
    assert([timing[@"schema"]intValue]==3&&sawPrep&&sawGenerated&&sawReal);
    capture.enabled=0;assert(vkHuskFramegenCaptureConfigure(&capture));[record release];[firstGate release];[copyGate release];[secondGate release];
    [p release];[layer release];[device release];
    puts("PASS: actual GPU reconstruction starts before ticks; output queue contains copies only; scratch is not overwritten during copy; blocked next reconstruction cannot block real output; stale GPU completion cannot revive reset leases; target clock and eleven-stage capture retained (display callbacks controlled, not panel proof)");return 0;
#endif
}}
