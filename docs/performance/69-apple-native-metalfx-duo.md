# Apple-native MetalFX Duo presets (proposal and working source branch)

19 November 2026. Branch: `feature/apple-native-metalfx-rebuild`.
User direction supersedes older Metal 4/KosmicKrisp and image-derived frame-generation defaults.
This is **not a certified iOS build or on-device 60 FPS result**.

## Corrected target geometry and policy

Duo inner panel recognition uses native 2670 × 1878 portrait pixels, and fullscreen
render output currently resolves to ~1816 × 1280 landscape pixels. The ratio of
the panel is 1.42173, not exactly 10:7 (1.42857); do not hardcode 10:7 geometry
or the full physical panel into the scaler descriptor.

| User preset | Native Vulkan render input | Apple MetalFX output | Relative input pixels |
| --- | --- | --- | --- |
| Max battery 50% | 912 × 640 | 1816 × 1280 | 25.1% |
| Balanced 60% (new Duo default) | 1088 × 768 | 1816 × 1280 | 36.0% |
| Quality 67% | 1216 × 856 | 1816 × 1280 | 44.8% |
| Extra sharp 80% | 1456 × 1024 | 1816 × 1280 | 64.1% |

Inputs are eight-pixel aligned by nearest rounding; actual size is derived from
the output extent at launch, not hardcoded as a target for the outer display.
These ratios quantify fragment/input pixels only. They do not measure total GPU
work, MetalFX cost, heat, battery, frame cadence or subjective HUD legibility.

## Selected runtime path

1. UE4 keeps its **Vulkan** guest frontend. Husk chooses its pinned
   `HuskMoltenVK.framework` when native Apple MetalFX spatial scaling is requested
   and the binary exists, otherwise falls back to standard `MoltenVK`.
   The `HuskSpatial.inc` integration creates Apple's `MTLFXSpatialScaler` from
   the actual Metal texture formats, validates input/output dimensions, and
   encodes on the same Metal command buffer as Vulkan presentation.
2. `TLAppSettings` stores `duoSpatialPreset` independently of older
   `spatialInputPercent`. Automatic unfolded Duo chooses this preset and a real
   **60 rendered FPS request**. The UI shows the estimated input/output pair.
   Legacy `frameGeneration`, `metal4Renderer` and `enhancedMetal4` are
   decoded inertly for saved preference migration; gameplay never selects
   KosmicKrisp and always asks for old Husk frame-generation OFF.
3. `HuskNativeMetalFX.m` contains an optional **Apple MetalFX** interpolator
   admission/encoding adapter. It is NOT wired into the game's frame loop.
   It requires real frame-pair colour, depth, motion, view/projection inputs and
   synchronized dual output presentation, none of which the current final
   Vulkan swapchain capture provides. Do not synthesize engine vectors or
   claim real frame generation from an unused adapter.
4. Native scaler uses `Perceptual` for BGRA8Unorm's sRGB-like encoded values
   and `Linear` when sampling `BGRA8Unorm_sRGB` into linear values.
   This depends on real texture encodings, not only the Unreal version.
   The MetalFX scaler is created for each swapchain image, then reused per
   presentation, with output drawable texture rebound as needed. Descriptor
   format and output extent match the actual CAMetalLayer drawable, not
   physical panel pixels assumed by Husk.

## Remaining blockers and validation

- **Live fold/unfold**: `TLUnityUIView.layoutSubviews` intentionally retains
  the UE4 Vulkan swapchain extent after the game starts. Changing the Metal
  drawable size alone would break guest/driver agreement. Correct implementation
  needs render-thread-driven `vkDeviceWaitIdle` or equivalent fenced quiescence,
  swapchain teardown/recreation with the new window extent, UI/pointer scale
  propagation, and scaler resource retirement only after GPU completion.
  Current safe route is restarting the game after a display-size transition.
- **Native frame interpolation**: interrogate real Dungeons UE4 Vulkan render
  passes to determine whether and where scene velocity and depth images exist;
  expose them safely as Metal textures, preserve colour/depth/motion agreement,
  and add native interpolated/real dual-frame presentation. The APK's colour
  swapchain alone is insufficient. UI should remain composited at output size
  where possible.
- **Actual 60 FPS and battery claim**: verify real render FPS and MetalFX
  encode cost, not displayed/generated frame count. Hold ~16.7ms/frame
  within thermal and memory budgets. Compare HUD text, character motion,
  transitions, lifecycle and input latency across 50/60/67/80% at matched
  conditions before claiming the Balanced preset is visually optimal.
- **Physical iPhone fold transition** and **signed IPA**: no confirmation.
  Mac SDK compile, complete CI regression and actual device validation pending.
  Preserve game saves, caches, existing MoltenVK fallback and 60 FPS cap.

Apple docs: https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerdescriptor
https://developer.apple.com/documentation/metalfx/mtlfxspatialscalercolorprocessingmode
https://github.com/apple/game-porting-toolkit/blob/main/game-porting-skills/skills/using-metalfx-frame-interpolation/SKILL.md

Portable source geometry check in authoring environment (not a full repo build):
C11 `-Wall -Wextra -Werror` compiled and produced expected 50/60/67/80
values. Added `tests/translation-layer/test_native_metalfx_duo.py`
to Mac CI 52-suite inventory. Full tests unrun in this environment.
