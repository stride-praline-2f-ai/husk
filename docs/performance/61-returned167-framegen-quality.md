# M9-FG-QUALITY-v1 — build167 real-game quality criterion failed

**Later scoped repair:** [Verified168 candidate](builds/023470100c159eb32ff2777a28658f334229e548.md)
addresses the mixed-phase mechanism with filtered coherent reconstruction and
actual GPU negative controls. It does not retroactively pass167's visual result
or establish phone comfort. No repeated uncomfortable comparison is requested.

**Valid replacement MOV now inspected:** [Decoded visual evidence](62-framegen-visible-switch.md)
supersedes the earlier unavailable-footage status below.88decoded frames show
changing clarity/doubled edges during motion; no large global brightness jump
is apparent in the short clip. Source review identifies a possible mixed-motion
phase problem in generated per-pixel fallback, not a proven sole cause or
repaired algorithm. Enough evidence to document the visual failure; keep FG OFF,
no further uncomfortable comparison or general logs. No new runtime/IPA.

**Later returned recording / discomfort report, 15 November:** user says the
switch hurts their eyes. Keep FG OFF; do not request another uncomfortable
comparison. The uploaded Adobe Express MP4 cannot be visually analysed:
two independent downloads are byte-identical,14,202,968bytes, SHA256
`724633afd724764cfab7004857eddafa4c4736448824f9fcb6b4902c6d8d4537`.
The `mdat` box declares14,233,408bytes at offset40 but only14,202,928bytes
remain (30,480bytes missing within that box), and there is no `moov` metadata.
FFprobe reports `moov atom not found`; zero frames were decoded. See the
[receipt](runs/METAL4-FG-167-video.receipt.json). This establishes an incomplete
uploaded/exported file, not where truncation occurred. No observed brightness
flash, alternating blur or medical cause can be claimed. The existing real /
generated-image alternation and per-pixel fallback are possible contributors,
not a diagnosis from unseen footage. Request only the existing original Photos
recording if available, without recreating the effect; further repair remains
pending actual visual evidence. The prior optional30FPS test below is suspended
because the user now reports discomfort. No runtime change or replacement IPA.

15 November 2026. This supersedes the *pending* phone-quality status in
[the 167 handover](builds/3fcf97c285124e3d7a8e9e01d40e17abe00635b6.md).
It does not invalidate the recorded synthetic GPU or packaging checks.
The user now reports that movement still looks fuzzy with FG ON and that
FG OFF fixes it. The delivered guard is insufficient for this game result.

## Identity and comparison

All four attachments were read in full. Both host headers independently stamp
3.4/167, source `3fcf97c285124e3d7a8e9e01d40e17abe00635b6-dirty`, built
2026-11-15 11:02 UTC, iPhone19,4, iOS27.3, six CPUs. This is the delivered
167, not an older 166 shader or a newly rebuilt app. The attachment hashes,
all timing/FG windows, cache events and completed lifecycle sequences are in
[the machine receipt](runs/METAL4-FG-167-paired.returned.json). Reproduce with
[the extractor](runs/METAL4-FG-167-paired.analysis.py) and the original four-file
directory. Historical `[prev]` lines are excluded; native stderr mirrored in
the host log is cross-checked rather than counted twice.

Both modes select source-built HuskKosmicKrisp, Metal4 enhancements and Sharp /
Efficient, with actual guest swapchain and drawable **1816 × 1280**. The
Automatic Duo profile selects worker mode4/normal-worker allowance2 and Driver
Default; this is a scheduling policy, not fixed P-core placement. Actual A20
admission or benefit is not demonstrated. ANGLE's offscreen startup probe does
not mean the Vulkan scene switched away from KosmicKrisp. The source-built
Metal4 path is selected and producing GPU-completed frames; this is not proof
of perfect game pixels, displayed cadence or lower power.

| Mode / report window | Real host cadence | P95 / maximum interval | Pipeline call total / maximum |
|---|---:|---:|---:|
| FG ON, first reported window | 26.6 FPS | 38.18 / 552.14 ms | 938.299 / 50.210 ms |
| FG ON, following window | 29.9 FPS | 38.76 / 55.06 ms | 46.645 / 36.833 ms |
| FG ON, screenshot-overlapping window | 21.7 FPS | 115.00 / 424.80 ms | 0 / 0 ms |
| FG OFF, reported window after resume | 58.1 FPS | 20.84 / 49.79 ms | 15.553 / 8.674 ms |

These are host durations, not GPU execution or measured display scanout. The
ON real target is30, OFF60; 58.1 is near60, not stable exact60. First ON launch
restores no compatible seed. OFF restores13,017,161 bytes accepted by the API;
both save later checkpoints and skip unchanged data. This confirms persistence
mechanics, not native PSO hits or a cache-matched performance comparison.

FG ON counters reach842 GPU-completed real frames at the last aggregate,
active1/failed0/GPU errors0; later guest heartbeats reach1207 before intentional
pause. In the steady window, deltas are299 completed real,299 real presentation
callbacks and299 generated callbacks, approximately60 callbacks/s. Generated
pixels can fall back to a real image. These counters do not establish60 unique
sharp images or even16.67ms display spacing. During the slow window deltas are
218 completed real and431 total presentation callbacks, approximately43/s.
No four-frame launch starvation recurs. OFF reaches1611 guest heartbeat frames.

