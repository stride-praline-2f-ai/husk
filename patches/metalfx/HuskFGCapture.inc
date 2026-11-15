/* SPDX-License-Identifier: Apache-2.0
 * Explicit, bounded visual evidence. OFF costs one relaxed atomic check; no
 * readback, file work or timer exists until the host arms an empty directory.
 */
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <errno.h>
bool huskFramegenRequested();
static std::atomic<bool> fgCaptureEnabled{false};
static std::mutex fgCaptureLock;
static unsigned fgCaptureBusy;
struct FGCaptureTiming {
    uint64_t sequence,epoch;
    bool generated,diagnostic,gpuValid,presentValid;
    double submitHost,gpuStart,gpuEnd,completionHost,presented,presentObserved;
};
@interface HuskFGCaptureSession:NSObject {
@public
    int _fd;
    unsigned _limit,_next,_busy,_first,_stride;
    uint64_t _base;
    std::atomic<bool> _cancelled;
    std::mutex _timingLock;
    FGCaptureTiming _timings[64];
    unsigned _timingCount,_timingLost,_commands;
}
@end
@implementation HuskFGCaptureSession
- (instancetype)init{if((self=[super init])){_fd=-1;_cancelled=false;}return self;}
- (void)dealloc{if(_fd>=0)close(_fd);[super dealloc];}
@end
@interface HuskFGCaptureTicket:NSObject {
@public
    HuskFGCaptureSession *_session;
    id<MTLBuffer> _images[4],_fields[2];
    unsigned _id,_width,_height,_row,_flowWidth,_flowHeight,_flowRow;
    uint64_t _previousSequence,_currentSequence,_epoch;
    double _created,_sourcePrevious,_sourceCurrent;
    std::mutex _stageLock;
    bool _done[2];
    double _gpuStart[2],_gpuEnd[2];
    std::atomic<bool> _finalized;
}
@end
@implementation HuskFGCaptureTicket
- (instancetype)init{if((self=[super init]))_finalized=false;return self;}
- (void)dealloc{for(auto b:_images)[b release];for(auto b:_fields)[b release];
    {std::lock_guard<std::mutex> lock(fgCaptureLock);if(_session&&_session->_busy)--_session->_busy;if(fgCaptureBusy)--fgCaptureBusy;}
    [_session release];[super dealloc];}
