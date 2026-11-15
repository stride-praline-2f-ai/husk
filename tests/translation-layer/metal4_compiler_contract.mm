// SPDX-License-Identifier: GPL-2.0-or-later
// Production compiler wrapper with controlled Metal objects. This verifies
// ownership/cache/epoch/error contracts, NOT GPU correctness or native hits.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <atomic>
#include <thread>
#include <vector>
#include <cassert>
#include <unistd.h>
#include "HuskMetal4Compiler.mm"

static std::atomic<unsigned> createdCompilers{0},compiledLibraries{0},compiledPipelines{0};
static std::atomic<unsigned> libraryInFlight{0},libraryMax{0};
static std::atomic<bool> failSave{false};
static dispatch_semaphore_t entered,releaseCompile;
@interface ContractState : NSObject
@property BOOL restored;
@end
@implementation ContractState
@end
@interface ContractSerializer : NSObject {
@public std::atomic<unsigned> active;
    std::mutex lock;
    NSMutableArray *labels;
}
@end
@implementation ContractSerializer
- (instancetype)init {if((self=[super init])){active=0;labels=[NSMutableArray new];}return self;}
- (BOOL)serializeAsArchiveAndFlushToURL:(NSURL *)url error:(NSError **)error {
    (void)error;assert(active.load()==0);if(failSave.load())return NO;
    std::lock_guard<std::mutex> guard(lock);
    NSMutableData *data=[NSMutableData dataWithData:[NSJSONSerialization dataWithJSONObject:labels options:0 error:nil]];
    while(data.length<512)[data appendBytes:" " length:1];
    BOOL ok=[data writeToURL:url atomically:NO];if(ok)[labels removeAllObjects];return ok;
}
- (void)dealloc {[labels release];[super dealloc];}
@end
@interface ContractArchive : NSObject {NSSet *_labels;}
- (instancetype)initWithURL:(NSURL *)url;
@end
@implementation ContractArchive
- (instancetype)initWithURL:(NSURL *)url {
    if(!(self=[super init]))return nil;NSData *data=[NSData dataWithContentsOfURL:url];
    id list=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![list isKindOfClass:[NSArray class]]){[self release];return nil;}_labels=[[NSSet alloc]initWithArray:list];return self;
}
- (id)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor *)d error:(NSError **)error {
    (void)error;if(![_labels containsObject:d.label?:@""])return nil;ContractState *s=[ContractState new];s.restored=YES;return s;
}
- (id)newRenderPipelineStateWithDescriptor:(MTL4RenderPipelineDescriptor *)d error:(NSError **)error {return [self newComputePipelineStateWithDescriptor:(id)d error:error];}
- (void)dealloc {[_labels release];[super dealloc];}
@end
@interface ContractCompiler : NSObject {ContractSerializer *_capture;}
- (instancetype)initWithCapture:(id)capture;
@end
@implementation ContractCompiler
- (instancetype)initWithCapture:(id)capture {if((self=[super init]))_capture=[capture retain];return self;}
- (id)newLibraryWithDescriptor:(MTL4LibraryDescriptor *)d error:(NSError **)error {
    (void)d;if(error)*error=nil;++compiledLibraries;
    unsigned active=++libraryInFlight,peak=libraryMax.load();while(active>peak&&!libraryMax.compare_exchange_weak(peak,active)){}
    if(_capture)++_capture->active;usleep(10000);if(_capture)--_capture->active;--libraryInFlight;return [NSObject new];
}
- (id)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor *)d compilerTaskOptions:(id)options error:(NSError **)error {
    (void)options;if(error)*error=nil;++compiledPipelines;
    if(_capture)++_capture->active;
    if([d.label isEqual:@"blocked"]){dispatch_semaphore_signal(entered);assert(!dispatch_semaphore_wait(releaseCompile,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC)));}
    if(_capture){std::lock_guard<std::mutex> guard(_capture->lock);[_capture->labels addObject:d.label?:@""];--_capture->active;}
    return [ContractState new];
}
- (id)newRenderPipelineStateWithDescriptor:(MTL4RenderPipelineDescriptor *)d compilerTaskOptions:(id)o error:(NSError **)e {return [self newComputePipelineStateWithDescriptor:(id)d compilerTaskOptions:o error:e];}
- (void)dealloc {[_capture release];[super dealloc];}
@end
@interface ContractArchitecture : NSObject
@end
@implementation ContractArchitecture
- (NSString *)name {return @"CONTROL-ONLY";}
@end
@interface ContractDevice : NSObject
@end
@implementation ContractDevice
- (NSString *)name {return @"CONTROL-ONLY Metal Device";}
- (id)architecture {return [[[ContractArchitecture alloc]init]autorelease];}
- (uint64_t)registryID {return 42;}
- (id)newPipelineDataSetSerializerWithDescriptor:(id)d {(void)d;return [ContractSerializer new];}
- (id)newCompilerWithDescriptor:(MTL4CompilerDescriptor *)d error:(NSError **)e {
    if(e)*e=nil;++createdCompilers;return [[ContractCompiler alloc]initWithCapture:d.pipelineDataSetSerializer];
}
- (id)newArchiveWithURL:(NSURL *)u error:(NSError **)e {(void)e;return [[ContractArchive alloc]initWithURL:u];}
@end
static id pipeline(HuskMetal4Compiler *c,NSString *label){
    MTL4ComputePipelineDescriptor *d=[MTL4ComputePipelineDescriptor new];d.label=label;
    id state=[c newComputePipelineStateWithDescriptor:d compilerTaskOptions:nil error:nil];[d release];return state;
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==2);entered=dispatch_semaphore_create(0);releaseCompile=dispatch_semaphore_create(0);
    ContractDevice *device=[ContractDevice new];
    NSString *external=[@(argv[1])stringByAppendingString:@"-external"],*link=[@(argv[1])stringByAppendingString:@"-link"];
    [NSFileManager.defaultManager createDirectoryAtPath:external withIntermediateDirectories:YES attributes:nil error:nil];
    assert([NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:external error:nil]);
    tl_na_config invalidRoot={TL_NATIVE_ARCHIVE_ABI,sizeof(invalidRoot),1,0,link.UTF8String};assert(vkHuskArchiveConfigure(&invalidRoot));
    HuskMetal4Compiler *uncached=[[HuskMetal4Compiler alloc]initWithDevice:(id)device];assert(uncached);[pipeline(uncached,@"not-saved-through-link")release];[uncached save];[uncached release];
    assert([NSFileManager.defaultManager contentsOfDirectoryAtPath:external error:nil].count==0);
    tl_na_config cfg={TL_NATIVE_ARCHIVE_ABI,sizeof(cfg),1,0,argv[1]};assert(vkHuskArchiveConfigure(&cfg));
    cfg.version++;assert(!vkHuskArchiveConfigure(&cfg));cfg.version--;
    HuskMetal4Compiler *c=[[HuskMetal4Compiler alloc]initWithDevice:(id)device];assert(c);
    assert(!vkHuskArchiveConfigure(&cfg)); // No live compiler reconfiguration.
    MTL4LibraryDescriptor *ld=[MTL4LibraryDescriptor new];ld.source=@"source-a";
    MTLCompileOptions *opts=[MTLCompileOptions new];opts.mathMode=MTLMathModeFast;ld.options=opts;
    id a=[c newLibraryWithDescriptor:ld error:nil],b=[c newLibraryWithDescriptor:ld error:nil];assert(a==b&&compiledLibraries==1);[a release];[b release];
    ld.source=@"source-b";[[c newLibraryWithDescriptor:ld error:nil]release];assert(compiledLibraries==2);
    opts.mathMode=MTLMathModeSafe;ld.options=opts;[[c newLibraryWithDescriptor:ld error:nil]release];assert(compiledLibraries==3);
    // Exact source concurrent requests share one immutable owned library.
    unsigned before=compiledLibraries.load();std::vector<std::thread> readers;
    for(unsigned i=0;i<8;i++)readers.emplace_back([&]{@autoreleasepool{
        MTL4LibraryDescriptor *d=[MTL4LibraryDescriptor new];d.source=@"concurrent";d.options=[[[MTLCompileOptions alloc]init]autorelease];
        [[c newLibraryWithDescriptor:d error:nil]release];[d release];}});
    for(auto &t:readers)t.join();assert(compiledLibraries==before+1);
    readers.clear();libraryMax=0;
    for(unsigned i=0;i<4;i++)readers.emplace_back([&,i]{@autoreleasepool{
        MTL4LibraryDescriptor *d=[MTL4LibraryDescriptor new];d.source=[NSString stringWithFormat:@"parallel-%u",i];d.options=[[[MTLCompileOptions alloc]init]autorelease];
        [[c newLibraryWithDescriptor:d error:nil]release];[d release];}});
    for(auto &t:readers)t.join();assert(libraryMax>1); // Different keys retain native parallelism.
    [pipeline(c,@"persisted")release];
    id initial=pipeline(c,@"persisted-2");[initial release];[c save];
    tl_na_stats stats={};stats.version=TL_NATIVE_ARCHIVE_ABI;stats.size=sizeof(stats);assert(vkHuskArchiveSnapshot(&stats)&&stats.saved_bytes>=512&&stats.pending==0);
    before=compiledPipelines.load();id restored=pipeline(c,@"persisted-2");assert(((ContractState *)restored).restored&&compiledPipelines==before);[restored release];
    // A second compiler restores the same compatible namespace.
    HuskMetal4Compiler *second=[[HuskMetal4Compiler alloc]initWithDevice:(id)device];assert(second);
    restored=pipeline(second,@"persisted-2");assert(((ContractState *)restored).restored);[restored release];
    // Rotate while an old compile is admitted. New compiles proceed, while the
    // old serializer waits for the exact epoch's active native call to finish.
    [pipeline(c,@"before-rotation")release];
    std::thread producer([&]{@autoreleasepool{[pipeline(c,@"blocked")release];}});
    assert(!dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)));
    Ivar epochIvar=class_getInstanceVariable([HuskMetal4Compiler class],"_epoch");
    NSLock *ownerLock=object_getIvar(c,class_getInstanceVariable([HuskMetal4Compiler class],"_lock"));
    [ownerLock lock];id prior=[object_getIvar(c,epochIvar)retain];[ownerLock unlock];
    std::thread saver([&]{@autoreleasepool{[c save];}});bool rotated=false;
    for(unsigned i=0;i<2000&&!rotated;i++){[ownerLock lock];rotated=object_getIvar(c,epochIvar)!=prior;[ownerLock unlock];if(!rotated)usleep(1000);}
    assert(rotated);[prior release];
    [pipeline(c,@"new-epoch")release];dispatch_semaphore_signal(releaseCompile);producer.join();saver.join();
    [c save];assert(vkHuskArchiveSnapshot(&stats)&&stats.pending==0);
    // File write failure stays advisory; native creation remains usable.
    [pipeline(c,@"save-error")release];failSave=true;[c save];failSave=false;
    assert(vkHuskArchiveSnapshot(&stats)&&stats.write_failures>0);[pipeline(c,@"after-error")release];
    [ld release];[opts release];[second release];[c release];[device release];
    puts("PASS: production Metal4 compiler control contracts; mock GPU/archive objects, no physical hit/energy claim");
    return 0;
}}
