# Native Apple MetalFX frame interpolation: Dungeons Vulkan evidence gate

19 November 2026. Source: user-supplied iPhone Duo, A20 Pro, iOS 27.3 Dungeons v1.4 runtime log; source reviewed on `feature/apple-native-metalfx-rebuild`.

## Observed in the user's actual log

- Guest UE4 `com.nintendosss.spice`, Vulkan swapchain **912 x 640**, 3 images, format 44 (`VK_FORMAT_B8G8R8A8_UNORM`), output CAMetalLayer drawable **1816 x 1280**, 50% MetalFX spatial request. This proves the separate-size contract, not successful per-frame MetalFX encoding.
- `GL_RENDERER=ANGLE (... Apple A20 Pro GPU ...)` appears for a separate 912x640 offscreen EGL surface while the UE4 Vulkan swapchain is also active. Do not mistake this ANGLE surface for the Unreal scene's motion/depth attachments.
- iOS Low Power Mode is **on**. Requested real FPS cap 60, no thermal-classified throttling. Host frame cadence eventually 60 in some windows but frequent stalls; frame generation must never mask these as actual rendered frames.
- Graphics pipeline creation spikes reached **961.330 ms** and hundreds of milliseconds many other windows, even though the host restores a Vulkan cache seed (~1.16 MB) and uses it when creating pipelines. Accepted seed is not proof of complete pipeline-cache hits. This independent latency problem requires pipeline-level evidence and targeted prewarming/archives, rather than assuming interpolation can fix stalls.
- Shared mapped reserve reached ~2 GB; this is **not** physical RAM used. Jetsam headroom repeatedly remained roughly 5 GB. Missing optional patch OBB warning isn't a proven game-fatal error because subsequent frames continued.
- No observed engine motion-vector/depth GPU texture identities, shader semantics, camera matrices or GPU producer/sampling lifetime evidence in the log. **Do not enable native interpolation** using this log alone.

## Implemented: a safe first evidence gate

- Existing opt-in Vulkan `vkCreateImage`/renderpass inventory is extended with `tl_ri_metalfx_snapshot()` for bounded candidate format/usage groups: depth-attachment, readable-depth, float 2-4 channel motion-like, readable/writable float targets and colour render targets. Classifier excludes stencil-only as depth.
- Existing `render_inventory.native_metalfx_frame_interpolation_preflight` JSON includes counters and explicit negative flags for semantic buffer verification, GPU ownership/synchronisation and integrated real/interpolated presentation. Metadata-only candidates **never** auto-enable the interpolator. This is deliberately less capable than capturing actual GPU textures, and cannot reconstruct motion.
- Automatic Duo profile now preserves the user's explicit Render-target inventory diagnostic (normally Off), while still clearing unrelated tracing/queue experiments. The Dungeons Diagnostics route permits that one diagnostic to be turned on even with Automatic device tuning enabled. No new GPU pass/readback, swapchain change, frame generation, delay or allocation in ordinary playback.
- One-shot diagnostic collection:
  1. Dungeons > Settings > Diagnostics > Detailed Collection: Render-target inventory ON.
  2. Fully restart the game (existing Vulkan function interception is selected at lookup time); keep Automatic device tuning, MetalFX 50/60% and 60 real FPS enabled.
  3. Load gameplay and move the camera for 30-60 s. Open Dungeons > Settings > Diagnostics > Performance test & cache inspection and export a report. Search `render_inventory.native_metalfx_frame_interpolation_preflight` in the JSON.
  4. Turn inventory OFF and restart. Don't compare this capture with an uninstrumented battery test.
- If the report is `required_image_format_candidates_not_observed`, check whether UE4 actually builds a velocity pass on this Android/Vulkan/mobile rendering permutation. Never fabricate vectors with zero fill, random data or stale frame textures.
- If candidate groups exist, **next source milestone** must map Vulkan image, view, framebuffer, renderpass and command-buffer usage to actual scene buffers, including dynamic rendering if used. Classify with shader/pipeline and pass-order evidence, inspect real contents only behind a bounded GPU-completion capture. Reject mismatched scene/HUD textures. This cannot be inferred from VkFormat alone.
- Next, implement a source-built MoltenVK bridge with GPU completed-frame leases, real current/previous scene colour + depth + true velocity and camera constants. Integrate `HuskNativeMetalFX.m` on an ordered Metal command buffer. Follow Apple's dedicated frame-presentation thread approach (generated / real frames) with correct timestamp pacing and no duplicate presents. Require scene-aware UI composition, camera-cut reset, resource-retirement and resize/background/device-loss tests. Only then expose a feature-toggle and evaluate 30 rendered -> 60 displayed.
- Apple integration: https://github.com/apple/game-porting-toolkit/blob/main/game-porting-skills/skills/using-metalfx-frame-interpolation/SKILL.md ; https://developer.apple.com/videos/play/wwdc2025/211/
- Phase is **diagnostic and feasibility**, not functioning Apple frame generation. An actual Mac CI build and on-device report are still required. Keep current stable 60-real-FPS spatial path until they pass.


## 20 November 2026: measured `ba600be` Duo game log

The complete user's 8+ minute `husk.log` (A20 Pro, iOS 27.3, Dungeons Android v1.4) now establishes:

- Native Apple frame interpolator hardware support was explicitly **true** at runtime. The prototype remains **OFF** because there are no validated engine motion/depth texture handles or dual-frame presenter.
- Apple MetalFX spatial scaling **encoded over 26,000 calls with zero reported failures**, at **912 x 640 input → 1816 x 1280 output**. That establishes actual encode operation, not subjective image quality or measured energy savings.
- The passive image-only observer accumulated **4 depth-format groups (3 readable)**, **9 velocity-like float-format groups (9 readable/writable)** and **37 colour groups**; metadata suggests actual Unreal candidates rather than proving semantic contents. The previous preflight described all candidate data as "incomplete" if *any* observation was lost, even if overflow occurred only in unrelated asset formats.
- Repeated `vkCreateGraphicsPipelines` calls had recorded host durations up to **565 ms** in one interval. Stalls continue after a compatible **5.43 MB Vulkan pipeline cache seed** was accepted. Acceptance does not prove a cache hit, and frame interpolation cannot make a missing real frame appear during such a stall.
- Nominal thermal state (`0`) and approximately **4.7–5.0 GiB jetsam headroom** persisted, despite host CPU usage approaching **~200% of one core** (roughly two cores' worth) and a physical process footprint around **1.9 GiB**. Low Power Mode switched on during the session; the measured FPS and process CPU should not be interpreted as energy consumption.
- Repeated `VK_ERROR_FEATURE_NOT_PRESENT`/primitive restart warnings are nonfatal within this observed session; the game continues producing frames. The missing optional patch OBB notice also did not stop gameplay.
- Image-only inventory pass is now automatically enabled, and change-only snapshots can enumerate format/extent/usage for up to 12 candidates in the same game log.

**Source correction on this branch:** Count asset-target-renderpass capacity losses individually in the native bounded inventory and report them explicitly in the Dungeons game log and JSON. Positive candidate-format groups remain visible even if unrelated asset observation slots are full. Fewer false inconclusive statuses does **not** amount to verified UE4 motion vectors or admission to Apple frame interpolation.

**Next engineering gate:** prove each candidate's Vulkan image/view identity, framebuffer attachment mapping, scene producer pipeline, camera matrix and frame chronological availability, then export ownership-safe MoltenVK Metal textures. This is not possible from image-creation format and usage alone; no working native frame-generation path is claimed.
