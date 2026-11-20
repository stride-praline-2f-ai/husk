/* SPDX-License-Identifier: GPL-2.0-or-later
 * Native Metal 3 MetalFX frame-interpolator adapter, separate from old
 * HuskFramegen's colour-only flow and from Metal 4/KosmicKrisp.
 *
 * Not connected to the Vulkan swapchain. A future engine render-target bridge
 * must supply colour BEFORE HUD, previous colour, real per-pixel motion/depth,
 * correct camera parameters and an ordered Metal command buffer. Never enable
 * this adapter by inferring depth or motion from the final drawable.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#import "HuskNativeMetalFX.h"
#include <math.h>

@interface HuskNativeFXState : NSObject {
@public
    id<MTLDevice> device;
    id<MTLFXFrameInterpolator> interpolator;
    husk_metalfx_config contract;
}
@end
@implementation HuskNativeFXState
- (void)dealloc {
#if !__has_feature(objc_arc)
    [interpolator release];
    [device release];
    [super dealloc];
#endif
}
@end

bool husk_native_metalfx_supported(void) {
    if (@available(iOS 18.0, *)) {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        return device != nil && [MTLFXFrameInterpolatorDescriptor supportsDevice:device];
    }
    return false;
}

void *husk_native_metalfx_create(void *raw_device, const husk_metalfx_config *c) {
    if (!c || c->abi != 1 || c->size != sizeof(*c) ||
        c->width < 64 || c->height < 64 ||
        c->width > 4096 || c->height > 4096 ||
        !c->color_format || !c->depth_format || !c->motion_format || !c->output_format)
        return NULL;
    if (@available(iOS 18.0, *)) {
        id<MTLDevice> metalDevice = (__bridge id<MTLDevice>)raw_device;
        if (!metalDevice || ![MTLFXFrameInterpolatorDescriptor supportsDevice:metalDevice])
            return NULL;
        MTLFXFrameInterpolatorDescriptor *desc = [MTLFXFrameInterpolatorDescriptor new];
        desc.inputWidth = c->width;
        desc.inputHeight = c->height;
        desc.outputWidth = c->width;
        desc.outputHeight = c->height;
        desc.colorTextureFormat = (MTLPixelFormat)c->color_format;
        desc.depthTextureFormat = (MTLPixelFormat)c->depth_format;
        desc.motionTextureFormat = (MTLPixelFormat)c->motion_format;
        desc.outputTextureFormat = (MTLPixelFormat)c->output_format;
        id<MTLFXFrameInterpolator> fx = [desc newFrameInterpolatorWithDevice:metalDevice];
#if !__has_feature(objc_arc)
        [desc release];
#endif
        if (!fx) return NULL;
        HuskNativeFXState *s = [HuskNativeFXState new];
#if __has_feature(objc_arc)
        s->device = metalDevice;
        s->interpolator = fx;
#else
        s->device = [metalDevice retain];
        s->interpolator = fx;
#endif
        s->contract = *c;
#if __has_feature(objc_arc)
        return (__bridge_retained void *)s;
#else
        return s;
#endif
    }
    return NULL;
}

bool husk_native_metalfx_encode(void *opaque, void *raw_buffer,
                                const husk_metalfx_inputs *i) {
    if (!opaque || !raw_buffer || !i || i->abi != 1 || i->size != sizeof(*i) ||
        !i->previous_color || !i->current_color || !i->depth || !i->motion || !i->output ||
        !isfinite(i->delta_seconds) || i->delta_seconds <= 0.0f ||
        !isfinite(i->motion_scale_x) || !isfinite(i->motion_scale_y) ||
        !isfinite(i->field_of_view) || i->field_of_view <= 0.0f ||
        !isfinite(i->near_plane) || !isfinite(i->far_plane) ||
        !isfinite(i->aspect_ratio) || i->aspect_ratio <= 0.0f)
        return false;
    if (@available(iOS 18.0, *)) {
        HuskNativeFXState *s = (__bridge HuskNativeFXState *)opaque;
        id<MTLTexture> previous = (__bridge id<MTLTexture>)i->previous_color;
        id<MTLTexture> current = (__bridge id<MTLTexture>)i->current_color;
        id<MTLTexture> depth = (__bridge id<MTLTexture>)i->depth;
        id<MTLTexture> motion = (__bridge id<MTLTexture>)i->motion;
        id<MTLTexture> output = (__bridge id<MTLTexture>)i->output;
        id<MTLCommandBuffer> buffer = (__bridge id<MTLCommandBuffer>)raw_buffer;
        if (previous.device != s->device || current.device != s->device ||
            depth.device != s->device || motion.device != s->device ||
            output.device != s->device)
            return false;
        if (previous.width != s->contract.width || previous.height != s->contract.height ||
            current.width != s->contract.width || current.height != s->contract.height ||
            output.width != s->contract.width || output.height != s->contract.height ||
            depth.width != s->contract.width || depth.height != s->contract.height ||
            motion.width != s->contract.width || motion.height != s->contract.height ||
            previous.pixelFormat != (MTLPixelFormat)s->contract.color_format ||
            current.pixelFormat != (MTLPixelFormat)s->contract.color_format ||
            depth.pixelFormat != (MTLPixelFormat)s->contract.depth_format ||
            motion.pixelFormat != (MTLPixelFormat)s->contract.motion_format ||
            output.pixelFormat != (MTLPixelFormat)s->contract.output_format)
            return false;
        // The caller is responsible for GPU dependency ordering, camera cuts,
        // UI composition and presenting generated then real images on time.
        id<MTLFXFrameInterpolator> fx = s->interpolator;
        fx.contentWidth = s->contract.width;
        fx.contentHeight = s->contract.height;
        fx.prevColorTexture = previous;
        fx.colorTexture = current;
        fx.depthTexture = depth;
        fx.motionTexture = motion;
        fx.outputTexture = output;
        fx.motionVectorScaleX = i->motion_scale_x;
        fx.motionVectorScaleY = i->motion_scale_y;
        fx.deltaTime = i->delta_seconds;
        fx.fieldOfView = i->field_of_view;
        fx.nearPlane = i->near_plane;
        fx.farPlane = i->far_plane;
        fx.aspectRatio = i->aspect_ratio;
        fx.depthReversed = i->depth_reversed;
        fx.shouldResetHistory = i->reset_history;
        [fx encodeToCommandBuffer:buffer];
        return true;
    }
    return false;
}

void husk_native_metalfx_destroy(void *opaque) {
    if (!opaque) return;
#if __has_feature(objc_arc)
    CFBridgingRelease(opaque);
#else
    [(HuskNativeFXState *)opaque release];
#endif
}
