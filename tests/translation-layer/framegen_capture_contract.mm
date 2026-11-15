// Actual shared capture implementation with real GPU blits; waits are test-only.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <atomic>
#include <mutex>
#include <cassert>
#include <vector>
#include <thread>
#include "HuskFramegenABI.h"
static std::atomic<uint64_t> fgRendered{0};
bool huskFramegenRequested(){return true;}
#include "HuskFGCapture.inc"
static id<MTLTexture> texture(id<MTLDevice> device,unsigned w,unsigned h,MTLPixelFormat format,uint8_t value){
    auto *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:NO];
    desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> t=[device newTextureWithDescriptor:desc];assert(t);
    unsigned pixel=format==MTLPixelFormatBGRA8Unorm?4:(format==MTLPixelFormatRGBA32Float?16:8);std::vector<uint8_t> bytes(w*h*pixel,value);
    [t replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0 withBytes:bytes.data() bytesPerRow:w*pixel];return t;
}
static NSDictionary *record(NSString *root){
    for(unsigned i=0;i<200;i++){
        NSData *d=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"pair-01.json"]];
        if(d)return [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    std::this_thread::sleep_for(std::chrono::milliseconds(10));}assert(false);return nil;
}
@interface TimingDrawable:NSObject {NSMutableArray *_callbacks;double _when;}
- (void)addPresentedHandler:(MTLDrawablePresentedHandler)handler;
- (double)presentedTime;
- (void)fire:(double)when;
@end
@implementation TimingDrawable
- (instancetype)init{if((self=[super init]))_callbacks=[NSMutableArray new];return self;}
- (void)addPresentedHandler:(MTLDrawablePresentedHandler)handler{id block=[handler copy];[_callbacks addObject:block];[block release];}
- (double)presentedTime{return _when;}
- (void)fire:(double)when{_when=when;for(MTLDrawablePresentedHandler h in _callbacks)h((id<MTLDrawable>)self);[_callbacks removeAllObjects];}
- (void)dealloc{[_callbacks release];[super dealloc];}
@end
int main(int argc,char **argv){@autoreleasepool{
    static_assert(sizeof(tl_fg_capture_config)==792,"capture ABI");assert(argc==2);
    NSString *root=[NSString stringWithUTF8String:argv[1]];
    tl_fg_capture_config c={1,sizeof(c),0,1,1,1,{0}};assert(vkHuskFramegenCaptureConfigure(&c));
    c.enabled=1;snprintf(c.directory,sizeof c.directory,"%s",argv[1]);
    c.pair_limit=3;assert(!vkHuskFramegenCaptureConfigure(&c));c.pair_limit=1;
    c.size--;assert(!vkHuskFramegenCaptureConfigure(&c));c.size++;
    id<MTLDevice> d=MTLCreateSystemDefaultDevice();if(!d){fprintf(stderr,"GPU_UNAVAILABLE\n");return 77;}
    assert(vkHuskFramegenCaptureConfigure(&c));
    id<MTLCommandQueue> queue=[d newCommandQueue];
    @autoreleasepool {
    auto *t=fgCaptureReserve(d,8,8,2,2,1,2,7,1.0,2.0);assert(t);
    assert(!fgCaptureReserve(d,8,8,2,2,2,3,7,2.0,3.0)); // one outstanding ticket only
    id<MTLTexture> textures[11];for(unsigned i=0;i<11;i++)textures[i]=texture(d,i>=8?1:(i>=4?2:8),i>=8?1:(i>=4?2:8),i==10?MTLPixelFormatRGBA32Float:(i>=4?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm),(uint8_t)(11+i));
    id<MTLCommandBuffer> generated=[queue commandBuffer];
    for(unsigned i=0;i<3;i++)assert(fgCaptureCopy(generated,textures[i],t->_images[i],t->_row));
    for(unsigned i=0;i<6;i++)assert(fgCaptureCopy(generated,textures[i+4],t->_fields[i],i>=4?t->_coarseRow:t->_flowRow));
    assert(fgCaptureCopy(generated,textures[10],t->_quality,256));
    [generated addCompletedHandler:^(id<MTLCommandBuffer> done){fgCaptureStage(t,true,done);}];[generated commit];
    id<MTLCommandBuffer> real=[queue commandBuffer];assert(fgCaptureCopy(real,textures[3],t->_images[3],t->_row));
    [real addCompletedHandler:^(id<MTLCommandBuffer> done){fgCaptureStage(t,false,done);}];[real commit];[real waitUntilCompleted];
    NSDictionary *r=record(root);assert([r[@"state"] isEqual:@"complete"]&&[r[@"files"] count]==11);
    for(unsigned i=0;i<11;i++){
        NSDictionary *meta=r[@"files"][i];NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:meta[@"file"]]];
        unsigned row=[meta[@"row_bytes"] unsignedIntValue],w=i>=8?1:(i>=4?2:8),h=i>=8?1:(i>=4?2:8),used=w*(i==10?16:(i>=4?8:4));
        assert(data.length==row*h);auto *bytes=(const uint8_t*)data.bytes;
        for(unsigned y=0;y<h;y++)for(unsigned x=0;x<row;x++)assert(bytes[y*row+x]==(x<used?11+i:0));
    }
    // Idempotent late completion never rewrites a completed pair.
    fgCaptureStage(t,false,real);assert(!fgCaptureEnabled.load());
    [t release];for(auto value:textures)[value release];
    }
    dispatch_sync(fgCaptureWriter(),^{});
    assert(!vkHuskFramegenCaptureConfigure(&c)); // never overwrite a nonempty capture
    c.enabled=0;assert(vkHuskFramegenCaptureConfigure(&c));
    NSString *cancel=[root stringByAppendingPathComponent:@"cancel"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cancel withIntermediateDirectories:NO attributes:nil error:nil];
    c.enabled=1;snprintf(c.directory,sizeof c.directory,"%s",cancel.fileSystemRepresentation);assert(vkHuskFramegenCaptureConfigure(&c));
    auto *pending=fgCaptureReserve(d,8,8,2,2,3,4,8,3,4);assert(pending);
    c.enabled=0;assert(vkHuskFramegenCaptureConfigure(&c));fgCaptureFinish(pending,nil);
    NSDictionary *incomplete=record(cancel);assert([incomplete[@"state"] isEqual:@"incomplete"]&&[incomplete[@"files"] count]==0);
    [pending release];dispatch_sync(fgCaptureWriter(),^{});
    for(unsigned i=0;i<200;i++){bool busy;{std::lock_guard<std::mutex> lock(fgCaptureLock);busy=fgCaptureBusy!=0;}if(!busy)break;std::this_thread::sleep_for(std::chrono::milliseconds(10));}
    NSString *large=[root stringByAppendingPathComponent:@"large"];[[NSFileManager defaultManager] createDirectoryAtPath:large withIntermediateDirectories:NO attributes:nil error:nil];
    c.enabled=1;snprintf(c.directory,sizeof c.directory,"%s",large.fileSystemRepresentation);assert(vkHuskFramegenCaptureConfigure(&c));
    assert(!fgCaptureReserve(d,4096,4096,128,128,4,5,9,4,5));assert([record(large)[@"state"] isEqual:@"incomplete"]);
    c.enabled=0;assert(vkHuskFramegenCaptureConfigure(&c));
    NSString *ring=[root stringByAppendingPathComponent:@"ring"];[[NSFileManager defaultManager] createDirectoryAtPath:ring withIntermediateDirectories:NO attributes:nil error:nil];
    c.enabled=1;snprintf(c.directory,sizeof c.directory,"%s",ring.fileSystemRepresentation);assert(vkHuskFramegenCaptureConfigure(&c));
    auto *pinned=[TimingDrawable new],*unavailable=[TimingDrawable new],*late=[TimingDrawable new];
    for(unsigned i=0;i<142;i++){@autoreleasepool{
        id<MTLCommandBuffer> command=[queue commandBuffer];bool diagnostic=i<2;
        TimingDrawable *shown=i==0?pinned:(i==1?unavailable:(i==2?late:[TimingDrawable new]));
        fgCaptureObserve(command,(id<CAMetalDrawable>)shown,(i%2)==0,diagnostic,1000+i,17);
        [command commit];[command waitUntilCompleted];if(i>2){[shown fire:100+i];[shown release];}
    }}
    [pinned fire:42];[unavailable fire:0];[late fire:44];
    fgCaptureFlushTimings(fgCaptureSession);
    {std::lock_guard<std::mutex> lock(fgCaptureSession->_timingLock);
     assert(fgCaptureSession->_timingCount==140&&fgCaptureSession->_timingLost==12&&fgCaptureSession->_lateCallbacks>=1);
     assert(fgCaptureSession->_pinned[0].sequence==1000&&fgCaptureSession->_pinned[0].presentValid);
     assert(fgCaptureSession->_pinned[1].sequence==1001&&!fgCaptureSession->_pinned[1].presentValid);}
    [pinned release];[unavailable release];[late release];
    c.enabled=0;assert(vkHuskFramegenCaptureConfigure(&c));[queue release];[d release];
    fprintf(stderr,"PASS: consecutive timing ring stays bounded, pins capture outputs, ignores stale callbacks and preserves unavailable timestamps (presentation doubles, not panel proof)\n");
    fprintf(stderr,"PASS: actual GPU capture preserves eleven image/field/quality stages and zero padding; bounded staging, cancellation, late completion and empty-directory guards\n");return 0;
}}
