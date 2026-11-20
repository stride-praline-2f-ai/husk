# Dungeons on iPhone Duo: CPU translation and Vulkan PSO-hitch reduction

**Source:** `feature/apple-native-metalfx-rebuild`, 20 November 2026. **Status:** Code submitted for Mac CI; actual energy savings and stutter elimination are not established.

## Evidence before changes

The `ba600be` device log confirms roughly 60 rendered FPS for many 10-second windows, with intermittent dips associated with host `vkCreateGraphicsPipelines` calls lasting 200–565 ms. A 5,428,788-byte Vulkan cache seed is restored and accepted. It does **not** establish individual application/Metal cache hits: the user sees heavy new PSO compilations despite a valid persistent blob. Device has nominal thermal state and ample jetsam headroom; neither GPU temperature nor electricity drawn by CPU/GPU is measured. Process CPU reaches about 200% of one core in the current capture; that does not identify exact expensive guest functions.

## Changes with a plausible direct mechanism

1. **Native ARM64 guest TLS entry fast path.** `husk-tl-ld.c` replaces repeated `pthread_once` + `pthread_getspecific` lookups on each `__tls_get_addr` and UE4 TLSDESC operation with a **per-thread native TLS pointer**. First use retains safe `pthread_key_create`, `pthread_setspecific`, thread-exit destructor, initialized module memory and zero-fill. Compiler still uses the original ABI shim; no game state, JIT memory size, or executable mappings are altered. The new `test_tls_fastpath.py` compiles the real fast path and checks first use, repeated accesses and simultaneous per-thread separation. This removes two host-runtime operations from **frequent TLS accesses**; end-to-end CPU and battery improvement requires measurement.

2. **UE4 built-in PSO warm-up instead of forced synchronous bulk compile.** High/Sharp and Sharp/Efficient Android/Vulkan engine settings request `r.ShaderPipelineCache.Enabled=1`, `r.ShaderPipelineCache.StartupMode=2` (background), `r.ShaderPipelineCache.BackgroundBatchSize=2`, `r.ShaderPipelineCache.BackgroundBatchTime=1.0` ms and `r.Vulkan.PipelineCacheFromShaderPipelineCache=1`. These are *engine requests* and take effect only if the actual game build supports the CVars and has usable PSO cache data. They do **not** automatically generate a complete offline game PSO cache. All injected settings live within the existing reversible Husk marker; switching off Sharp restores the original config bytes. See Epic's UE 4.27 Android guidance: https://dev.epicgames.com/documentation/ko-kr/unreal-engine/pso-caching-on-android?application_version=4.27 .

3. **Persist cache at normal Vulkan shutdown.** `w_vkDestroyDevice` saves dirty serializable cache state **before** destroying the owning device, in addition to Husk's existing pause checkpoint. No pipeline creation or queue submission runs a checkpoint, so save costs occur on shutdown or background only. Sudden process termination is not recoverable. Cache contents and driver UUID remain validated on load.

4. **Safe buffer provenance for a future Apple MetalFX interpolator.** Vulkan interceptor records successful target images (including *live* handles), image views and framebuffer links; explicit full mode additionally counts `vkCmdBeginRenderPass` use. Native recorders are fixed-capacity, use non-blocking creation-time locks, hold metadata only and do not copy GPU data. All stdout evidence is joined into the existing Dungeons game log. A `VK_EXT_metal_objects` device-extension request is appended only on the MoltenVK Dungeons path when advertised and is retried without changing guest settings if explicitly rejected. **No Metal texture ownership is transferred and interpolation remains OFF** until genuine depth/motion semantics, camera matrices, GPU synchronization and presentation are verified. VK formats and framebuffer associations alone are insufficient.

## Validation & release gates

- Tests: `tests/translation-layer/test_tls_fastpath.py`, `test_ue4_graphics.py`, `test_render_inventory.py`, `test_metal_export_device.py` plus normal full regression suite, Apple driver compilation, Xcode native app/package verification.
- Test on the actual Duo in matched scenes: warm launch after at least one prior pause/normal exit; Low Power Mode kept identical across runs; compare median/p95/p99 frame times and >50ms/>100ms stalls, elapsed host pipeline creation totals, number and estimated extent of new shader PSOs, sustained CPU usage and battery percentage per fixed-duration test. Sample data across a cold and a warm session.
- Risk/fallback: if game boot, visual quality, PSO compatibility or cache durability regresses, disable Sharp/efficient preset or revert this isolated branch. Never treat cached source blobs as proof of native Metal pipeline hits or pledge 'zero stutters' without GPU-cache and real-device evidence.
- Further work: detect actual game-packaged `.upipelinecache` files; collect missing PSO keys and stage feedback; precompile safely during loading screens if the actual UE4 project can honor it. For MetalFX, identify true velocity/depth producers, export only lease-safe Metal textures and implement a dedicated synchronized presenter with camera-cut and lifecycle tests.

## Caveat

Khronos MoltenVK pipeline-cache serialization helps reuse SPIR-V→MSL conversions, but on a new pipeline combination the native Metal pipeline may still need compilation. Unreal's bundled PSO cache and Vulkan driver blob are related but distinct layers. The current code improves their use and reporting, **not a guaranteed stutter-free result**.
