#!/usr/bin/env python3
"""Actual scaler component with deterministic Metal protocol doubles on Apple."""
import subprocess,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
@unittest.skipUnless(sys.platform=='darwin','Apple Objective-C/MetalFX SDK required; IPA CI runs this check')
class SpatialLifetimeTests(unittest.TestCase):
 def test_ownership_preparation_reuse_failure_serialization_and_reconfiguration(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);tl=ROOT/'src/translation-layer-next';inc=ROOT/'patches/metalfx'
   (p/'HuskSpatialABI.h').write_text((tl/'husk-tl-spatial.h').read_text())
   (p/'main.mm').write_text(r'''
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <atomic>
#include <thread>
#include <cassert>
enum{VK_COLOR_SPACE_SRGB_NONLINEAR_KHR=0,VK_FORMAT_B8G8R8A8_UNORM=44,VK_FORMAT_B8G8R8A8_SRGB=50,VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR=1,VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR=1};
struct VkSwapchainCreateInfoKHR{struct{unsigned width,height;}imageExtent;unsigned imageArrayLayers,imageColorSpace,imageFormat,preTransform,compositeAlpha,flags;void*pNext;};
#include "HuskSpatial.inc"
static std::atomic<unsigned> texturesFreed{0},scalersFreed{0},overlaps{0};
@interface TestTexture:NSObject
@property(nonatomic) NSUInteger width,height;
@property(nonatomic) MTLPixelFormat pixelFormat;
@property(nonatomic) MTLTextureUsage usage;
@end
@implementation TestTexture
-(void)dealloc{++texturesFreed;[super dealloc];}
@end
@interface TestScaler:NSObject{std::atomic<unsigned> _active;}
@property(nonatomic) NSUInteger inputWidth,inputHeight,outputWidth,outputHeight;
@property(nonatomic) MTLPixelFormat colorTextureFormat,outputTextureFormat;
@property(nonatomic) MTLTextureUsage colorTextureUsage,outputTextureUsage;
@property(nonatomic) MTLFXSpatialScalerColorProcessingMode colorProcessingMode;
@property(nonatomic,retain) id colorTexture,outputTexture;
@property(nonatomic) NSUInteger inputContentWidth,inputContentHeight;
@property(nonatomic) unsigned inputBindings,contentWrites,outputBindings,encodes;
@end
@implementation TestScaler
@synthesize colorTexture=_colorTexture,outputTexture=_outputTexture,inputContentWidth=_inputContentWidth,inputContentHeight=_inputContentHeight;
-(id)init{self=[super init];if(self)_active.store(0);return self;}
-(void)setColorTexture:(id)value{self.inputBindings++;[value retain];[_colorTexture release];_colorTexture=value;}
-(void)setOutputTexture:(id)value{self.outputBindings++;[value retain];[_outputTexture release];_outputTexture=value;}
-(void)setInputContentWidth:(NSUInteger)value{self.contentWrites++;_inputContentWidth=value;}
-(void)setInputContentHeight:(NSUInteger)value{self.contentWrites++;_inputContentHeight=value;}
-(void)encodeToCommandBuffer:(id)command{
 assert(command&&self.colorTexture&&self.outputTexture&&self.inputContentWidth==1696&&self.inputContentHeight==1280);
 if(_active.fetch_add(1))++overlaps;
 self.encodes++;std::this_thread::yield();_active.fetch_sub(1);
}
-(void)dealloc{[_colorTexture release];[_outputTexture release];++scalersFreed;[super dealloc];}
@end
static TestTexture *texture(unsigned w,unsigned h,MTLTextureUsage usage){auto*t=[TestTexture new];t.width=w;t.height=h;t.pixelFormat=MTLPixelFormatBGRA8Unorm;t.usage=usage;return t;}
static HuskSpatialImage *image(const tl_spatial_config&c){
 auto*state=new HuskSpatialImage();++huskSpatialLive;
 state->input=(id<MTLTexture>)texture(c.input_width,c.input_height,MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget);
 auto*s=[TestScaler new];s.inputWidth=c.input_width;s.inputHeight=c.input_height;s.outputWidth=c.output_width;s.outputHeight=c.output_height;
 s.colorTextureFormat=s.outputTextureFormat=MTLPixelFormatBGRA8Unorm;s.colorTextureUsage=MTLTextureUsageShaderRead;s.outputTextureUsage=MTLTextureUsageShaderWrite;
 state->scaler=(id<MTLFXSpatialScaler>)s;return state;
}
int main(){@autoreleasepool{
 tl_spatial_config c={1,sizeof(c),1696,1280,2128,1600,1,0};huskSpatialConfig=c;
 auto*a=image(c),*b=image(c);assert(huskSpatialLive.load()==2);
 assert(huskSpatialPrepareImage(a,c,MTLPixelFormatBGRA8Unorm));assert(huskSpatialPrepareImage(b,c,MTLPixelFormatBGRA8Unorm));
 auto*scaler=(TestScaler*)a->scaler;assert(scaler.inputBindings==1&&scaler.contentWrites==2);
 auto*out=texture(2128,1600,MTLTextureUsageShaderWrite);id command=[NSObject new];
 unsigned invalid=huskSpatialEncodeFailures.load();
 out.width=2120;assert(!huskSpatialEncode(a,(id<MTLTexture>)out,(id<MTLCommandBuffer>)command));out.width=2128;
 out.pixelFormat=MTLPixelFormatRGBA8Unorm;assert(!huskSpatialEncode(a,(id<MTLTexture>)out,(id<MTLCommandBuffer>)command));out.pixelFormat=MTLPixelFormatBGRA8Unorm;
 out.usage=MTLTextureUsageShaderRead;assert(!huskSpatialEncode(a,(id<MTLTexture>)out,(id<MTLCommandBuffer>)command));out.usage=MTLTextureUsageShaderWrite;
 assert(huskSpatialEncodeFailures.load()==invalid+3&&scaler.encodes==0);
 auto encode=[&]{@autoreleasepool{for(unsigned i=0;i<500;i++)assert(huskSpatialEncode(a,(id<MTLTexture>)out,(id<MTLCommandBuffer>)command));}};
 std::thread first(encode),second(encode);first.join();second.join();
 assert(scaler.encodes==1000&&scaler.inputBindings==1&&scaler.contentWrites==2&&scaler.outputBindings==1&&!overlaps.load());
 tl_spatial_bindings bindings={1,sizeof(bindings)};assert(vkHuskSpatialBindings(&bindings)&&bindings.output_rebinds==1&&bindings.output_contract_checks==4);
 auto*replacement=texture(2128,1600,MTLTextureUsageShaderWrite);assert(huskSpatialEncode(a,(id<MTLTexture>)replacement,(id<MTLCommandBuffer>)command));
 assert(scaler.outputBindings==2&&a->boundOutput==(id<MTLTexture>)replacement);
 assert(huskSpatialEncode(a,(id<MTLTexture>)out,(id<MTLCommandBuffer>)command));assert(scaler.outputBindings==3);[replacement release];
 tl_spatial_observations observations={};observations.version=1;observations.size=sizeof(observations);
 assert(vkHuskSpatialObservations(&observations)&&observations.observed_images==1&&observations.input_width==1696&&observations.output_width==2128);
 tl_spatial_config off={1,sizeof(off),0,0,0,0,0,0};assert(!vkHuskSpatialConfigure(&off));
 huskSpatialDeleteImage(a);assert(huskSpatialLive.load()==1&&texturesFreed.load()==2&&scalersFreed.load()==1);assert(!vkHuskSpatialConfigure(&off));
 auto*input=(TestTexture*)b->input;input.usage=MTLTextureUsageRenderTarget;
 assert(!huskSpatialPrepareImage(b,c,MTLPixelFormatBGRA8Unorm)&&!b->prepared);
 assert(!huskSpatialEncode(b,(id<MTLTexture>)out,(id<MTLCommandBuffer>)command));
 huskSpatialDeleteImage(b);assert(huskSpatialLive.load()==0&&texturesFreed.load()==3&&scalersFreed.load()==2);
 assert(vkHuskSpatialConfigure(&off));assert(vkHuskSpatialObservations(&observations)&&observations.observed_images==0);
 unsigned resources=huskSpatialResources.load();assert(!huskSpatialNewImage(nil,MTLPixelFormatBGRA8Unorm,MTLTextureUsageRenderTarget,c));
 assert(huskSpatialResources.load()==resources+1&&!huskSpatialLive.load());
 [out release];[command release];assert(texturesFreed.load()==4);return 0;
}}
''')
   binary=p/'check';subprocess.run(['clang++','-std=c++17','-fno-objc-arc','-fblocks','-I',str(p),'-I',str(inc),str(p/'main.mm'),'-framework','Foundation','-framework','Metal','-framework','MetalFX','-o',str(binary)],check=True);subprocess.run([str(binary)],check=True)

 def test_framegen_offscreen_lease_retirement_callback_once_and_pool_reuse(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);tl=ROOT/'src/translation-layer-next'
   (p/'HuskFramegenABI.h').write_text((tl/'husk-tl-framegen.h').read_text())
   (p/'HuskFramegenShader.inc').write_text('static const char* huskFramegenShader="";')
   # Only platform/headroom/unused iOS clock-factory facades differ; execute the actual drawable,
   # completion and bounded pool implementation without allocating a GPU.
   code=(ROOT/'patches/metalfx/HuskFramegen.inc').read_text().replace('#if TARGET_OS_IOS','#if 1').replace('#include <os/proc.h>','static uint64_t os_proc_available_memory(){return 1ULL<<30;}').replace('[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)]','((CADisplayLink*)nil)')
   (p/'HuskFramegen.inc').write_text(code)
   (p/'lease.mm').write_text(r"""
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <atomic>
#include <cassert>
#include <mutex>
#include "HuskFramegen.inc"
int main(){@autoreleasepool{
 auto*p=[HuskFGPresenter new];HuskFGDrawable* frames[4];
 for(unsigned i=0;i<4;i++){@autoreleasepool{frames[i]=[(HuskFGDrawable*)huskFramegenDrawable(p,nil) retain];assert(frames[i]&&p->_used[i]);}}
 assert(!huskFramegenDrawable(p,nil));
 __block unsigned callbacks=0;HuskFGDrawable*first=frames[0];
 [frames[0] addPresentedHandler:^(id<MTLDrawable> d){callbacks++;assert(d.presentedTime==2);[first finish:9];}];
 [frames[0] finish:2];[frames[0] finish:3];assert(callbacks==1&&frames[0].presentedTime==2);
 [frames[0] addPresentedHandler:^(id<MTLDrawable> d){callbacks++;assert(d.presentedTime==2);}];assert(callbacks==2);
 auto held=[frames[0] retain];[frames[0] release];assert(p->_used[0]);[held release];assert(!p->_used[0]);
 @autoreleasepool{auto* replacement=(HuskFGDrawable*)huskFramegenDrawable(p,nil);assert(replacement&&replacement->_slot==0);}
 assert(!p->_used[0]);
 for(unsigned i=1;i<4;i++)[frames[i] release];
 p->_paused=true;@autoreleasepool{assert(huskFramegenDrawable(p,nil));}p->_paused=false;p->_stopped=true;assert(!huskFramegenDrawable(p,nil));
 [p release];
 tl_fg_config c={1,sizeof(c),1,1816,1280,0};assert(vkHuskFramegenConfigure(&c));
 assert(fgStorageBytes(1816,1280)<(96ULL<<20));
 assert(fgStorageBytes(2128,1600)<(96ULL<<20));
 assert(fgStorageBytes(2128,1600)>uint64_t(2128)*1600*16);
 c.width=c.height=2048;assert(fgStorageBytes(2048,2048)>(96ULL<<20)&&!vkHuskFramegenConfigure(&c));
 c.width=c.height=4096;assert(!vkHuskFramegenConfigure(&c));c.enabled=0;assert(vkHuskFramegenConfigure(&c));
 tl_fg_stats stats={1,sizeof(stats)};assert(vkHuskFramegenSnapshot(&stats)&&!stats.active&&!stats.failed);
}return 0;}
""")
   subprocess.run(['clang++','-std=c++17','-fblocks','-fno-objc-arc','-Wno-deprecated-declarations','-framework','Foundation','-framework','Metal','-framework','QuartzCore','-I',str(p),str(p/'lease.mm'),'-o',str(p/'lease')],check=True)
   subprocess.run([str(p/'lease')],check=True,timeout=10)


 def test_real_optical_flow_shader_compiles_and_interpolates_on_available_host_gpu(self):
  with tempfile.TemporaryDirectory() as d:
   exe=Path(d)/'gpu'
   subprocess.run(['clang++','-std=c++17','-fno-objc-arc','-framework','Foundation','-framework','Metal',str(ROOT/'tests/translation-layer/framegen_gpu.mm'),'-o',str(exe)],check=True)
   result=subprocess.run([str(exe),str(ROOT/'patches/metalfx/HuskFramegen.metal')],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
   print(result.stdout)
   if result.returncode==77:self.skipTest('runner exposes no Metal GPU; shader execution unavailable')
   self.assertEqual(result.returncode,0,result.stdout)
   # The same real GPU quality cases must reject the frozen166 shader. This
   # demonstrates the concrete former HUD blend defect, not just a new shader
   # passing expectations written only around its own implementation.
   old=subprocess.run([str(exe),str(ROOT/'tests/translation-layer/fixtures/framegen-166.metal')],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
   self.assertEqual(old.returncode,3,old.stdout)
   self.assertIn('QUALITY_REJECT: stationary HUD changed',old.stdout)
   print('PASS: frozen166 shader rejected for stationary HUD ghosting; repaired shader passes the same GPU cases')
   prior=subprocess.run([str(exe),str(ROOT/'tests/translation-layer/fixtures/framegen-167.metal')],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
   self.assertEqual(prior.returncode,4,prior.stdout)
   self.assertIn('QUALITY_REJECT: intermediate textured sequence jumps to real-frame phase',prior.stdout)
   print(prior.stdout)
   print('PASS: frozen167 rejected for mixed motion phases; current shader passes whole generated/real sequences and fractional motion')
   unfiltered=subprocess.run([str(exe),str(ROOT/'tests/translation-layer/fixtures/framegen-168-pre-pyramid.metal')],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
   self.assertEqual(unfiltered.returncode,4,unfiltered.stdout)
   self.assertRegex(unfiltered.stdout,r'QUALITY_REJECT: (textured motion was not recovered|estimated textured flow did not preserve)')
   print(unfiltered.stdout)
   print('PASS: pre-pyramid candidate rejected by actual textured flow; filtered production search passes')

if __name__=='__main__':unittest.main()
