#!/usr/bin/env python3
"""Run the actual WK bridge for a script-only page, attachment response and HTTP error."""
import http.server,platform,subprocess,tempfile,threading,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class Server(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):
  if self.path=='/deck':
   self.send_response(200);self.send_header('Content-Type','application/octet-stream');self.send_header('Content-Disposition','attachment; filename="sample.apkg"');self.end_headers();self.wfile.write(b'PK\x03\x04deck');return
  if self.path=='/rate':
   self.send_response(429);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(b'<p>Login required</p>');return
  self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers()
  self.wfile.write(b'<html><body><script type="module">document.body.innerHTML=`ANKI-MODULE-READY<button id="download">Download</button>`;document.querySelector("#download").onclick=()=>{window.location.href="/deck"}</script></body></html>')
PROGRAM=r'''
#import <Cocoa/Cocoa.h>
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include "husk-tl-dvm-web.m"
void tl_log_line(const char *format,...) { (void)format; }
void tl_javaapp_web_events(void) {}
const char *tl_jni_string(const jobj *value) { return (const char *)value; }
const char *tl_data_dir(void) { return "/tmp"; }
static BOOL has_event(NSString *kind) {
 BOOL found=NO;
 pthread_mutex_lock(&g_ev_lock);
 for(int i=0;i<g_nev;i++) {
  NSString *event=[NSString stringWithUTF8String:g_ev[i]];
  if([event hasPrefix:[kind stringByAppendingString:@"\x1f"]])found=YES;
 }
 pthread_mutex_unlock(&g_ev_lock);return found;
}
static void clear_events(void) {
 pthread_mutex_lock(&g_ev_lock);for(int i=0;i<g_nev;i++)free(g_ev[i]);g_nev=0;pthread_mutex_unlock(&g_ev_lock);
}
static int asset_requests;
static void pump(void) {
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 // A test navigation has no guest override; deliver its actual parked completion.
 for(NSNumber *key in g_pending.allKeys) if(g_pending[key].kind==HuskWebNavigation) {
  jvalue reply[2]={0},result={0};reply[0].i=key.intValue;reply[1].l=(jobj *)"\1nav-allow";
  W_reply(NULL,reply,&result);
 }
 for(NSNumber *key in g_pending.allKeys) if(g_pending[key].kind==HuskWebScheme) {
  id<WKURLSchemeTask> task=g_pending[key].value;
  assert([task.request.URL.host isEqualToString:@"android_asset"]);
  BOOL script=[task.request.URL.path hasSuffix:@"card.js"];
  NSString *body=script?@"window._showQuestion=function(){document.getElementById('qa').textContent='ANKI-CARD-READY';};":@"body{color:rgb(1,2,3)}";
  NSData *bytes=[body dataUsingEncoding:NSUTF8StringEncoding];
  jobj data={.kind=TL_K_PRIM_ARRAY};data.arr.data=(void*)bytes.bytes;data.arr.len=(uint32_t)bytes.length;
  jvalue a[7]={0},r={0};a[0].i=key.intValue;a[1].i=200;a[2].l=(jobj*)"OK";a[3].l=(jobj*)(script?"text/javascript":"text/css");a[4].l=(jobj*)"utf-8";a[6].l=&data;
  W_respond(NULL,a,&r);asset_requests++;
 }
}
int main(int argc,char **argv) { @autoreleasepool {
 assert(argc==2);[NSApplication sharedApplication];
 NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(10,10,600,400) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
 window.releasedWhenClosed=NO;
 NSView *host=[[NSView alloc]initWithFrame:NSMakeRect(0,0,600,400)];window.contentView=host;[window orderFrontRegardless];
 g_container=host;g_screen=host;g_scale=1;
 HuskWeb *h=[[HuskWeb alloc]initWithId:1];g_views=[NSMutableDictionary dictionaryWithObject:h forKey:@1];
 jvalue args[7]={0},ret={0};args[0].i=1;args[3].i=600;args[4].i=400;args[5].i=1;args[6].i=1;W_frame(NULL,args,&ret);
 args[1].i=1;args[2].l=NULL;args[3].i=100;args[4].i=0;W_settings(NULL,args,&ret);
 for(int i=0;i<5;i++)pump();
 NSString *base=[NSString stringWithUTF8String:argv[1]];
 // Only virtual Android resource prefixes are rewritten; arbitrary files,
 // public URLs, non-text and non-UTF8 bytes retain their original payload.
 NSData *sample=[@"file:///android_asset/a.js file:/android_res/b.css file:///private/keep https://keep" dataUsingEncoding:NSUTF8StringEncoding];
 NSString *mapped=[[NSString alloc]initWithData:android_resource_urls(sample,@"text/html",@"utf-8") encoding:NSUTF8StringEncoding];
 assert([mapped containsString:@"huskapp://android_asset/a.js"]&&[mapped containsString:@"huskapp://android_res/b.css"]&&[mapped containsString:@"file:///private/keep https://keep"]);
 assert(android_resource_urls(sample,@"application/octet-stream",nil)==sample);
 assert(android_resource_urls(sample,@"text/html",@"utf-16")==sample);
 unsigned char invalid[]={255,254,255};NSData *binary=[NSData dataWithBytes:invalid length:3];assert(android_resource_urls(binary,@"text/html",@"utf-8")==binary);
 NSString *card=@"<html><head><link rel='stylesheet' href='file:///android_asset/flashcard.css'><script src='file:///android_asset/scripts/card.js'></script></head><body id='qa'></body></html>";
 NSData *cardBytes=[card dataUsingEncoding:NSUTF8StringEncoding];
 // Reproduce WebKit's failure before applying the production mapping.
 clear_events();h.apiLoad=YES;[h.web loadData:cardBytes MIMEType:@"text/html" characterEncodingName:@"utf-8" baseURL:[NSURL URLWithString:base]];
 for(int i=0;i<1000&&!has_event(@"f");i++)pump();assert(has_event(@"f"));
 __block BOOL checked=NO;[h.web evaluateJavaScript:@"typeof _showQuestion" completionHandler:^(id r,NSError*e){assert(!e&&[r isEqual:@"undefined"]);checked=YES;}];
 for(int i=0;i<500&&!checked;i++)pump();assert(checked);
 // Actual W_loadData/W_respond path must load the same file:///android_asset
 // references used by Anki's pinned card_template.html, before page-finished.
 clear_events();jobj data={.kind=TL_K_PRIM_ARRAY};data.arr.data=(void*)cardBytes.bytes;data.arr.len=(uint32_t)cardBytes.length;
 jvalue load[5]={0};load[0].i=1;load[1].l=&data;load[2].l=(jobj*)"text/html";load[3].l=(jobj*)"utf-8";load[4].l=(jobj*)base.UTF8String;W_loadData(NULL,load,&ret);
 for(int i=0;i<1000&&!has_event(@"f");i++)pump();assert(has_event(@"f")&&asset_requests>=2);
 checked=NO;[h.web evaluateJavaScript:@"_showQuestion();document.body.textContent" completionHandler:^(id r,NSError*e){assert(!e&&[r containsString:@"ANKI-CARD-READY"]);checked=YES;}];
 for(int i=0;i<500&&!checked;i++)pump();assert(checked);
 clear_events();h.apiLoad=YES;[h.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:base]]];
 for(int i=0;i<1000 && !has_event(@"f");i++)pump();assert(has_event(@"f"));
 __block BOOL evaluated=NO;__block NSString *text=nil;
 [h.web evaluateJavaScript:@"document.body.textContent" completionHandler:^(id result,NSError *error){assert(!error);text=result;evaluated=YES;}];
 for(int i=0;i<500 && !evaluated;i++)pump();assert(evaluated && [text containsString:@"ANKI-MODULE-READY"] && !h.web.hidden && h.web.frame.size.width==600);
 // AnkiWeb's real button assigns window.location.href; do not bypass its navigation-policy reply.
 [h.web evaluateJavaScript:@"document.querySelector('#download').click()" completionHandler:nil];
 for(int i=0;i<1000 && !has_event(@"d");i++)pump();assert(has_event(@"d"));
 h.apiLoad=YES;[h.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:@"rate"]]]];
 for(int i=0;i<1000 && !has_event(@"H");i++)pump();assert(has_event(@"H"));
 [h teardown];pending_cancel_all();[window close];
 puts("actual WKWebView Android card assets/_showQuestion/module page/frame/attachment/HTTP429 passed");return 0;
} }
'''
@unittest.skipUnless(platform.system()=='Darwin','WebKit executes on Apple cloud runner')
class WebKitTests(unittest.TestCase):
 def test_actual_script_only_page_download_and_http_response(self):
  server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Server);threading.Thread(target=server.serve_forever,daemon=True).start()
  try:
   with tempfile.TemporaryDirectory() as td:
    p=Path(td);(p/'test.m').write_text(PROGRAM)
    cmd=['clang','-fobjc-arc','-fblocks','-Wno-deprecated-declarations','-I',str(ROOT/'src/translation-layer-next'),str(p/'test.m'),'-framework','Cocoa','-framework','WebKit','-Wl,-undefined,dynamic_lookup','-o',str(p/'test')]
    c=subprocess.run(cmd,capture_output=True,text=True);self.assertEqual(c.returncode,0,c.stdout+c.stderr)
    r=subprocess.run([str(p/'test'),f'http://127.0.0.1:{server.server_port}/'],capture_output=True,text=True,timeout=90)
    self.assertEqual(r.returncode,0,r.stdout+r.stderr)
  finally:server.shutdown();server.server_close()
if __name__=='__main__':unittest.main(verbosity=2)