## Interruptions and reliability

Both runs launch at Low Power Mode0, then switch to1 after the first return;
reported thermal state remains0. The user previously confirmed changing LPM.
The results are not a matched LPM-OFF energy or timing benchmark. Nonetheless,
the user-visible OFF improvement is meaningful and must not be dismissed as
thermal state or a bad install.

The slow21.7FPS ON window overlaps four `screenshot_observed` notifications at
53,501.80 / 53,508.35 / 55,953.57 / 56,002.27ms. Maximum host sleep overshoot is
244.735ms, with no pipeline creations. Capture/system scheduling can confound
this window; logs cannot apportion the time or prove that screenshots caused
it. The source screenshot observer only records an event; it does not pause
or rebuild a drawable. Notifications are not attached pixel captures and
cannot establish how an edge actually looks. No busy-spin or cache rewrite
is justified by these aggregates.

All seven ON and all nine OFF lifecycle begin sequences have matching completed
sequence/paused values, and return swapchains recreate successfully at the same
size. The final static tails follow completed intentional pauses. This is
positive scoped launch/pause/resume evidence after166; it does not by itself
pass all controls/audio/visual requirements of D2. Main OBB is present. Optional
patch-OBB/JNI messages occur in both modes; no fatal/device-lost/OOM signature
establishes a new cause here. GPU errors0 does not mean image quality passed.

## Source review and decision

The shared colour-flow shader still estimates one vector per roughly16×16
pixels from nine luminance samples, with a bounded integer search and bilinear
sampling of vectors and warped colours. It has no engine motion/depth/occlusion
inputs or independently tracked HUD layer.167's local RGB agreement guards
reject specific wrong blends but cannot prove a correct trajectory for each
edge. Even two closely agreeing warped samples can both be blurred or sample
the wrong surface. Fallback to the latest real pixel can also create local30FPS
motion next to interpolated motion. Passing the selected synthetic fixtures
never established general Dungeons image reconstruction quality.

The returned comparison isolates the **FG mode as a whole**, not just a shader
operation: it also halves real scene updates from60 to30. Engine temporal AA,
30FPS sampling/display persistence and interpolation may each contribute.
Requested motion-blur/dynamic-resolution CVars are OFF, but their runtime game
effect and actual scene pixels are not established by swapchain dimensions.
Do not call the shader the proven sole cause, or promise that sharpening,
extra worker caps or a denser flow field will fix it without an image example.

**Current working recommendation: FG OFF, selected60FPS, same source Metal4
renderer/enhancements and output.** No downgrade of the renderer, data/cache
reset or replacement installation is necessary. No new runtime change/IPA is
claimed for this analysis. Preserve166's lease fix and167's tested guards;
do not silently replace interpolation with a duplicate-frame "fix" or claim
MetalFX temporal inputs exist.

One remaining discriminating control, if continuing the FG repair: compare
**FG OFF at30 real FPS** with **FG ON at30 real FPS** in the same scene. Existing
167 controls support it; no new build or general log campaign is needed:

1. Use fullscreen/same orientation and LPM OFF. Turn **Automatic Duo Inner
   Screen OFF**; keep **Rendering Resolution → Automatic · Reduced Resolution**
   (the same inner-panel resolution function is used; Fullscreen Target should
   remain1816×1280). Keep sourceMetal4/enhancementsON and DriverDefault.
2. Set **Frame Limit → 30 FPS · Lower Power**. In **Frame Pacing & CPU**, retain
   **Worker Scheduling → Baseline-Relative Trial (Experimental)** for both
   checks, matching the automatic mode4 here; do not add another treatment.
   Preserve all other settings. Restart with FG OFF and move in a familiar
   scene for about10seconds; stop for5seconds. Restart with only FG ON changed
   and repeat. This preserves real frame rate/output while changing FG.
3. If OFF30 stays sharp and ON blurs, the interpolation/presenter path is
   implicated independently of real frame rate. If both blur, investigate
   the30FPS engine/temporal appearance before another interpolation edit.
   A short view of the actual affected moving edge/HUD in each mode is the
   missing visual evidence; another general log cannot reconstruct it. Screen
   capture is only for image diagnosis, never a timing/energy benchmark.
4. Restore **Automatic Duo Inner Screen ON**, **FG OFF**, and restart to retain
   the known clearer60-real-FPS route. Keep saves/caches; no reinstall required.

This is an optional focused diagnosis, not a demand to repeat the already
answered native60 OFF/FG ON comparison. Until a specific real image failure is
available, another unvalidated shader-only build would not be a completed fix.

Sequence: M1 lease/lifecycle repair → M9 synthetic quality guards → **returned
game visual criterion failed** → matched30-real/image diagnosis → targeted
repair and actual-game acceptance → separate GPU/latency/energy acceptance.
M9-FG-QUALITY-v1 I3/3 remains synthetic/build100%; D1 failed, D2 partial scoped
lifecycle evidence (full gate pending), D0/2 accepted; E0/1 UNKNOWN. Fixed whole
31.11%, weighted I79.795918%, M4 scope34.5667%, Duo0 and energy gates unchanged.
