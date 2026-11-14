#!/usr/bin/env python3
"""Exercise disk-streaming NSURLSession backend against controlled local HTTP responses."""
import http.server
import platform
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PAYLOAD=b'PK\x03\x04'+bytes(range(256))*4096
class Server(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a): pass
 def do_GET(self):
  if self.path=='/redirect':
   self.send_response(302);self.send_header('Location','/deck');self.end_headers();return
  if self.path=='/rate':
   self.send_response(429);self.end_headers();self.wfile.write(b'Login required');return
  if self.path=='/deck' and (self.headers.get('Cookie')!='session=test' or self.headers.get('User-Agent')!='Anki contract'):
   self.send_response(403);self.end_headers();return
  self.send_response(200);self.send_header('Content-Type','application/octet-stream');self.send_header('Content-Length',str(len(PAYLOAD)));self.send_header('Content-Disposition','attachment; filename=deck.apkg');self.end_headers()
  try:
   for off in range(0,len(PAYLOAD),16384):
    self.wfile.write(PAYLOAD[off:off+16384]);self.wfile.flush()
    if self.path=='/slow':time.sleep(.03)
  except (BrokenPipeError,ConnectionResetError):pass
PROGRAM=r'''
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <assert.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
static const char *root;
const char *tl_data_dir(void) { return root; }
static int completions;
static void emit(NSString *kind,int wid,NSArray<NSString *> *fields) { (void)wid;(void)fields;assert([kind isEqual:@"D"]);__atomic_fetch_add(&completions,1,__ATOMIC_SEQ_CST); }
#include "husk-tl-downloads.inc"
static NSArray *wait_for(int identifier) {
 for(int i=0;i<1000;i++) { NSArray *s=download_snapshot(identifier);if([s[0] intValue]>=8)return s;usleep(10000); }
 assert(!"download deadline exceeded");return nil;
}
int main(int argc,char **argv) { @autoreleasepool {
 assert(argc==3);root=argv[1];NSString *base=[NSString stringWithUTF8String:argv[2]];
 NSString *dir=[NSString stringWithUTF8String:root],*file=[dir stringByAppendingPathComponent:@"shared_decks/deck.apkg"];
 NSArray *headers=@[@"Cookie",@"session=test",@"User-Agent",@"Anki contract"];
 download_start(1,[base stringByAppendingString:@"/redirect"],file,headers);
 NSArray *s=wait_for(1);assert([s[0] intValue]==8 && [s[2] longLongValue]==1048580);
 NSData *bytes=[NSData dataWithContentsOfFile:file];assert(bytes.length==1048580 && !memcmp(bytes.bytes,"PK\3\4",4));
 assert([NSFileManager.defaultManager contentsOfDirectoryAtPath:file.stringByDeletingLastPathComponent error:NULL].count==1);
 download_start(2,[base stringByAppendingString:@"/rate"],[dir stringByAppendingPathComponent:@"rate.apkg"],headers);
 s=wait_for(2);assert([s[0] intValue]==16 && [s[1] intValue]==429);
 download_start(3,[base stringByAppendingString:@"/deck"],file,headers);
 s=wait_for(3);assert([s[0] intValue]==16);assert([[NSData dataWithContentsOfFile:file] isEqual:bytes]);
 NSString *outside=[dir stringByAppendingString:@"-outside.apkg"];
 download_start(4,[base stringByAppendingString:@"/deck"],outside,headers);
 s=wait_for(4);assert([s[0] intValue]==16 && ![NSFileManager.defaultManager fileExistsAtPath:outside]);
 NSString *slow=[dir stringByAppendingPathComponent:@"cancel.apkg"];
 download_start(5,[base stringByAppendingString:@"/slow"],slow,headers);
 usleep(80000);assert(download_remove(5));assert(!download_remove(5));usleep(150000);
 assert(!download_snapshot(5) && ![NSFileManager.defaultManager fileExistsAtPath:slow]);
 // Cancel after registration while session creation may still be in progress.
 dispatch_group_t group=dispatch_group_create();
 NSString *startup=[dir stringByAppendingPathComponent:@"startup-cancel.apkg"];
 dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{download_start(6,[base stringByAppendingString:@"/slow"],startup,headers);});
 for(int i=0;i<5000 && !download_snapshot(6);i++)usleep(1000);
 assert(download_remove(6));
 assert(dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);usleep(100000);
 assert(!download_snapshot(6) && ![NSFileManager.defaultManager fileExistsAtPath:startup]);
 assert(download_remove(1) && ![NSFileManager.defaultManager fileExistsAtPath:file]);
 printf("actual NSURLSession download/redirect/headers/HTTP429/no-overwrite/sandbox/cancel/remove passed\n");
 return 0;
} }
'''
@unittest.skipUnless(platform.system()=='Darwin','NSURLSession executes on Apple cloud runner')
class DownloadTests(unittest.TestCase):
 def test_actual_streaming_redirect_failure_and_cancellation(self):
  server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Server)
  threading.Thread(target=server.serve_forever,daemon=True).start()
  try:
   with tempfile.TemporaryDirectory() as td:
    p=Path(td);(p/'test.m').write_text(PROGRAM);(p/'data').mkdir()
    c=subprocess.run(['clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror','-I',str(ROOT/'src/translation-layer-next'),str(p/'test.m'),'-framework','Foundation','-o',str(p/'test')],capture_output=True,text=True)
    self.assertEqual(c.returncode,0,c.stdout+c.stderr)
    r=subprocess.run([str(p/'test'),str(p/'data'),f'http://127.0.0.1:{server.server_port}'],capture_output=True,text=True,timeout=40)
    self.assertEqual(r.returncode,0,r.stdout+r.stderr)
  finally:server.shutdown();server.server_close()
if __name__=='__main__':unittest.main(verbosity=2)
