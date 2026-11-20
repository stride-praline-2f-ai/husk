# Dungeons unified game log: automatic low-impact diagnostics

Source branch: `feature/apple-native-metalfx-rebuild`, 19 November 2026.

## Behaviour and user access

Minecraft Dungeons automatically enables host/native **game-log diagnostics at launch**, even when the on-screen log panel is closed. The bar's **Log** button shows `GAME LOG & DIAGNOSTICS`, using one merged `HuskLog` stream for guest UE4/JNI/Vulkan and Swift host summaries. The viewer keeps a 1200-line tail for responsiveness; **Copy full log** copies the complete on-disk file, including the launch records and older slow-pipeline events. No second export or developer toggle is required for the routinely useful facts.

Included by default, at limited frequency:
- Host process CPU (sampled difference, 15 s), memory footprint, approximate jetsam headroom, thermal class and OS Low Power Mode; never label them watts or real GPU utilisation.
- Native 10 s Vulkan host frame cadence, p95 and worst interval, slow graphics pipeline creation and seed acceptance, acquire/submit/present/sleep host durations; no claim that host present cadence equals true panel FPS.
- Actual Apple MetalFX spatial configured/encoded/failure counts, input/output extents (not a guarantee of visible clarity), **native frame interpolation remains OFF** until real engine buffers and completed presentation exist.
- Automatic **image-allocation metadata only**, without full `vkCmdBeginRenderPass` interposition. Bounded native resource groups are sampled in the existing 15 s UI timer; up to 12 likely depth/velocity formats are emitted to the game log only on discovery/change. Format and usage are *candidates*, not proof of Unreal motion/depth content. Missing or lost observations remain visible.
- Native worker QoS policy/rollback, memory reserve events, game lifecycle, Vulkan errors and existing cached pipeline warnings.

Safeguards: no per-frame Swift log; no always-on driver-phase profiling; no readback or wait-idle; no exhaustive renderpass capture, shader tracing, persistent extra GPU buffers or repeated full Mach memory maps. On-device energy change remains unknown. Error/failed-probe statuses are retained instead of manufacturing data. Only Dungeons gets automatic image-only interception; other games keep previous opt-in behaviour. Users can still explicitly enable full inventory for a bounded deeper comparison, and should disable it after collection.

The system's one unified game log is the default handover for follow-up debugging. If genuine scene velocity/depth cannot be validated from this metadata, the next milestone remains GPU-safe source-renderpass tracing plus on-device shader/texture semantics verification, not flipping on synthetic frame generation.
