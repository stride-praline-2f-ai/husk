/* SPDX-License-Identifier: Apache-2.0
 * Explicit, bounded visual evidence. OFF costs one relaxed atomic check; no
 * readback, file work or timer exists until the host arms an empty directory.
 */
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <cmath>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <errno.h>
bool huskFramegenRequested();
// FG_IMAGE_METRICS_BEGIN
// Utility writer only, AFTER the one-shot GPU readbacks have completed. No
// additional GPU pass, staging buffer, per-frame log or gameplay scan.
struct FGImageMetrics {
    uint64_t pixels=0,changed=0,absoluteDifference=0,referenceEdges=0,outputEdges=0;
    unsigned maximumDifference=0;
};
static FGImageMetrics fgImageMetrics(const uint8_t *reference,const uint8_t *output,unsigned width,unsigned height,unsigned row){
    FGImageMetrics m;
    for(unsigned y=0;y<height;y++)for(unsigned x=0;x<width;x++){
        unsigned largest=0;size_t p=size_t(y)*row+x*4;
        for(unsigned c=0;c<3;c++){
            unsigned difference=unsigned(std::abs(int(reference[p+c])-int(output[p+c])));
            m.absoluteDifference+=difference;largest=std::max(largest,difference);
            if(x){m.referenceEdges+=unsigned(std::abs(int(reference[p+c])-int(reference[p-4+c])));
                  m.outputEdges+=unsigned(std::abs(int(output[p+c])-int(output[p-4+c])));}
            if(y){m.referenceEdges+=unsigned(std::abs(int(reference[p+c])-int(reference[p-row+c])));
                  m.outputEdges+=unsigned(std::abs(int(output[p+c])-int(output[p-row+c])));}
        }
        ++m.pixels;if(largest>1)++m.changed;
        m.maximumDifference=std::max(m.maximumDifference,largest);
    }
    return m;
}
// FG_IMAGE_METRICS_END
static NSDictionary *fgImageMetricsJSON(const FGImageMetrics &m){
    return @{@"pixels":@(m.pixels),@"changed_rgb_gt1_pixels":@(m.changed),@"maximum_rgb_difference_codes":@(m.maximumDifference),
        @"mean_absolute_rgb_difference_codes":m.pixels?@((double)m.absoluteDifference/(3*m.pixels)):(id)[NSNull null],
        @"reference_rgb_edge_l1_sum":@(m.referenceEdges),@"output_rgb_edge_l1_sum":@(m.outputEdges),
        @"exact_rgb_copy":@(m.maximumDifference==0)};
}
static std::atomic<bool> fgCaptureEnabled{false},fgCaptureTimingEnabled{false};
static std::mutex fgCaptureLock;
static unsigned fgCaptureBusy;
struct FGCaptureTiming {
    uint64_t sequence,epoch,recordID;
    bool generated,diagnostic,gpuValid,presentValid,preparation;
    double submitHost,gpuStart,gpuEnd,completionHost,presented,presentObserved,targetHost,sourceCompletedHost;
};
@interface HuskFGCaptureSession:NSObject {
@public
    int _fd;
    unsigned _limit,_next,_busy,_first,_stride;
    uint64_t _base;
    std::atomic<bool> _cancelled;
    std::mutex _timingLock;
    FGCaptureTiming _timings[128],_pinned[2];
    unsigned _timingCount,_timingLost,_commands,_lateCallbacks;
}
@end
@implementation HuskFGCaptureSession
- (instancetype)init{if((self=[super init])){_fd=-1;_cancelled=false;}return self;}
- (void)dealloc{if(_fd>=0)close(_fd);[super dealloc];}
@end
@interface HuskFGCaptureTicket:NSObject {
@public
    HuskFGCaptureSession *_session;
    id<MTLBuffer> _images[4],_fields[6],_quality;
    unsigned _id,_width,_height,_row,_flowWidth,_flowHeight,_flowRow,_coarseWidth,_coarseHeight,_coarseRow;
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
- (void)dealloc{for(auto b:_images)[b release];for(auto b:_fields)[b release];[_quality release];
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
    FGCaptureTiming rows[130];unsigned count,lost,late;
    {std::lock_guard<std::mutex> lock(s->_timingLock);count=std::min(s->_timingCount,128u);lost=s->_timingLost;late=s->_lateCallbacks;
     unsigned first=s->_timingCount>128?s->_timingCount%128:0;for(unsigned i=0;i<count;i++)rows[i]=s->_timings[(first+i)%128];
     for(unsigned i=0;i<2;i++)if(s->_pinned[i].recordID)rows[count++]=s->_pinned[i];}
    std::sort(rows,rows+count,[](const FGCaptureTiming&a,const FGCaptureTiming&b){return a.recordID<b.recordID;});
    NSMutableArray *items=[NSMutableArray array];
    for(unsigned i=0;i<count;i++){
        auto &r=rows[i];[items addObject:@{@"record_id":@(r.recordID),@"source_sequence":@(r.sequence),@"epoch":@(r.epoch),@"kind":r.preparation?@"reconstruction":(r.generated?@"generated":@"real"),
            @"target_presentation_host_seconds":fgCaptureTime(r.targetHost),@"source_completed_host_seconds":fgCaptureTime(r.sourceCompletedHost),
            @"includes_diagnostic_readback":@(r.diagnostic),@"submit_host_monotonic_seconds":@(r.submitHost),
            @"completion_host_monotonic_seconds":fgCaptureTime(r.completionHost),@"gpu_timestamp_valid":@(r.gpuValid),
            @"gpu_start_seconds":r.gpuValid?@(r.gpuStart):(id)[NSNull null],@"gpu_end_seconds":r.gpuValid?@(r.gpuEnd):(id)[NSNull null],
            @"gpu_duration_ms":r.gpuValid?@((r.gpuEnd-r.gpuStart)*1000):(id)[NSNull null],@"presented_timestamp_valid":@(r.presentValid),
            @"presented_time_seconds":r.presentValid?@(r.presented):(id)[NSNull null],
            @"presented_minus_target_ms":(r.presentValid&&r.targetHost>0)?@((r.presented-r.targetHost)*1000):(id)[NSNull null],@"presentation_callback_host_seconds":fgCaptureTime(r.presentObserved)}];
    }
    fgCaptureJSON(s,"consumer-timing.json",@{@"schema":@3,@"plan_ids":@[@"M3",@"M4",@"M9"],@"subsystem":@"framegen_consumer",
        @"records":items,@"capacity":@130,@"omitted_records":@(lost),@"late_callbacks_after_slot_reuse":@(late),@"sampling":@"every output in a rolling128-command ring plus2 pinned capture outputs; ends500ms after file completion",
        @"host_clock":@"CACurrentMediaTime seconds",@"gpu_clock":@"MTLCommandBuffer GPUStartTime/GPUEndTime seconds; no inferred cross-clock latency",
        @"presentation_clock":@"CAMetalDrawable presentedTime; absent callbacks stay unavailable",
        @"limitations":@"Reconstruction commands are separate from generated/real display copies; compare the full work, not copy-only cost. Targets and source completion are CA host times, not engine sampling times. Not unique pixels, input latency, panel scanout or power. Exclude diagnostic readback commands from normal GPU comparisons."});
}
extern "C" __attribute__((visibility("default"))) int vkHuskFramegenCaptureConfigure(const tl_fg_capture_config *c){
    if(!c||c->version!=1||c->size!=sizeof(*c)||c->enabled>1)return 0;
    if(!c->enabled){std::lock_guard<std::mutex> lock(fgCaptureLock);fgCaptureEnabled=false;fgCaptureTimingEnabled=false;if(fgCaptureSession)fgCaptureSession->_cancelled=true;[fgCaptureSession release];fgCaptureSession=nil;return 1;}
    if(!huskFramegenRequested()||c->pair_limit<1||c->pair_limit>2||c->first_frame<1||c->first_frame>900||c->frame_stride<1||c->frame_stride>900||
       c->directory[0]!='/'||strnlen(c->directory,sizeof c->directory)==sizeof c->directory)return 0;
    int fd=open(c->directory,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);if(fd<0)return 0;
    int duplicate=dup(fd);DIR *dir=duplicate>=0?fdopendir(duplicate):nullptr;if(!dir&&duplicate>=0)close(duplicate);bool empty=dir!=nullptr;
    if(dir){while(auto *entry=readdir(dir))if(strcmp(entry->d_name,".")&&strcmp(entry->d_name,"..")){empty=false;break;}closedir(dir);}
    if(!empty){close(fd);return 0;}
    std::lock_guard<std::mutex> lock(fgCaptureLock);
    if(fgCaptureBusy){close(fd);return 0;}
    auto *s=[HuskFGCaptureSession new];s->_fd=fd;s->_limit=c->pair_limit;s->_first=c->first_frame;s->_stride=c->frame_stride;s->_base=fgRendered.load();
    if(fgCaptureSession)fgCaptureSession->_cancelled=true;[fgCaptureSession release];fgCaptureSession=s;fgCaptureEnabled=true;fgCaptureTimingEnabled=true;
    fprintf(stderr,"[M3/M9-FG-CAPTURE] armed %u pair(s), first after %u completed source frames, stride %u; diagnostic copies are excluded from performance acceptance\n",c->pair_limit,c->first_frame,c->frame_stride);return 1;
}
static void fgCaptureFinish(HuskFGCaptureTicket *t,NSString *failure){
    bool expected=false;if(!t||!t->_finalized.compare_exchange_strong(expected,true))return;
    if(t->_session->_cancelled.load()&&!failure)failure=@"capture configuration superseded";
    {std::lock_guard<std::mutex> lock(fgCaptureLock);if(t->_session==fgCaptureSession&&t->_session->_next>=t->_session->_limit)fgCaptureEnabled=false;}
    dispatch_async(fgCaptureWriter(),^{@autoreleasepool{
        NSString *error=failure;NSMutableArray *files=[NSMutableArray array];
        const char *stages[]={"previous","current","generated","following-real","forward","backward","raw-forward","raw-backward","coarse-forward","coarse-backward","quality"};
        if(!error)for(unsigned i=0;i<11;i++){
            bool field=i>=4,coarse=i==8||i==9,quality=i==10;
            id<MTLBuffer> b=quality?t->_quality:(field?t->_fields[i-4]:t->_images[i]);
            char file[96];snprintf(file,sizeof file,"pair-%02u-%s.%s",t->_id,stages[i],quality?"f32":(field?"f16":"bgra"));
            if(!fgCaptureWrite(t->_session,file,b.contents,b.length)){error=[NSString stringWithFormat:@"file write failed at %s (errno %d)",stages[i],errno];break;}
            [files addObject:@{@"stage":[NSString stringWithUTF8String:stages[i]],@"file":[NSString stringWithUTF8String:file],
                @"width":@(quality?1:(coarse?t->_coarseWidth:(field?t->_flowWidth:t->_width))),@"height":@(quality?1:(coarse?t->_coarseHeight:(field?t->_flowHeight:t->_height))),@"row_bytes":@(quality?256:(coarse?t->_coarseRow:(field?t->_flowRow:t->_row))),
                @"bytes":@(b.length),@"format":quality?@"RGBA32Float":(field?@"RGBA16Float":@"BGRA8Unorm"),@"origin":@"top-left"}];
        }
        double gpuStart[2],gpuEnd[2];{std::lock_guard<std::mutex> lock(t->_stageLock);memcpy(gpuStart,t->_gpuStart,sizeof gpuStart);memcpy(gpuEnd,t->_gpuEnd,sizeof gpuEnd);}
        const float *quality=(const float*)t->_quality.contents;
        id qualityRecord=(!error&&quality)?(id)@{@"coherent_tile_fraction":@(quality[0]),@"mean_forward_backward_error_pixels":@(quality[1]),@"static_tile_fraction":@(quality[2]),@"interpolation_admitted":@(quality[3]>=0.5f),@"minimum_coherent_fraction":@0.80,@"decision":quality[3]>=0.5f?@"interpolation_with_local_boundary_guards":@"whole_frame_real_fallback"}:(id)[NSNull null];
        id imageMeasurements=[NSNull null];
        if(!error){
            const uint8_t *previous=(const uint8_t*)t->_images[0].contents,*current=(const uint8_t*)t->_images[1].contents;
            const uint8_t *generated=(const uint8_t*)t->_images[2].contents,*real=(const uint8_t*)t->_images[3].contents;
            imageMeasurements=@{@"provenance":@"MEASURED from completed full-resolution BGRA readbacks; RGB only; alpha and row padding excluded",
                @"source_pair":fgImageMetricsJSON(fgImageMetrics(previous,current,t->_width,t->_height,t->_row)),
                @"reconstruction_vs_current":fgImageMetricsJSON(fgImageMetrics(current,generated,t->_width,t->_height,t->_row)),
                @"real_copy_vs_current":fgImageMetricsJSON(fgImageMetrics(current,real,t->_width,t->_height,t->_row)),
                @"interpretation":@"An exact generated/current match is a repeat, not unique interpolation. A non-exact following-real/current copy is a presentation-copy defect. Edge sums measure detail change, not proof of perceptual blur or its engine cause; use matched source/generated images and fields."};
        }
        NSDictionary *record=@{@"schema":@2,@"image_measurements":imageMeasurements,@"reconstruction_quality":qualityRecord,@"plan_ids":@[@"M1",@"M3",@"M9"],@"pair_id":@(t->_id),@"state":error?@"incomplete":@"complete",
            @"error":error?: (id)[NSNull null],@"previous_source_sequence":@(t->_previousSequence),@"current_source_sequence":@(t->_currentSequence),@"epoch":@(t->_epoch),
            @"capture_encode_host_monotonic_seconds":@(t->_created),@"previous_source_gpu_completion_callback_host_seconds":fgCaptureTime(t->_sourcePrevious),
            @"current_source_gpu_completion_callback_host_seconds":fgCaptureTime(t->_sourceCurrent),@"source_gpu_execution_timestamps":@"UNAVAILABLE for source Metal4 feedback; callback time is not GPU duration",
            @"generated_gpu_stage":@"reconstruction before display tick; separate output-copy/presentation timestamps are in consumer-timing.json",
            @"generated_gpu_start_seconds":fgCaptureTime(gpuStart[0]),@"generated_gpu_end_seconds":fgCaptureTime(gpuEnd[0]),
            @"real_gpu_start_seconds":fgCaptureTime(gpuStart[1]),@"real_gpu_end_seconds":fgCaptureTime(gpuEnd[1]),@"files":files,
            @"input_stage":@"colour handed to framegen after engine postprocessing and any upstream spatial pass; source Metal4 has no spatial pass",
            @"field_stages":@"coarse64px -> raw16px residual refinement -> median3x3 with dense residual recheck; forward/backward are final fields",
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),fgCaptureWriter(),^{@autoreleasepool{
            {std::lock_guard<std::mutex> lock(fgCaptureLock);if(fgCaptureSession==session)fgCaptureTimingEnabled=false;}
            fgCaptureFlushTimings(session);
        }});
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
    t->_flowWidth=fw;t->_flowHeight=fh;t->_flowRow=(fw*8+255)&~255u;
    t->_coarseWidth=(fw+3)/4;t->_coarseHeight=(fh+3)/4;t->_coarseRow=(t->_coarseWidth*8+255)&~255u;t->_previousSequence=previous;t->_currentSequence=current;t->_epoch=epoch;
    t->_created=CACurrentMediaTime();t->_sourcePrevious=previousTime;t->_sourceCurrent=currentTime;
    uint64_t size=uint64_t(t->_row)*h,flowSize=uint64_t(t->_flowRow)*fh,coarseSize=uint64_t(t->_coarseRow)*t->_coarseHeight,total=4*size+4*flowSize+2*coarseSize+256;
    bool admitted=w>=1&&h>=1&&w<=4096&&h<=4096&&fw>=1&&fh>=1&&fw<=256&&fh<=256&&total<=(64ULL<<20);
#if TARGET_OS_IOS
    admitted=admitted&&os_proc_available_memory()>total+(128ULL<<20);
#endif
    if(admitted){for(auto &b:t->_images){b=[device newBufferWithLength:size options:MTLResourceStorageModeShared];if(b)memset(b.contents,0,b.length);}
        for(unsigned i=0;i<6;i++){auto &b=t->_fields[i];b=[device newBufferWithLength:(i>=4?coarseSize:flowSize) options:MTLResourceStorageModeShared];if(b)memset(b.contents,0,b.length);}
        t->_quality=[device newBufferWithLength:256 options:MTLResourceStorageModeShared];if(t->_quality)memset(t->_quality.contents,0,256);}
    bool allocated=admitted&&t->_quality!=nil;for(auto b:t->_images)allocated=allocated&&b!=nil;for(auto b:t->_fields)allocated=allocated&&b!=nil;
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
static void fgCaptureObserve(id<MTLCommandBuffer> command,id<CAMetalDrawable> drawable,bool generated,bool diagnostic,uint64_t sequence,uint64_t epoch,double targetHost=0,double sourceCompletedHost=0,bool preparation=false){
    if(!fgCaptureTimingEnabled.load(std::memory_order_relaxed))return;
    HuskFGCaptureSession *s;unsigned index;uint64_t recordID;
    {std::lock_guard<std::mutex> lock(fgCaptureLock);s=fgCaptureSession;if(!s||s->_cancelled.load())return;[s retain];}
    {std::lock_guard<std::mutex> lock(s->_timingLock);index=(diagnostic&&!preparation)?(generated?128:129):s->_timingCount++%128;recordID=++s->_commands;
     if(index<128&&s->_timingCount>128)++s->_timingLost;
     auto &r=index>=128?s->_pinned[index-128]:s->_timings[index];r={};r.recordID=recordID;r.sequence=sequence;r.epoch=epoch;r.generated=generated;r.diagnostic=diagnostic;r.preparation=preparation;r.targetHost=targetHost;r.sourceCompletedHost=sourceCompletedHost;r.submitHost=CACurrentMediaTime();}
    [command addCompletedHandler:^(id<MTLCommandBuffer> done){std::lock_guard<std::mutex> lock(s->_timingLock);auto &r=index>=128?s->_pinned[index-128]:s->_timings[index];
        if(r.recordID!=recordID){++s->_lateCallbacks;return;}
        r.completionHost=CACurrentMediaTime();r.gpuStart=done.GPUStartTime;r.gpuEnd=done.GPUEndTime;
        r.gpuValid=done.status==MTLCommandBufferStatusCompleted&&std::isfinite(r.gpuStart)&&std::isfinite(r.gpuEnd)&&r.gpuStart>0&&r.gpuEnd>=r.gpuStart;}];
    [drawable addPresentedHandler:^(id<MTLDrawable> shown){std::lock_guard<std::mutex> lock(s->_timingLock);auto &r=index>=128?s->_pinned[index-128]:s->_timings[index];
        if(r.recordID!=recordID){++s->_lateCallbacks;return;}
        r.presented=shown.presentedTime;r.presentObserved=CACurrentMediaTime();r.presentValid=std::isfinite(r.presented)&&r.presented>0;}];[s release];
}
