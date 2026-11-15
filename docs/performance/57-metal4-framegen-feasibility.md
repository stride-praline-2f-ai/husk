# M9-FG-METAL4-v1 — concrete route, not an enabled feature

15November2026. User asks whether frame generation can work with the now-active nativeMetal4 renderer. **Yes, a port is feasible; the shipped driver does not expose the current Husk framegen bridge, and this cache-repair candidate does not enable it.** Renderer exclusivity stays until correct GPU ownership/presentation interop is implemented and validated.

## Verified interfaces at the actual pins

Playport26620bf5319a0f5a5cca47cfecec797cafe45493, Mesa b39d173ca9369c19fda2635be6655d308067e52d; existing shipped KosmicKrisp binary SHA17bba1df31d4c8eb757ce2f56fdc1f8c6af92bc5427585e33673b0c60e8ba7de.

- Mesa `src/kosmickrisp/vulkan/kk_physical_device.c` at this pin advertises **VK_EXT_external_memory_metal**. That supplies a possible public import/export route for owned compatible Metal-backed allocations; it does not imply arbitrary live swapchain images can safely be consumed or that VK_EXT_metal_objects is advertised. Mere entrypoint strings are not feature admission.
- Playport patch0035 (`kk-hang-a-drawable-s-readable-source-on-its-texture`) retains the ordinary readable blit source on a framebuffer-only drawable's texture under `@selector(playportReadableSource)`. The shipped binary contains that selector. The patch explicitly says its paused-game screenshot use is safe because the application is not re-rendering into that image. This is not a live frame lease or a completion/retirement API.
- WSI Metal sources and patches0009/0010/0083 implement nativeMetal4 queue residency, acquire/present callbacks and swapchain ownership. They are the concrete places to add producer completion/lease/presentation hooks if public interop is insufficient.
- Shipped driver does **not** contain/export `vkHuskFramegenConfigure`. The current framegen ABI exists in the separate custom MoltenVK, where source completion and drawable lease lifetimes are already integrated.
- NX18/Henge shared-event bridges demonstrate the relevant producer/consumer synchronization pattern; their NVN/PVG command frontend cannot simply be copied into the Vulkan swapchain path.

References: [Playport pin](https://github.com/playportdev/playport/tree/26620bf5319a0f5a5cca47cfecec797cafe45493), [Mesa physical-device source at pin](https://github.com/chaotic-cx/mesa-mirror/blob/b39d173ca9369c19fda2635be6655d308067e52d/src/kosmickrisp/vulkan/kk_physical_device.c), [Metal WSI source at pin](https://github.com/chaotic-cx/mesa-mirror/blob/b39d173ca9369c19fda2635be6655d308067e52d/src/vulkan/wsi/wsi_common_metal_layer.m).

## Two implementable routes

1. **Public Vulkan/Metal interop plus a presentation adapter.** Admit the real external-memory feature and supported formats/usage; allocate/import dedicated bounded frame textures, copy/produce only with valid image usage/barriers and exportable allocations, signal completion through an actual GPU event/fence, and consume after that dependency. Own output scheduling and true WSI image-retirement rules. A successful memory-handle query alone does not implement the presentation adapter.
2. **A source-built KosmicKrisp WSI extension.** Add typed completed-colour-frame, retain/release and presentation-sink hooks at the real Mesa/Metal bridge, then adapt existing Husk colour-flow generation. Keep a separate pinned experimental framework and original-driver rollback, real semaphore/result semantics, Metal4 residency and cancellation/resize/background epochs. Rebuilding that ICD is required for private hooks; the existing binary cannot acquire those hooks by toggling a setting.

Both need bounded frame slots, GPU completion before sampling, no producer reuse until sampling retires, correct present order, background/resize/device-loss handling and no wait-idle/readback in the normal frame loop. Metal4 producer and Metal compute consumer can share textures with proper shared-event ordering; different API versions are not the fundamental blocker. Capturing a readable source after its real presentation then interpolating past images can move the scene backwards; retaining an Objective-C texture alone does not prevent GPU overwrite. Never count copied/repeated images as unique real60FPS.

The reusable algorithm today is **Husk colour-flow interpolation**, not a claim of native MetalFX temporal/frame interpolation. A native MetalFX approach may also require engine depth/motion-vector inputs not exposed by the current bridge; do not fabricate them. Generated output cannot repair a418ms engine/pipeline freeze and can add latency, GPU work and artifacts.

## Definition of done before exposing combined mode

A real producer/interop implementation and backend capability admission; lifetime/synchronization and resource-loss tests; actual GPU producer→interpolator→present tests (no manufactured input); pinned Apple driver/app/package build; then Dungeons visible quality/input/latency/cadence/lifecycle/rollback checks. Energy benefit is separate. The current candidate fixes a reproducible nativeMetal4 cache-startup defect first and preserves existing choices; no dummy combined-mode switch or claimed implementation is added.
