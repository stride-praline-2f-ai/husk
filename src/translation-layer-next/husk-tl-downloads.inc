/* NSURLSession streams Android DownloadManager files to disk; no guest TLS or whole-file byte arrays. */
static pthread_mutex_t g_dl_lock = PTHREAD_MUTEX_INITIALIZER;
@class HuskDownload;
static NSMutableDictionary<NSNumber *, HuskDownload *> *g_downloads;
@interface HuskDownload : NSObject <NSURLSessionDownloadDelegate>
@property int64_t identifier, received, total;
@property int status, reason;
@property BOOL removed;
@property(nonatomic,copy) NSString *destination;
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSURLSessionDownloadTask *task;
@end
static void download_finish(HuskDownload *d, int status, int reason)
{
    pthread_mutex_lock(&g_dl_lock);
    BOOL publish=!d.removed && d.status<8;
    if (publish) { d.reason=reason; d.status=status; }
    pthread_mutex_unlock(&g_dl_lock);
    if (publish) emit(@"D",0,@[[NSString stringWithFormat:@"%lld",(long long)d.identifier]]);
}
@implementation HuskDownload
- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytes totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)expected
{
    (void)s; (void)task; (void)bytes;
    pthread_mutex_lock(&g_dl_lock); self.received=written; self.total=expected; pthread_mutex_unlock(&g_dl_lock);
}
- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location
{
    (void)s;
    NSHTTPURLResponse *response=[task.response isKindOfClass:NSHTTPURLResponse.class]?(id)task.response:nil;
    if (!response || response.statusCode<200 || response.statusCode>=300) { download_finish(self,16,response?(int)response.statusCode:1001); return; }
    pthread_mutex_lock(&g_dl_lock); BOOL removed=self.removed; pthread_mutex_unlock(&g_dl_lock);
    if (removed) return;
    NSError *error=nil;
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *part=[self.destination stringByAppendingFormat:@".husk-download-%lld.part",(long long)self.identifier];
    BOOL copied=[fm copyItemAtURL:location toURL:[NSURL fileURLWithPath:part] error:&error];
    BOOL moved=copied && [fm moveItemAtPath:part toPath:self.destination error:&error];
    if (copied && !moved) [fm removeItemAtPath:part error:NULL];
    pthread_mutex_lock(&g_dl_lock); removed=self.removed;
    if (moved && !removed) { self.received=task.countOfBytesReceived; self.total=self.received; self.status=8; self.reason=0; }
    pthread_mutex_unlock(&g_dl_lock);
    if (removed) { if (moved) [fm removeItemAtPath:self.destination error:NULL]; return; }
    if (moved) emit(@"D",0,@[[NSString stringWithFormat:@"%lld",(long long)self.identifier]]);
    else download_finish(self,16,error.code==NSFileWriteFileExistsError?1009:1001);
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    (void)task;
    if (error) download_finish(self,16,1001);
    [s finishTasksAndInvalidate];
    self.task=nil; self.session=nil;
}
@end
static void download_start(int64_t identifier, NSString *url, NSString *destination, NSArray<NSString *> *headers)
{
    HuskDownload *d=[HuskDownload new]; d.identifier=identifier; d.status=2; d.total=-1; d.destination=destination;
    pthread_mutex_lock(&g_dl_lock);
    if (!g_downloads) g_downloads=[NSMutableDictionary dictionary];
    if (g_downloads[@(identifier)]) { pthread_mutex_unlock(&g_dl_lock); return; }
    g_downloads[@(identifier)]=d;
    pthread_mutex_unlock(&g_dl_lock);
    extern const char *tl_data_dir(void);
    NSString *root=[[[NSString stringWithUTF8String:tl_data_dir()] stringByStandardizingPath] stringByResolvingSymlinksInPath];
    NSString *dest=[[destination stringByStandardizingPath] stringByResolvingSymlinksInPath];
    NSURL *u=url?[NSURL URLWithString:url]:nil;
    if (!([u.scheme isEqual:@"https"] || [u.scheme isEqual:@"http"]) || ![dest hasPrefix:[root stringByAppendingString:@"/"]]) { download_finish(d,16,1001); return; }
    d.destination=dest;
    NSError *error=nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]) { download_finish(d,16,1001); return; }
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:u];
    request.timeoutInterval=60;
    for (NSUInteger i=0;i+1<headers.count;i+=2) [request setValue:headers[i+1] forHTTPHeaderField:headers[i]];
    NSURLSessionConfiguration *config=[NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForResource=3600; config.URLCache=nil;
    request.cachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    NSOperationQueue *queue=[NSOperationQueue new]; queue.maxConcurrentOperationCount=1; queue.qualityOfService=NSQualityOfServiceUtility;
    d.session=[NSURLSession sessionWithConfiguration:config delegate:d delegateQueue:queue];
    d.task=[d.session downloadTaskWithRequest:request]; [d.task resume];
}
static NSArray<NSString *> *download_snapshot(int64_t identifier)
{
    pthread_mutex_lock(&g_dl_lock); HuskDownload *d=g_downloads[@(identifier)];
    NSArray *snapshot=d?@[[NSString stringWithFormat:@"%d",d.status],[NSString stringWithFormat:@"%d",d.reason],
        [NSString stringWithFormat:@"%lld",(long long)d.received],[NSString stringWithFormat:@"%lld",(long long)d.total]]:nil;
    pthread_mutex_unlock(&g_dl_lock); return snapshot;
}
static BOOL download_remove(int64_t identifier)
{
    pthread_mutex_lock(&g_dl_lock); HuskDownload *d=g_downloads[@(identifier)];
    if (d) { d.removed=YES; [g_downloads removeObjectForKey:@(identifier)]; }
    pthread_mutex_unlock(&g_dl_lock);
    if (!d) return NO;
    [d.task cancel]; [d.session invalidateAndCancel];
    // Only a successfully published file belongs to this download; never remove an existing destination on failure.
    if (d.status==8) [NSFileManager.defaultManager removeItemAtPath:d.destination error:NULL];
    return YES;
}
