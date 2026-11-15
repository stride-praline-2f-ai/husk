/* SPDX-License-Identifier: GPL-2.0-or-later
 * NX18/Henge-inspired exact library reuse and Metal-owned native archives.
 * No serialized Vulkan handles, guessed PSOs, or raw descriptor pointer keys.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CommonCrypto/CommonDigest.h>
#include <atomic>
#include <mutex>
#include <shared_mutex>
#include <vector>
#include <algorithm>
#include <sys/stat.h>
#include <string.h>
#include <stdio.h>
#include "HuskNativeArchiveABI.h"

static std::mutex ownersLock;
@class HuskMetal4Compiler;
static std::vector<HuskMetal4Compiler *> compilerOwners;
static NSString *archiveRoot;
static bool archiveEnabled,archiveVerify;
static std::atomic<uint64_t> captures{0},hits{0},misses{0},writes{0},writeBytes{0},readBytes{0},readErrors{0},writeErrors{0},evictions{0},evictedBytes{0},libraryHits{0},libraryLoads{0},prepareCalls{0};
static NSString *huskDigest(NSData *data){
    unsigned char d[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,d);
    NSMutableString *s=[NSMutableString stringWithCapacity:64];for(unsigned i=0;i<sizeof(d);i++)[s appendFormat:@"%02x",d[i]];return s;
}

@interface HuskMetal4CompileEpoch : NSObject {
@public
    id<MTL4Compiler> compiler;
    id<MTL4PipelineDataSetSerializer> capture;
    std::shared_mutex gate;
    std::atomic<unsigned> pending;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device capture:(BOOL)enabled;
@end
@implementation HuskMetal4CompileEpoch
- (instancetype)initWithDevice:(id<MTLDevice>)device capture:(BOOL)enabled {
    if(!(self=[super init]))return nil;pending=0;
    MTL4CompilerDescriptor *desc=[MTL4CompilerDescriptor new];
    if(enabled){
        MTL4PipelineDataSetSerializerDescriptor *c=[MTL4PipelineDataSetSerializerDescriptor new];
        c.configuration=MTL4PipelineDataSetSerializerConfigurationCaptureBinaries;
        capture=[device newPipelineDataSetSerializerWithDescriptor:c];[c release];desc.pipelineDataSetSerializer=capture;
    }
    NSError *error=nil;compiler=[device newCompilerWithDescriptor:desc error:&error];[desc release];
    if(!compiler){fprintf(stderr,"[M3 METAL4] compiler creation failed: %s\n",error.localizedDescription.UTF8String?:"unavailable");[self release];return nil;}return self;
}
- (void)dealloc {[compiler release];[capture release];[super dealloc];}
@end

@interface HuskMetal4Compiler : NSObject {
    id<MTLDevice> _device;
    HuskMetal4CompileEpoch *_epoch;
    NSLock *_lock;
    NSCondition *_libraryLock;
    NSMutableDictionary *_libraries;
    NSMutableSet *_loading;
    NSMutableArray *_libraryOrder;
    NSUInteger _libraryBytes;
    NSArray *_archives;
    NSURL *_directory,*_root;
    dispatch_queue_t _saveQueue;
    BOOL _savingScheduled,_enabled;
    std::atomic<unsigned> _pending;
    std::atomic<bool> _urgentSaveScheduled;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (id<MTLLibrary>)newLibraryWithDescriptor:(MTL4LibraryDescriptor *)desc error:(NSError **)error;
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTL4RenderPipelineDescriptor *)desc compilerTaskOptions:(MTL4CompilerTaskOptions *)options error:(NSError **)error;
- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor *)desc compilerTaskOptions:(MTL4CompilerTaskOptions *)options error:(NSError **)error;
- (void)scheduleSave;
- (void)checkpoint;
- (void)save;
- (unsigned)pending;
- (void)prune;
- (void)loadArchives;
- (HuskMetal4CompileEpoch *)epoch;
- (id)pipeline:(id)desc compute:(BOOL)compute options:(MTL4CompilerTaskOptions *)options error:(NSError **)error;
@end

@implementation HuskMetal4Compiler
- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if(!(self=[super init]))return nil;
    _device=[device retain];_lock=[NSLock new];_libraryLock=[NSCondition new];
    _libraries=[NSMutableDictionary new];_loading=[NSMutableSet new];_libraryOrder=[NSMutableArray new];_archives=[NSArray new];_pending=0;_urgentSaveScheduled=false;
    NSString *path=nil;{std::lock_guard<std::mutex> guard(ownersLock);_enabled=archiveEnabled;path=[archiveRoot copy];}
    if(_enabled&&path.length){
        NSOperatingSystemVersion os=NSProcessInfo.processInfo.operatingSystemVersion;
        // Increment the contract when compiler/descriptor semantics change.
        NSString *identity=[NSString stringWithFormat:@"husk-kk-native-v1/b39d173c/26620bf5/%@/%@/%llu/%ld.%ld.%ld/%@/%s/%s",
            device.name,device.architecture.name,(unsigned long long)device.registryID,(long)os.majorVersion,(long)os.minorVersion,(long)os.patchVersion,
            NSProcessInfo.processInfo.operatingSystemVersionString,getenv("MESA_KK_DISABLE_WORKAROUNDS")?:"",getenv("MESA_KK_DEBUG")?:""];
        _root=[[NSURL fileURLWithPath:path isDirectory:YES]retain];
        _directory=[[_root URLByAppendingPathComponent:huskDigest([identity dataUsingEncoding:NSUTF8StringEncoding]) isDirectory:YES]retain];
        NSFileManager *fm=NSFileManager.defaultManager;
        [fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
        struct stat st;if(lstat(_root.path.fileSystemRepresentation,&st)||!S_ISDIR(st.st_mode))_enabled=NO;
        if(_enabled){
            [fm createDirectoryAtURL:_directory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil];
            if(lstat(_directory.path.fileSystemRepresentation,&st)||!S_ISDIR(st.st_mode))_enabled=NO;
        }
        if(!_enabled)++writeErrors;
        if(_enabled){[self prune];[self loadArchives];}
    }else _enabled=NO;
    [path release];
    _epoch=[[HuskMetal4CompileEpoch alloc]initWithDevice:device capture:_enabled];
    _saveQueue=dispatch_queue_create("com.husk.metal4.archive",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));
    if(!_epoch){[self release];return nil;}
    {std::lock_guard<std::mutex> guard(ownersLock);compilerOwners.push_back(self);}
    return self;
}
- (void)prune {
    NSFileManager *fm=NSFileManager.defaultManager;NSMutableArray *files=[NSMutableArray array];
    NSDirectoryEnumerator *en=[fm enumeratorAtURL:_root includingPropertiesForKeys:@[NSURLFileSizeKey,NSURLContentModificationDateKey,NSURLIsSymbolicLinkKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    for(NSURL *url in en){NSNumber *symlink=nil;[url getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:nil];
        if(symlink.boolValue){[en skipDescendants];continue;}
        struct stat st;if([url.pathExtension isEqual:@"mtl4a"]&&!lstat(url.path.fileSystemRepresentation,&st)&&S_ISREG(st.st_mode))[files addObject:url];
    }
    [files sortUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){NSDate *ad=nil,*bd=nil;[a getResourceValue:&ad forKey:NSURLContentModificationDateKey error:nil];[b getResourceValue:&bd forKey:NSURLContentModificationDateKey error:nil];return [bd compare:ad];}];
    uint64_t bytes=0;unsigned count=0;
    for(NSURL *url in files){NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];uint64_t n=size.unsignedLongLongValue;
        if(!n||n>(64ULL<<20)||count>=32||bytes>(128ULL<<20)-n){if([fm removeItemAtURL:url error:nil]){++evictions;evictedBytes+=n;}}
        else{++count;bytes+=n;}
    }
}
- (void)loadArchives {
    NSMutableArray *loaded=[NSMutableArray array];uint64_t bytes=0;
    NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:_directory includingPropertiesForKeys:@[NSURLFileSizeKey,NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    files=[files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){NSDate *ad=nil,*bd=nil;[a getResourceValue:&ad forKey:NSURLContentModificationDateKey error:nil];[b getResourceValue:&bd forKey:NSURLContentModificationDateKey error:nil];return [bd compare:ad];}];
    for(NSURL *url in files){
        if(![url.pathExtension isEqual:@"mtl4a"])continue;
        struct stat st;if(lstat(url.path.fileSystemRepresentation,&st)||!S_ISREG(st.st_mode)||st.st_size<256||st.st_size>(64LL<<20)||loaded.count>=16||bytes+st.st_size>(64ULL<<20))continue;
        NSError *error=nil;id<MTL4Archive> archive=[_device newArchiveWithURL:url error:&error];
        if(archive){[loaded addObject:archive];bytes+=st.st_size;[archive release];}
        else ++readErrors;
    }
    NSArray *next=[loaded copy];[_lock lock];NSArray *old=_archives;_archives=next;[_lock unlock];[old release];readBytes+=bytes;
}
- (HuskMetal4CompileEpoch *)epoch {
    [_lock lock];HuskMetal4CompileEpoch *e=[_epoch retain];
    // Admission and the shared lease are atomic with epoch rotation. A caller
    // cannot obtain the old epoch, pause, then compile after it was flushed.
    e->gate.lock_shared();[_lock unlock];return e;
}
- (id<MTLLibrary>)newLibraryWithDescriptor:(MTL4LibraryDescriptor *)desc error:(NSError **)error {
    MTLCompileOptions *o=desc.options;
    NSString *contract=[NSString stringWithFormat:@"%lu/%lu/%lu/%lu/",(unsigned long)o.languageVersion,(unsigned long)o.mathMode,(unsigned long)o.mathFloatingPointFunctions,(unsigned long)o.optimizationLevel];
    NSMutableData *key=[NSMutableData dataWithData:[contract dataUsingEncoding:NSUTF8StringEncoding]];[key appendData:[desc.source dataUsingEncoding:NSUTF8StringEncoding]];
    // This entrypoint is used only with Mesa's fixed options above. Exact MSL
    // plus all options set by mtl_new_library form the immutable key.
    [_libraryLock lock];while([_loading containsObject:key])[_libraryLock wait];
    id<MTLLibrary> cached=_libraries[key];
    if(cached){++libraryHits;[cached retain];[_libraryOrder removeObject:key];[_libraryOrder addObject:key];[_libraryLock unlock];if(error)*error=nil;return cached;}
    NSData *loading=[key copy];[_loading addObject:loading];[loading release];[_libraryLock unlock];
    ++libraryLoads;HuskMetal4CompileEpoch *e=[self epoch];id<MTLLibrary> library;
    {std::shared_lock<std::shared_mutex> gate(e->gate,std::adopt_lock);library=[e->compiler newLibraryWithDescriptor:desc error:error];}[e release];
    [_libraryLock lock];
    if(library&&key.length<=(32ULL<<20)&&!getenv("HUSK_METAL4_LIBRARY_CACHE_OFF")){
        while(_libraryOrder.count&&(_libraryOrder.count>=64||_libraryBytes>(32ULL<<20)-key.length)){
            NSData *old=[[_libraryOrder objectAtIndex:0]retain];_libraryBytes-=old.length;[_libraries removeObjectForKey:old];[_libraryOrder removeObjectAtIndex:0];[old release];
        }
        NSData *copy=[key copy];_libraries[copy]=library;[_libraryOrder addObject:copy];_libraryBytes+=copy.length;[copy release];
    }
    [_loading removeObject:key];[_libraryLock broadcast];[_libraryLock unlock];return library;
}
- (id)pipeline:(id)desc compute:(BOOL)compute options:(MTL4CompilerTaskOptions *)options error:(NSError **)error {
    [_lock lock];NSArray *archives=[_archives retain];[_lock unlock];id state=nil;
    for(id<MTL4Archive> archive in archives){
        state=compute?(id)[archive newComputePipelineStateWithDescriptor:desc error:nil]:(id)[archive newRenderPipelineStateWithDescriptor:desc error:nil];
        if(state){++hits;break;}
    }[archives release];
    if(state){if(error)*error=nil;return state;}if(_enabled)++misses;
    HuskMetal4CompileEpoch *e=[self epoch];
    {std::shared_lock<std::shared_mutex> gate(e->gate,std::adopt_lock);
        state=compute?(id)[e->compiler newComputePipelineStateWithDescriptor:desc compilerTaskOptions:options error:error]:(id)[e->compiler newRenderPipelineStateWithDescriptor:desc compilerTaskOptions:options error:error];
        if(state&&e->capture){++e->pending;++_pending;++captures;}
    }[e release];
    if(state&&_enabled)[self scheduleSave];return state;
}
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTL4RenderPipelineDescriptor *)d compilerTaskOptions:(MTL4CompilerTaskOptions *)o error:(NSError **)e {return [self pipeline:d compute:NO options:o error:e];}
- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor *)d compilerTaskOptions:(MTL4CompilerTaskOptions *)o error:(NSError **)e {return [self pipeline:d compute:YES options:o error:e];}
- (unsigned)pending {return _pending.load();}
- (void)scheduleSave {
    if(_pending.load()>=64)[self checkpoint];
    [_lock lock];if(_savingScheduled){[_lock unlock];return;}_savingScheduled=YES;[_lock unlock];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),_saveQueue,^{[self save];});
}
- (void)checkpoint {
    bool expected=false;
    if(_enabled&&_pending.load()&&_urgentSaveScheduled.compare_exchange_strong(expected,true))
        dispatch_async(_saveQueue,^{[self save];});
}
- (void)save {
    _urgentSaveScheduled=false;
    [_lock lock];_savingScheduled=NO;
    if(!_enabled||!_pending.load()||!_epoch->capture){[_lock unlock];return;}
    [_lock unlock];
    HuskMetal4CompileEpoch *next=[[HuskMetal4CompileEpoch alloc]initWithDevice:_device capture:YES];
    if(!next){++writeErrors;return;}
    [_lock lock];
    if(!_pending.load()){[_lock unlock];[next release];return;}
    HuskMetal4CompileEpoch *old=_epoch;_epoch=next;[_lock unlock];
    // No future caller can obtain old. Wait only on Utility for already active
    // compiles; normal pipeline compilation keeps shared parallel access.
    std::unique_lock<std::shared_mutex> gate(old->gate);
    NSURL *final=[_directory URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"mtl4a"]];
    NSURL *temporary=[final URLByAppendingPathExtension:@"new"];NSError *error=nil;
    BOOL saved=[old->capture serializeAsArchiveAndFlushToURL:temporary error:&error];
    struct stat st;if(saved)saved=!lstat(temporary.path.fileSystemRepresentation,&st)&&S_ISREG(st.st_mode)&&st.st_size>=256&&st.st_size<=(64LL<<20);
    if(saved)saved=[NSFileManager.defaultManager moveItemAtURL:temporary toURL:final error:&error];
    if(saved){++writes;writeBytes+=st.st_size;[self prune];[self loadArchives];}
    else{++writeErrors;[NSFileManager.defaultManager removeItemAtURL:temporary error:nil];}
    _pending.fetch_sub(old->pending.load());gate.unlock();[old release];
}
- (void)dealloc {
    {std::lock_guard<std::mutex> guard(ownersLock);auto i=std::find(compilerOwners.begin(),compilerOwners.end(),self);if(i!=compilerOwners.end())compilerOwners.erase(i);}
    [_epoch release];[_device release];[_lock release];[_libraryLock release];[_libraries release];[_loading release];[_libraryOrder release];[_archives release];[_directory release];[_root release];
#if OS_OBJECT_USE_OBJC
    [(id)_saveQueue release];
#else
    if(_saveQueue)dispatch_release(_saveQueue);
#endif
    [super dealloc];
}
@end

extern "C" void *husk_metal4_new_compiler(void *device){return [[HuskMetal4Compiler alloc]initWithDevice:(id<MTLDevice>)device];}
extern "C" __attribute__((visibility("default"))) int vkHuskArchiveConfigure(const tl_na_config *c){
    if(!c||c->version!=TL_NATIVE_ARCHIVE_ABI||c->size!=sizeof(*c)||c->enabled>1||c->flags&~TL_NA_VERIFY_REQUIREMENT||!c->directory||strlen(c->directory)>4096)return 0;
    std::lock_guard<std::mutex> guard(ownersLock);if(!compilerOwners.empty())return 0;
    [archiveRoot release];archiveRoot=[[NSString stringWithUTF8String:c->directory]copy];archiveEnabled=c->enabled;archiveVerify=c->flags&TL_NA_VERIFY_REQUIREMENT;return archiveRoot!=nil;
}
extern "C" __attribute__((visibility("default"))) int vkHuskArchiveSnapshot(tl_na_stats *s){
    if(!s||s->version!=TL_NATIVE_ARCHIVE_ABI||s->size!=sizeof(*s))return 0;
    std::lock_guard<std::mutex> guard(ownersLock);uint32_t pending=0;for(HuskMetal4Compiler *c:compilerOwners)pending+=[c pending];
    *s={};s->version=TL_NATIVE_ARCHIVE_ABI;s->size=sizeof(*s);s->requested=archiveEnabled;s->supported=!compilerOwners.empty();s->pending=pending;
    s->descriptors_captured=captures;s->archive_attachments=hits;s->archive_fallbacks=misses;s->saved_bytes=writeBytes;s->restored_bytes=readBytes;
    s->read_failures=readErrors;s->write_failures=writeErrors;s->evicted_files=evictions;s->evicted_bytes=evictedBytes;s->prepare_calls=prepareCalls;
    s->verification_requested=archiveVerify;
    if(archiveVerify){s->verification_attempts=hits+misses;s->archive_requirement_satisfied=hits;s->verification_failures=misses;}
    return 1;
}
extern "C" __attribute__((visibility("default"))) void vkHuskMetal4Checkpoint(void){
    std::lock_guard<std::mutex> guard(ownersLock);for(HuskMetal4Compiler *c:compilerOwners)[c checkpoint];
}
extern "C" __attribute__((visibility("default"))) int vkHuskArchivePrepare(void){++prepareCalls;vkHuskMetal4Checkpoint();return 0;}
extern "C" __attribute__((visibility("default"))) void vkHuskArchiveForget(void){/* Device-owned compiler lifetimes release archive/library mappings. */}
