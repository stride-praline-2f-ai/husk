/* SPDX-License-Identifier: GPL-2.0-or-later
 * Offline synthetic GPU regression, never invoked during gameplay.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>

static id<MTLTexture> texture(id<MTLDevice> device,NSUInteger w,NSUInteger h,MTLPixelFormat format){
    auto*d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    return [device newTextureWithDescriptor:d];
}
static void dispatch(id<MTLComputeCommandEncoder> encoder,id<MTLComputePipelineState> pipeline,NSUInteger w,NSUInteger h){
    [encoder setComputePipelineState:pipeline];
    [encoder dispatchThreads:MTLSizeMake(w,h,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
}
int main(int argc,char**argv){@autoreleasepool{
    assert(argc==2);
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if(!device){puts("UNAVAILABLE: runner exposes no Metal GPU");return 77;}
    NSError*error=nil;
    NSString*source=[NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:&error];assert(source);
    MTLCompileOptions*options=[MTLCompileOptions new];options.fastMathEnabled=NO;
    id<MTLLibrary>library=[device newLibraryWithSource:source options:options error:&error];
    if(!library){fprintf(stderr,"%s\n",error.description.UTF8String);return 1;}
    id<MTLFunction>f=[library newFunctionWithName:@"huskFlow"],i=[library newFunctionWithName:@"huskInterpolate"],c=[library newFunctionWithName:@"huskCopyFrame"];
    auto flow=[device newComputePipelineStateWithFunction:f error:&error];
    auto interpolate=[device newComputePipelineStateWithFunction:i error:&error];
    auto copy=[device newComputePipelineStateWithFunction:c error:&error];assert(flow&&interpolate&&copy);
    auto a=texture(device,64,64,MTLPixelFormatRGBA8Unorm),b=texture(device,64,64,MTLPixelFormatRGBA8Unorm);
    auto forward=texture(device,4,4,MTLPixelFormatRGBA16Float),backward=texture(device,4,4,MTLPixelFormatRGBA16Float);
    auto out=texture(device,64,64,MTLPixelFormatRGBA8Unorm);assert(a&&b&&forward&&backward&&out);
    uint8_t pixels[64*64*4];
    auto queue=[device newCommandQueue];
    for(unsigned motion=4;motion<=16;motion+=12){
    for(unsigned shift=0;shift<2;shift++){
        for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
            unsigned offset=(y*64+x)*4;uint8_t value=(uint8_t)((x>=shift*motion?x-shift*motion:0)*4);
            pixels[offset]=pixels[offset+1]=pixels[offset+2]=value;pixels[offset+3]=255;
        }
        [(shift?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
    }
    auto command=[queue commandBuffer];
    for(unsigned reverse=0;reverse<2;reverse++){
        auto e=[command computeCommandEncoder];[e setTexture:reverse?b:a atIndex:0];[e setTexture:reverse?a:b atIndex:1];
        [e setTexture:reverse?backward:forward atIndex:2];dispatch(e,flow,4,4);[e endEncoding];
    }
    auto e=[command computeCommandEncoder];[e setTexture:a atIndex:0];[e setTexture:b atIndex:1];
    [e setTexture:forward atIndex:2];[e setTexture:backward atIndex:3];[e setTexture:out atIndex:4];dispatch(e,interpolate,64,64);[e endEncoding];
    [command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
    __fp16 vectors[4*4*4];[forward getBytes:vectors bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0];
    assert(fabs((float)vectors[(2*4+2)*4]+(float)motion)<0.5f);
    [out getBytes:pixels bytesPerRow:256 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
    unsigned centre=(32*64+32)*4;assert(abs((int)pixels[centre]-(int)((32-motion/2)*4))<=2);
    command=[queue commandBuffer];e=[command computeCommandEncoder];[e setTexture:b atIndex:0];[e setTexture:out atIndex:1];dispatch(e,copy,64,64);[e endEncoding];
    [command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
    [out getBytes:pixels bytesPerRow:256 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];assert(pixels[centre]==(32-motion)*4&&pixels[centre+3]==255);
    }
    // Deliberately confident but locally wrong tile vectors model the missing
    // per-pixel confidence at HUD/depth boundaries. Forward/backward consistency
    // alone passes these cases; the original shader destroys the white glyph
    // or blends two incompatible colours.
    __fp16 controlled[4*4*4];
    for(unsigned reverse=0;reverse<2;reverse++){
        for(unsigned v=0;v<16;v++){
            controlled[v*4]=reverse?8:-8;controlled[v*4+1]=0;
            controlled[v*4+2]=0;controlled[v*4+3]=1;
        }
        [(reverse?backward:forward) replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:controlled bytesPerRow:32];
    }
    auto interpolateOnly=[&]{
        auto command=[queue commandBuffer];auto e=[command computeCommandEncoder];
        [e setTexture:a atIndex:0];[e setTexture:b atIndex:1];[e setTexture:forward atIndex:2];
        [e setTexture:backward atIndex:3];[e setTexture:out atIndex:4];dispatch(e,interpolate,64,64);[e endEncoding];
        [command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
        [out getBytes:pixels bytesPerRow:256 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
    };
    for(unsigned image=0;image<2;image++){
        for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
            unsigned q=(y*64+x)*4;uint8_t bg=((x+image*8)%16)<8?32:80;
            pixels[q]=pixels[q+1]=pixels[q+2]=(x==32||x==33)?255:bg;pixels[q+3]=255;
        }
        [(image?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
    }
    interpolateOnly();unsigned centre=(32*64+32)*4;
    if(pixels[centre]!=255||pixels[centre+1]!=255||pixels[centre+2]!=255){
        fprintf(stderr,"QUALITY_REJECT: stationary HUD changed under background motion\n");return 3;
    }
    for(unsigned scenario=0;scenario<2;scenario++){
        for(unsigned image=0;image<2;image++){
            for(unsigned q=0;q<64*64;q++){
                pixels[q*4]=(image?0:255);
                pixels[q*4+1]=scenario?(image?76:0):(image?0:255);
                pixels[q*4+2]=scenario?0:(image?0:255);pixels[q*4+3]=255;
            }
            [(image?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
        }
        interpolateOnly();
        if(pixels[centre]!=0||pixels[centre+1]!=(scenario?76:0)||pixels[centre+2]!=0){
            fprintf(stderr,"QUALITY_REJECT: inconsistent warped colours were blended\n");return 3;
        }
    }
    for(unsigned image=0;image<2;image++){
        for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
            unsigned q=(y*64+x)*4;uint8_t value=image&&x<2?0:255;
            pixels[q]=pixels[q+1]=pixels[q+2]=value;pixels[q+3]=255;
        }
        [(image?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
    }
    interpolateOnly();unsigned edge=(32*64)*4;
    if(pixels[edge]!=0||pixels[edge+1]!=0||pixels[edge+2]!=0){
        fprintf(stderr,"QUALITY_REJECT: out-of-frame warp stretched the edge\n");return 3;
    }
    puts("PASS: stationary HUD and locally inconsistent/equal-luminance colours preserve the real pixel without ghost blending");
    printf("PASS: real GPU shader compilation, bidirectional translation, intermediate image and real-frame copy on %s\n",device.name.UTF8String);
    [queue release];[a release];[b release];[forward release];[backward release];[out release];
    [flow release];[interpolate release];[copy release];[f release];[i release];[c release];[library release];[options release];[device release];
}return 0;}
