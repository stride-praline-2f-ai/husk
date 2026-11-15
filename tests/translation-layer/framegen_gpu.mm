/* SPDX-License-Identifier: GPL-2.0-or-later
 * Offline synthetic GPU regression, never invoked during gameplay.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <algorithm>
#include <initializer_list>
#include <vector>
#include <array>

static id<MTLTexture> texture(id<MTLDevice> device,NSUInteger w,NSUInteger h,MTLPixelFormat format,bool mips=false){
    auto*d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:mips];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    return [device newTextureWithDescriptor:d];
}
static void dispatch(id<MTLComputeCommandEncoder> encoder,id<MTLComputePipelineState> pipeline,NSUInteger w,NSUInteger h){
    [encoder setComputePipelineState:pipeline];
    [encoder dispatchThreads:MTLSizeMake(w,h,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
}
static void motionPass(id<MTLCommandBuffer> command,id<MTLTexture> previous,id<MTLTexture> current,id<MTLTexture> output,
                       id<MTLComputePipelineState> flow,id<MTLComputePipelineState> coarsePSO,id<MTLComputePipelineState> regularizePSO){
    id<MTLTexture> raw=output,coarse=nil;
    if(coarsePSO){
        coarse=texture(previous.device,(previous.width+63)/64,(previous.height+63)/64,MTLPixelFormatRGBA16Float);
        raw=texture(previous.device,output.width,output.height,MTLPixelFormatRGBA16Float);
        auto e=[command computeCommandEncoder];[e setTexture:previous atIndex:0];[e setTexture:current atIndex:1];[e setTexture:coarse atIndex:2];dispatch(e,coarsePSO,coarse.width,coarse.height);[e endEncoding];
    }
    auto e=[command computeCommandEncoder];[e setTexture:previous atIndex:0];[e setTexture:current atIndex:1];[e setTexture:raw atIndex:2];if(coarse)[e setTexture:coarse atIndex:3];dispatch(e,flow,raw.width,raw.height);[e endEncoding];
    if(coarse){
        e=[command computeCommandEncoder];[e setTexture:previous atIndex:0];[e setTexture:current atIndex:1];[e setTexture:raw atIndex:2];[e setTexture:output atIndex:3];dispatch(e,regularizePSO,output.width,output.height);[e endEncoding];
        [raw release];[coarse release];
    }
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
    auto a=texture(device,64,64,MTLPixelFormatRGBA8Unorm,true),b=texture(device,64,64,MTLPixelFormatRGBA8Unorm,true);
    auto forward=texture(device,4,4,MTLPixelFormatRGBA16Float),backward=texture(device,4,4,MTLPixelFormatRGBA16Float);
    auto out=texture(device,64,64,MTLPixelFormatRGBA8Unorm);assert(a&&b&&forward&&backward&&out);
    auto quality=texture(device,1,1,MTLPixelFormatRGBA32Float);
    float allow[4]={1,0,0,1};[quality replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:allow bytesPerRow:16];
    id<MTLFunction> cf=[library newFunctionWithName:@"huskCoarseFlow"],rf=[library newFunctionWithName:@"huskRegularizeFlow"],qf=[library newFunctionWithName:@"huskFlowQuality"];
    id<MTLComputePipelineState> coarsePSO=cf?[device newComputePipelineStateWithFunction:cf error:&error]:nil;
    id<MTLComputePipelineState> regularizePSO=rf?[device newComputePipelineStateWithFunction:rf error:&error]:nil;
    id<MTLComputePipelineState> qualityPSO=qf?[device newComputePipelineStateWithFunction:qf error:&error]:nil;
    if(cf||rf||qf)assert(coarsePSO&&regularizePSO&&qualityPSO);
    [cf release];[rf release];[qf release];
    uint8_t pixels[64*64*4];
    auto queue=[device newCommandQueue];
    auto prepareMotion=[&](id<MTLCommandBuffer> command){auto blit=[command blitCommandEncoder];[blit generateMipmapsForTexture:a];[blit generateMipmapsForTexture:b];[blit endEncoding];};
    for(unsigned motion=4;motion<=16;motion+=12){
    for(unsigned shift=0;shift<2;shift++){
        for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
            unsigned offset=(y*64+x)*4;uint8_t value=(uint8_t)((x>=shift*motion?x-shift*motion:0)*4);
            pixels[offset]=pixels[offset+1]=pixels[offset+2]=value;pixels[offset+3]=255;
        }
        [(shift?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
    }
    auto command=[queue commandBuffer];
    prepareMotion(command);
    for(unsigned reverse=0;reverse<2;reverse++){
        motionPass(command,reverse?b:a,reverse?a:b,reverse?backward:forward,flow,coarsePSO,regularizePSO);
    }
    auto e=[command computeCommandEncoder];[e setTexture:a atIndex:0];[e setTexture:b atIndex:1];
    [e setTexture:forward atIndex:2];[e setTexture:backward atIndex:3];[e setTexture:out atIndex:4];[e setTexture:quality atIndex:5];dispatch(e,interpolate,64,64);[e endEncoding];
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
        [e setTexture:backward atIndex:3];[e setTexture:out atIndex:4];[e setTexture:quality atIndex:5];dispatch(e,interpolate,64,64);[e endEncoding];
        [command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
        [out getBytes:pixels bytesPerRow:256 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
    };
    // Unchanged background at the midpoint is not a static HUD. A thin
    // moving object must still appear between its two disjoint real positions.
    for(unsigned image=0;image<2;image++){
        for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
            unsigned q=(y*64+x)*4;unsigned origin=20+image*8;
            pixels[q]=pixels[q+1]=pixels[q+2]=(x>=origin&&x<origin+2)?255:0;pixels[q+3]=255;
        }
        [(image?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
    }
    interpolateOnly();
    if(pixels[(32*64+24)*4]!=255||pixels[(32*64+25)*4]!=255||pixels[(32*64+28)*4]!=0){
        fprintf(stderr,"QUALITY_REJECT: true moving thin object lost its intermediate position\n");return 3;
    }
    for(unsigned image=0;image<2;image++){
        for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
            unsigned q=(y*64+x)*4;uint8_t bg=(uint8_t)(32+x-image*8);
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
    // Whole generated/real sequences over textured motion. Some materials
    // change illumination while others do not. Geometry still shares ONE
    // intermediate phase.167's per-pixel RGB gate incorrectly splices phases.
    uint8_t currentPixels[64*64*4];
    for(unsigned pair=0;pair<4;pair++){
        for(unsigned image=0;image<2;image++){
            unsigned phase=pair+image;
            for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
                int world=(int)x-(int)phase*4;
                unsigned q=(y*64+x)*4;
                unsigned seed=(unsigned)(world+128)*1973u+y*9277u;
                seed=(seed^(seed>>7))*26699u;
                unsigned material=((unsigned)(world+128)/7+y/5)%3;
                unsigned lighting=material?phase*13:0;
                for(unsigned channel=0;channel<3;channel++){
                    unsigned detail=(seed>>(channel*5))&63;
                    unsigned brick=(((world+128)/8+(y/6)%2)%2)*28;
                    pixels[q+channel]=(uint8_t)(25+detail+brick+lighting);
                }
                pixels[q+3]=255;
            }
            [(image?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
            if(image)memcpy(currentPixels,pixels,sizeof pixels);
        }
        for(unsigned reverse=0;reverse<2;reverse++){
            for(unsigned v=0;v<16;v++){
                controlled[v*4]=reverse?4:-4;controlled[v*4+1]=0;
                controlled[v*4+2]=0;controlled[v*4+3]=1;
            }
            [(reverse?backward:forward) replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:controlled bytesPerRow:32];
        }
        interpolateOnly();unsigned worst=0;double sum=0;unsigned count=0;
        for(unsigned y=8;y<56;y++)for(unsigned x=8;x<54;x++)for(unsigned channel=0;channel<3;channel++){
            // Four real pixels of translation means two at the midpoint;
            // retain the current source's exposure, not mixed exposures.
            unsigned error=(unsigned)abs((int)pixels[(y*64+x)*4+channel]-(int)currentPixels[(y*64+x+2)*4+channel]);
            worst=std::max(worst,error);sum+=error;count++;
        }
        if(worst>1||sum/count>0.1){
            fprintf(stderr,"QUALITY_REJECT: intermediate textured sequence jumps to real-frame phase (pair %u max %u mean %.3f)\n",pair,worst,sum/count);return 4;
        }
        // Do not hide instability by blurring/resampling every real frame.
        auto command=[queue commandBuffer];auto e=[command computeCommandEncoder];
        [e setTexture:b atIndex:0];[e setTexture:out atIndex:1];dispatch(e,copy,64,64);[e endEncoding];
        [command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
        [out getBytes:pixels bytesPerRow:256 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
        assert(!memcmp(pixels,currentPixels,sizeof pixels));
    }
    // End-to-end textured flow, not only an injected perfect field. A
    // four-pixel move must be found at the filtered coarse scale and refined.
    for(unsigned image=0;image<2;image++){
        for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
            unsigned world=x+128-image*4,q=(y*64+x)*4;
            unsigned seed=(world*1973u+y*9277u);seed=(seed^(seed>>7))*26699u;
            for(unsigned ch=0;ch<3;ch++)pixels[q+ch]=(uint8_t)(30+((seed>>(ch*5))&127));
            pixels[q+3]=255;
        }
        [(image?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
        if(image)memcpy(currentPixels,pixels,sizeof pixels);
    }
    {
        auto command=[queue commandBuffer];prepareMotion(command);
        for(unsigned reverse=0;reverse<2;reverse++){
            motionPass(command,reverse?b:a,reverse?a:b,reverse?backward:forward,flow,coarsePSO,regularizePSO);
        }
        auto e=[command computeCommandEncoder];[e setTexture:a atIndex:0];[e setTexture:b atIndex:1];[e setTexture:forward atIndex:2];
        [e setTexture:backward atIndex:3];[e setTexture:out atIndex:4];[e setTexture:quality atIndex:5];dispatch(e,interpolate,64,64);[e endEncoding];
        [command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
        [out getBytes:pixels bytesPerRow:256 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
        __fp16 vectors[64];[forward getBytes:vectors bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0];
        for(unsigned y=1;y<3;y++)for(unsigned x=1;x<3;x++){
            if(fabs((float)vectors[(y*4+x)*4]+4)>0.01f||fabs((float)vectors[(y*4+x)*4+1])>0.01f){
                fprintf(stderr,"QUALITY_REJECT: textured motion was not recovered by actual flow\n");return 4;
            }
        }
        for(unsigned y=24;y<38;y++)for(unsigned x=30;x<38;x++)for(unsigned ch=0;ch<3;ch++){
            if(abs((int)pixels[(y*64+x)*4+ch]-(int)currentPixels[(y*64+x+2)*4+ch])>1){
                fprintf(stderr,"QUALITY_REJECT: estimated textured flow did not preserve intermediate phase\n");return 4;
            }
        }
    }
    // Odd/fractional translations on a known band-limited linear signal.
    for(float motion:{3.0f,3.5f}){
        for(unsigned image=0;image<2;image++){
            for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
                unsigned q=(y*64+x)*4;
                uint8_t value=(uint8_t)std::max(0.0f,((float)x-image*motion)*4);
                pixels[q]=pixels[q+1]=pixels[q+2]=value;pixels[q+3]=255;
            }
            [(image?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
        }
        auto command=[queue commandBuffer];
        prepareMotion(command);
        for(unsigned reverse=0;reverse<2;reverse++){
            motionPass(command,reverse?b:a,reverse?a:b,reverse?backward:forward,flow,coarsePSO,regularizePSO);
        }
        auto e=[command computeCommandEncoder];[e setTexture:a atIndex:0];[e setTexture:b atIndex:1];[e setTexture:forward atIndex:2];
        [e setTexture:backward atIndex:3];[e setTexture:out atIndex:4];[e setTexture:quality atIndex:5];dispatch(e,interpolate,64,64);[e endEncoding];
        [command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
        __fp16 vectors[64];[forward getBytes:vectors bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0];
        [out getBytes:pixels bytesPerRow:256 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
        if(fabs((float)vectors[(2*4+2)*4]+motion)>0.26f||fabs(pixels[(32*64+32)*4]-(32-motion/2)*4)>2){
            fprintf(stderr,"QUALITY_REJECT: fractional translation not reconstructed (%.1f pixels)\n",motion);return 4;
        }
    }
    // Confidence rejection remains active for unreliable motion fields.
    for(unsigned v=0;v<16;v++){controlled[v*4]=-4;controlled[v*4+1]=0;controlled[v*4+2]=0.2;controlled[v*4+3]=1;}
    [forward replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:controlled bytesPerRow:32];
    [b getBytes:currentPixels bytesPerRow:256 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
    interpolateOnly();assert(!memcmp(pixels,currentPixels,sizeof pixels));
    puts("PASS: textured generated/real sequence has one motion phase; real frames exact; odd/fractional flow and unreliable-field fallback verified");
    // Continuous two-axis camera motion over several texture frequencies.
    //168's independently rounded half-pixel vectors cannot represent this
    // smooth pan, even though the character may remain almost stationary.
    const float cameraX=4.25f,cameraY=2.25f;
    for(unsigned image=0;image<2;image++){
        for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){
            float u=x-image*cameraX,v=y-image*cameraY;unsigned q=(y*64+x)*4;
            pixels[q]=(uint8_t)lround(110+36*sin(0.31*u+0.11*v)+17*cos(0.13*u-0.27*v));
            pixels[q+1]=(uint8_t)lround(100+28*sin(0.17*u-0.23*v)+21*cos(0.37*u+0.19*v));
            pixels[q+2]=(uint8_t)lround(120+30*sin(0.11*u+0.29*v)+19*cos(0.23*u-0.17*v));pixels[q+3]=255;
        }
        [(image?b:a) replaceRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0 withBytes:pixels bytesPerRow:256];
    }
    {
        auto command=[queue commandBuffer];prepareMotion(command);
        for(unsigned reverse=0;reverse<2;reverse++){
            motionPass(command,reverse?b:a,reverse?a:b,reverse?backward:forward,flow,coarsePSO,regularizePSO);
        }
        [command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
        __fp16 vectors[64];[forward getBytes:vectors bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0];
        for(unsigned y=1;y<3;y++)for(unsigned x=1;x<3;x++){
            float dx=(float)vectors[(y*4+x)*4]+cameraX,dy=(float)vectors[(y*4+x)*4+1]+cameraY;
            if(hypot(dx,dy)>0.18){fprintf(stderr,"QUALITY_REJECT: camera pan quantized between independent tiles (error %.4f)\n",hypot(dx,dy));return 5;}
        }
    }
    puts("PASS: continuous two-axis textured camera pan is refined beyond half-pixel tile quantization");
    // A coherent minority among inconsistent tiles must never produce a
    // patchwork intermediate.169 admits scattered pixels from the minority.
    for(unsigned v=0;v<16;v++){
        bool valid=v%4<2;controlled[v*4]=valid?-4:20;controlled[v*4+1]=valid?0:20;controlled[v*4+2]=0;controlled[v*4+3]=1;
    }
    [forward replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:controlled bytesPerRow:32];
    for(unsigned v=0;v<16;v++){controlled[v*4]=v%4<2?4:20;controlled[v*4+1]=v%4<2?0:20;}
    [backward replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:controlled bytesPerRow:32];
    if(qualityPSO){auto command=[queue commandBuffer];auto e=[command computeCommandEncoder];[e setComputePipelineState:qualityPSO];[e setTexture:forward atIndex:0];[e setTexture:backward atIndex:1];[e setTexture:quality atIndex:2];unsigned extent[2]={64,64};[e setBytes:extent length:sizeof extent atIndex:0];[e dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(256,1,1)];[e endEncoding];[command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);}
    [b getBytes:currentPixels bytesPerRow:256 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];interpolateOnly();
    if(memcmp(pixels,currentPixels,sizeof pixels)){fprintf(stderr,"QUALITY_REJECT: incoherent field produced patchwork intermediate\n");return 6;}
    puts("PASS: poor field uses an exact whole-frame real fallback instead of scattered phase patches");
    if(qualityPSO){
        [quality getBytes:allow bytesPerRow:16 fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];assert(allow[0]<0.8f&&allow[3]==0);
    }
    if(qualityPSO){
        // The quality guard must still admit genuine interpolation.
        for(unsigned v=0;v<16;v++){controlled[v*4]=-4;controlled[v*4+1]=0;controlled[v*4+2]=0;controlled[v*4+3]=1;}
        [forward replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:controlled bytesPerRow:32];
        for(unsigned v=0;v<16;v++)controlled[v*4]=4;
        [backward replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:controlled bytesPerRow:32];
        auto command=[queue commandBuffer];auto e=[command computeCommandEncoder];[e setComputePipelineState:qualityPSO];[e setTexture:forward atIndex:0];[e setTexture:backward atIndex:1];[e setTexture:quality atIndex:2];unsigned extent[2]={64,64};[e setBytes:extent length:sizeof extent atIndex:0];[e dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(256,1,1)];[e endEncoding];[command commit];[command waitUntilCompleted];
        [quality getBytes:allow bytesPerRow:16 fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];assert(allow[0]>=.8f&&allow[3]==1);
        interpolateOnly();assert(memcmp(pixels,currentPixels,sizeof pixels));
        puts("PASS: coherent field still produces a genuine intermediate; guard is not a blanket duplicate-frame mode");
    }
    // Repeated scenery, affine camera flow, temporal contamination/noise.
    // This exercises multiple64px cells rather than a single clean translation.
    {
        const unsigned W=512,H=384,FW=W/16,FH=H/16;
        auto previous=texture(device,W,H,MTLPixelFormatRGBA8Unorm,true),current=texture(device,W,H,MTLPixelFormatRGBA8Unorm,true);
        auto result=texture(device,FW,FH,MTLPixelFormatRGBA16Float);
        std::vector<uint8_t> scenePixels(W*H*4);
        auto colour=[](float x,float y){return std::array<float,3>{105+32*sinf(.021f*x+.033f*y)+18*sinf(.91f*x+.23f*y)+9*cosf(.51f*x-.77f*y),110+29*cosf(.019f*x-.027f*y)+16*sinf(.71f*x-.43f*y)+11*cosf(.37f*x+.67f*y),100+33*sinf(.023f*x-.025f*y)+17*cosf(.83f*x+.29f*y)+10*sinf(.47f*x-.63f*y)};};
        for(unsigned image=0;image<2;image++){
            for(unsigned y=0;y<H;y++)for(unsigned x=0;x<W;x++){
                auto original=colour(x,y),moved=colour(x+2.25f+.006f*y,y+7.25f+.012f*x);
                for(unsigned c=0;c<3;c++){float value=image?.9f*moved[c]+.1f*original[c]+2*sinf(1.3f*x+.7f*y):original[c];scenePixels[(y*W+x)*4+c]=(uint8_t)std::clamp(lroundf(value),0L,255L);}
                scenePixels[(y*W+x)*4+3]=255;
            }
            [(image?current:previous) replaceRegion:MTLRegionMake2D(0,0,W,H) mipmapLevel:0 withBytes:scenePixels.data() bytesPerRow:W*4];
        }
        auto command=[queue commandBuffer];auto blit=[command blitCommandEncoder];[blit generateMipmapsForTexture:previous];[blit generateMipmapsForTexture:current];[blit endEncoding];
        motionPass(command,previous,current,result,flow,coarsePSO,regularizePSO);[command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
        std::vector<__fp16> vectors(FW*FH*4);[result getBytes:vectors.data() bytesPerRow:FW*8 fromRegion:MTLRegionMake2D(0,0,FW,FH) mipmapLevel:0];std::vector<float> errors;
        for(unsigned y=2;y<FH-2;y++)for(unsigned x=2;x<FW-2;x++){float px=(x+.5f)*16,py=(y+.5f)*16,dx=(float)vectors[(y*FW+x)*4]-(2.25f+.006f*py),dy=(float)vectors[(y*FW+x)*4+1]-(7.25f+.012f*px);errors.push_back(hypotf(dx,dy));}
        std::sort(errors.begin(),errors.end());float p50=errors[errors.size()/2],p90=errors[errors.size()*9/10];
        if(p50>.8f||p90>1.5f){fprintf(stderr,"QUALITY_REJECT: repeated scenery camera flow inaccurate (p50 %.4f p90 %.4f pixels)\n",p50,p90);return 7;}
        printf("PASS: multi-cell repeated scenery with affine camera motion and temporal noise (p50 %.4f p90 %.4f pixels)\n",p50,p90);
        [previous release];[current release];[result release];
    }
    printf("PASS: real GPU shader compilation, bidirectional translation, intermediate image and real-frame copy on %s\n",device.name.UTF8String);
    [queue release];[a release];[b release];[forward release];[backward release];[out release];
    [coarsePSO release];[regularizePSO release];[qualityPSO release];[quality release];
    [flow release];[interpolate release];[copy release];[f release];[i release];[c release];[library release];[options release];[device release];
}return 0;}