@end
static HuskFGCaptureSession *fgCaptureSession;
static dispatch_queue_t fgCaptureWriter(){
    static dispatch_queue_t q;static dispatch_once_t once;
    dispatch_once(&once,^{q=dispatch_queue_create("com.husk.framegen.evidence",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));});return q;
}
static bool fgCaptureWrite(HuskFGCaptureSession *s,const char *name,const void *bytes,size_t length){
    if(!name||strchr(name,'/')||strlen(name)>90)return false;
    char temp[100];snprintf(temp,sizeof temp,"%s.tmp",name);
    int fd=openat(s->_fd,temp,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);if(fd<0)return false;
    const uint8_t *p=(const uint8_t*)bytes;size_t left=length;bool ok=true;
    while(left){ssize_t n=write(fd,p,left);if(n<0&&errno==EINTR)continue;if(n<=0){ok=false;break;}p+=n;left-=(size_t)n;}
    if(close(fd))ok=false;
    if(ok)ok=renameat(s->_fd,temp,s->_fd,name)==0;
    if(!ok)unlinkat(s->_fd,temp,0);return ok;
}
static bool fgCaptureJSON(HuskFGCaptureSession *s,const char *name,id object){
    NSError *error=nil;NSData *data=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    return data&&fgCaptureWrite(s,name,data.bytes,data.length);
}
static id fgCaptureTime(double value){return std::isfinite(value)&&value>0?(id)@(value):(id)[NSNull null];}
static void fgCaptureFlushTimings(HuskFGCaptureSession *s){
    FGCaptureTiming rows[64];unsigned count,lost;
    {std::lock_guard<std::mutex> lock(s->_timingLock);count=s->_timingCount;lost=s->_timingLost;memcpy(rows,s->_timings,count*sizeof(*rows));}
    NSMutableArray *items=[NSMutableArray array];
    for(unsigned i=0;i<count;i++){
        auto &r=rows[i];[items addObject:@{@"source_sequence":@(r.sequence),@"epoch":@(r.epoch),@"kind":r.generated?@"generated":@"real",
            @"includes_diagnostic_readback":@(r.diagnostic),@"submit_host_monotonic_seconds":@(r.submitHost),
            @"completion_host_monotonic_seconds":fgCaptureTime(r.completionHost),@"gpu_timestamp_valid":@(r.gpuValid),
            @"gpu_start_seconds":r.gpuValid?@(r.gpuStart):(id)[NSNull null],@"gpu_end_seconds":r.gpuValid?@(r.gpuEnd):(id)[NSNull null],
            @"gpu_duration_ms":r.gpuValid?@((r.gpuEnd-r.gpuStart)*1000):(id)[NSNull null],@"presented_timestamp_valid":@(r.presentValid),
            @"presented_time_seconds":r.presentValid?@(r.presented):(id)[NSNull null],@"presentation_callback_host_seconds":fgCaptureTime(r.presentObserved)}];
    }
    fgCaptureJSON(s,"consumer-timing.json",@{@"schema":@1,@"plan_ids":@[@"M3",@"M4",@"M9"],@"subsystem":@"framegen_consumer",
        @"records":items,@"capacity":@64,@"omitted_records":@(lost),@"sampling":@"one in seven output commands plus captured pairs; bounded opt-in window",
        @"host_clock":@"CACurrentMediaTime seconds",@"gpu_clock":@"MTLCommandBuffer GPUStartTime/GPUEndTime seconds; no inferred cross-clock latency",
        @"presentation_clock":@"CAMetalDrawable presentedTime; absent callbacks stay unavailable",
        @"limitations":@"Not unique pixels, input latency, panel scanout or power. Exclude diagnostic-copy commands from normal GPU comparisons."});
}
extern "C" __attribute__((visibility("default"))) int vkHuskFramegenCaptureConfigure(const tl_fg_capture_config *c){
    if(!c||c->version!=1||c->size!=sizeof(*c)||c->enabled>1)return 0;
    if(!c->enabled){std::lock_guard<std::mutex> lock(fgCaptureLock);fgCaptureEnabled=false;if(fgCaptureSession)fgCaptureSession->_cancelled=true;[fgCaptureSession release];fgCaptureSession=nil;return 1;}
    if(!huskFramegenRequested()||c->pair_limit<1||c->pair_limit>2||c->first_frame<1||c->first_frame>900||c->frame_stride<1||c->frame_stride>900||
       c->directory[0]!='/'||strnlen(c->directory,sizeof c->directory)==sizeof c->directory)return 0;
    int fd=open(c->directory,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);if(fd<0)return 0;
    int duplicate=dup(fd);DIR *dir=duplicate>=0?fdopendir(duplicate):nullptr;if(!dir&&duplicate>=0)close(duplicate);bool empty=dir!=nullptr;
    if(dir){while(auto *entry=readdir(dir))if(strcmp(entry->d_name,".")&&strcmp(entry->d_name,"..")){empty=false;break;}closedir(dir);}
    if(!empty){close(fd);return 0;}
    std::lock_guard<std::mutex> lock(fgCaptureLock);
    if(fgCaptureBusy){close(fd);return 0;}
    auto *s=[HuskFGCaptureSession new];s->_fd=fd;s->_limit=c->pair_limit;s->_first=c->first_frame;s->_stride=c->frame_stride;s->_base=fgRendered.load();
    if(fgCaptureSession)fgCaptureSession->_cancelled=true;[fgCaptureSession release];fgCaptureSession=s;fgCaptureEnabled=true;
    fprintf(stderr,"[M3/M9-FG-CAPTURE] armed %u pair(s), first after %u completed source frames, stride %u; diagnostic copies are excluded from performance acceptance\n",c->pair_limit,c->first_frame,c->frame_stride);return 1;
}
static void fgCaptureFinish(HuskFGCaptureTicket *t,NSString *failure){
    bool expected=false;if(!t||!t->_finalized.compare_exchange_strong(expected,true))return;
    if(t->_session->_cancelled.load()&&!failure)failure=@"capture configuration superseded";
    {std::lock_guard<std::mutex> lock(fgCaptureLock);if(t->_session==fgCaptureSession&&t->_session->_next>=t->_session->_limit)fgCaptureEnabled=false;}
    dispatch_async(fgCaptureWriter(),^{@autoreleasepool{
        NSString *error=failure;NSMutableArray *files=[NSMutableArray array];
        const char *stages[]={"previous","current","generated","following-real","forward","backward"};
        if(!error)for(unsigned i=0;i<6;i++){
            bool field=i>=4;id<MTLBuffer> b=field?t->_fields[i-4]:t->_images[i];
            char file[96];snprintf(file,sizeof file,"pair-%02u-%s.%s",t->_id,stages[i],field?"f16":"bgra");
            if(!fgCaptureWrite(t->_session,file,b.contents,b.length)){error=[NSString stringWithFormat:@"file write failed at %s (errno %d)",stages[i],errno];break;}
            [files addObject:@{@"stage":[NSString stringWithUTF8String:stages[i]],@"file":[NSString stringWithUTF8String:file],
                @"width":@(field?t->_flowWidth:t->_width),@"height":@(field?t->_flowHeight:t->_height),@"row_bytes":@(field?t->_flowRow:t->_row),
                @"bytes":@(b.length),@"format":field?@"RGBA16Float":@"BGRA8Unorm",@"origin":@"top-left"}];
        }
        double gpuStart[2],gpuEnd[2];{std::lock_guard<std::mutex> lock(t->_stageLock);memcpy(gpuStart,t->_gpuStart,sizeof gpuStart);memcpy(gpuEnd,t->_gpuEnd,sizeof gpuEnd);}
        NSDictionary *record=@{@"schema":@1,@"plan_ids":@[@"M1",@"M3",@"M9"],@"pair_id":@(t->_id),@"state":error?@"incomplete":@"complete",
            @"error":error?: (id)[NSNull null],@"previous_source_sequence":@(t->_previousSequence),@"current_source_sequence":@(t->_currentSequence),@"epoch":@(t->_epoch),
            @"capture_encode_host_monotonic_seconds":@(t->_created),@"previous_source_gpu_completion_callback_host_seconds":fgCaptureTime(t->_sourcePrevious),
            @"current_source_gpu_completion_callback_host_seconds":fgCaptureTime(t->_sourceCurrent),@"source_gpu_execution_timestamps":@"UNAVAILABLE for source Metal4 feedback; callback time is not GPU duration",
            @"generated_gpu_start_seconds":fgCaptureTime(gpuStart[0]),@"generated_gpu_end_seconds":fgCaptureTime(gpuEnd[0]),
            @"real_gpu_start_seconds":fgCaptureTime(gpuStart[1]),@"real_gpu_end_seconds":fgCaptureTime(gpuEnd[1]),@"files":files,
            @"input_stage":@"final guest swapchain colour, after engine postprocessing and BEFORE framegen",
            @"forward_field":@"current to previous, xy in swapchain pixels, z photometric residual; RGBA16Float little-endian",
            @"backward_field":@"previous to current, same units; interpolated flow is not engine motion vectors",
            @"diagnostic_overhead":@"intrusive opt-in GPU copies/readback plus Utility disk work; not an energy or baseline pacing benchmark",
            @"engine_runtime_cvars":@"UNAVAILABLE; engine-requests.txt contains requests only"};
        char manifest[64];snprintf(manifest,sizeof manifest,"pair-%02u.json",t->_id);
        bool saved=fgCaptureJSON(t->_session,manifest,record);
        fgCaptureFlushTimings(t->_session);
        fprintf(stderr,"[M3/M9-FG-CAPTURE] pair %u %s, metadata %s, source sequences %llu/%llu; raw inputs/generated/following-real are separate\n",t->_id,error?"incomplete":"complete",saved?"saved":"FAILED",(unsigned long long)t->_previousSequence,(unsigned long long)t->_currentSequence);
        // One bounded final flush allows pending presentation callbacks to be
        // included. Hold only the small session/ring, never image buffers.
        HuskFGCaptureSession *session=t->_session;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),fgCaptureWriter(),^{@autoreleasepool{fgCaptureFlushTimings(session);}});
    }});
}
static HuskFGCaptureTicket *fgCaptureReserve(id<MTLDevice> device,unsigned w,unsigned h,unsigned fw,unsigned fh,
    uint64_t previous,uint64_t current,uint64_t epoch,double previousTime,double currentTime){
    if(!fgCaptureEnabled.load(std::memory_order_relaxed))return nil;
    HuskFGCaptureSession *s;unsigned pair;
    {std::lock_guard<std::mutex> lock(fgCaptureLock);s=fgCaptureSession;
     if(!s||s->_cancelled.load()||fgCaptureBusy||s->_busy||s->_next>=s->_limit||current<s->_base+s->_first+uint64_t(s->_next)*s->_stride)return nil;
     [s retain];pair=++s->_next;++s->_busy;++fgCaptureBusy;}
    auto *t=[HuskFGCaptureTicket new];t->_session=s;t->_id=pair;t->_width=w;t->_height=h;t->_row=(w*4+255)&~255u;
    t->_flowWidth=fw;t->_flowHeight=fh;t->_flowRow=(fw*8+255)&~255u;t->_previousSequence=previous;t->_currentSequence=current;t->_epoch=epoch;
    t->_created=CACurrentMediaTime();t->_sourcePrevious=previousTime;t->_sourceCurrent=currentTime;
    uint64_t size=uint64_t(t->_row)*h,flowSize=uint64_t(t->_flowRow)*fh,total=4*size+2*flowSize;
    bool admitted=w>=1&&h>=1&&w<=4096&&h<=4096&&fw>=1&&fh>=1&&fw<=256&&fh<=256&&total<=(64ULL<<20);
#if TARGET_OS_IOS
    admitted=admitted&&os_proc_available_memory()>total+(128ULL<<20);
#endif
    if(admitted){for(auto &b:t->_images){b=[device newBufferWithLength:size options:MTLResourceStorageModeShared];if(b)memset(b.contents,0,b.length);}
        for(auto &b:t->_fields){b=[device newBufferWithLength:flowSize options:MTLResourceStorageModeShared];if(b)memset(b.contents,0,b.length);}}
    bool allocated=admitted;for(auto b:t->_images)allocated=allocated&&b!=nil;for(auto b:t->_fields)allocated=allocated&&b!=nil;
    if(!allocated){fgCaptureFinish(t,@"diagnostic staging memory unavailable or exceeds64MiB budget");[t release];return nil;}
    fprintf(stderr,"[M3/M9-FG-CAPTURE] pair %u begins at source %llu; exclude diagnostic-copy frames from performance comparisons\n",pair,(unsigned long long)current);return t;
}
static bool fgCaptureCopy(id<MTLCommandBuffer> command,id<MTLTexture> texture,id<MTLBuffer> target,unsigned row){
    id<MTLBlitCommandEncoder> e=[command blitCommandEncoder];if(!e)return false;
    [e copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
        sourceSize:MTLSizeMake(texture.width,texture.height,1) toBuffer:target destinationOffset:0 destinationBytesPerRow:row destinationBytesPerImage:target.length];
    [e endEncoding];return true;
}
static void fgCaptureStage(HuskFGCaptureTicket *t,bool generated,id<MTLCommandBuffer> command){
    if(command.status==MTLCommandBufferStatusError){fgCaptureFinish(t,@"GPU error during diagnostic copy");return;}
    bool ready;unsigned i=generated?0:1;
    {std::lock_guard<std::mutex> lock(t->_stageLock);t->_done[i]=true;t->_gpuStart[i]=command.GPUStartTime;t->_gpuEnd[i]=command.GPUEndTime;ready=t->_done[0]&&t->_done[1];}
    if(ready)fgCaptureFinish(t,nil);
}
static void fgCaptureObserve(id<MTLCommandBuffer> command,id<CAMetalDrawable> drawable,bool generated,bool diagnostic,uint64_t sequence,uint64_t epoch){
    if(!fgCaptureEnabled.load(std::memory_order_relaxed))return;
    HuskFGCaptureSession *s;unsigned index;
    {std::lock_guard<std::mutex> lock(fgCaptureLock);s=fgCaptureSession;if(!s||s->_cancelled.load())return;
     if(!diagnostic&&s->_commands++%7)return;[s retain];}
    bool full;
    {std::lock_guard<std::mutex> lock(s->_timingLock);full=s->_timingCount>=64;if(full)++s->_timingLost;
     else{index=s->_timingCount++;auto &r=s->_timings[index];r.sequence=sequence;r.epoch=epoch;r.generated=generated;r.diagnostic=diagnostic;r.submitHost=CACurrentMediaTime();}}
    if(full){[s release];return;}
    [command addCompletedHandler:^(id<MTLCommandBuffer> done){std::lock_guard<std::mutex> lock(s->_timingLock);auto &r=s->_timings[index];
        r.completionHost=CACurrentMediaTime();r.gpuStart=done.GPUStartTime;r.gpuEnd=done.GPUEndTime;
        r.gpuValid=done.status==MTLCommandBufferStatusCompleted&&std::isfinite(r.gpuStart)&&std::isfinite(r.gpuEnd)&&r.gpuStart>0&&r.gpuEnd>=r.gpuStart;}];
    [drawable addPresentedHandler:^(id<MTLDrawable> shown){std::lock_guard<std::mutex> lock(s->_timingLock);auto &r=s->_timings[index];r.presented=shown.presentedTime;
        r.presentObserved=CACurrentMediaTime();r.presentValid=std::isfinite(r.presented)&&r.presented>0;}];[s release];
}
