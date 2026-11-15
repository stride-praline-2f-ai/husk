# M9-FG-COHERENCE-v1 — coherent intermediate reconstruction candidate168

15 November 2026. User explicitly requests a fix after
[the decoded switch evidence](62-framegen-visible-switch.md) and
[paired167 visual failure](61-returned167-framegen-quality.md). Preserve167's
working FG-OFF/native60/sourceMetal4 route, all selected output/data/caches and
166's scoped autorelease/WSI retirement fix. No more uncomfortable user tests.

## Mechanism and actual scope

The167 shader mixed two differently warped source images, then replaced
individual disagreeing pixels with the unwarped latest image. This both blends
misregistered detail and interleaves different geometric phases within an
intermediate frame. Its even-pixel search cannot represent odd/fractional
movement; the motion regularizer can dominate the actual fitting error and
was also reported as photometric confidence.

Candidate168 reconstructs admitted motion from **one current source** at the
intermediate position. It removes the per-pixel colour-difference phase switch
and temporal source averaging, rather than adding a sharpening slider or
blurring real frames. Bounded Catmull–Rom resampling preserves fractional detail;
its response is clamped to the central source footprint to avoid bright/dark
ringing. Integer positions use an exact single read. Current source illumination
is retained, not averaged between exposures. This is still colour-only
reprojection, not perfect optical flow or native MetalFX temporal generation.

The existing16-pixel tile search gains filtered coarse scales, a half-pixel final refinement, weighted
RGB residual instead of cancellation-prone luminance difference, a reduced
tie-breaking motion penalty and separate unpenalized residual confidence.
Two private motion-only mip pyramids are copied/generated on the GPU before
flow estimation; the guest/WSI textures and their mip-level contract remain
unchanged. Coarse matching uses filtered levels2/1 before original level0,
with a four-pixel coarse grid and a separate optimum per scale. An actual
textured-flow regression is required as well as the injected known-motion
sequence; ramp-only success is insufficient. No CPU readback or queue-idle wait.
The tile count/search radius remain bounded. Forward/backward confidence,
in-image boundaries, nonzero motion and current-frame fallback for genuinely
unreliable fields remain. Static HUD preservation requires temporal support
along a neighbouring axis and projected-side agreement, so an isolated colour
coincidence in moving texture is not incorrectly treated as a fixed layer.
The true disjoint-position thin-object case remains required.

This directly repairs the demonstrated mixed-phase mechanism. It cannot promise
all game blur is gone: coarse flow can still be wrong at depth/occlusion
boundaries, exact engine vectors/depth/jitter are unavailable, and30realFPS
still differs from60realFPS. Rejected fields/boundaries can repeat real pixels.
No output resolution, scene quality CVar, worker policy, presenter chronology,
lease lifetime, cache compiler compatibility or native renderer is changed.
Both source-built colour-flow frameworks must rebuild with the exact shader.

Scratch allocation is owned/released with the presenter. Admission now includes
all four source images, both complete mip pyramids and both flow fields in the
existing96MiB logical texture budget:62,131,376bytes at1816×1280 and91,007,040
at2128×1600. Actual Metal allocation overhead/physical residency are not promised
by this logical estimate. Unsupported larger targets preserve their original
rendered FPS through the existing preflight fallback; no resolution reduction.

## Quality regression and checks

The actual Metal GPU fixture now requires four whole generated/real pairs of
procedural stone-like RGB texture moving by four pixels, with material-specific
illumination changes. Known geometric correspondence means each intermediate
pixel must occupy the two-pixel position under the current exposure, followed
by an exact unblurred real-frame copy. Frozen167 must fail this same test with
`QUALITY_REJECT: intermediate textured sequence jumps to real-frame phase`.
Frozen166 must still fail its original stationary-HUD case. Existing4/16pixel
flow, HUD, moving-thin-object, equal-luminance colour and boundary cases remain.
Actual estimated3/3.5pixel motion and unreliable-field rejection are also required.

First168sourcee059591ef383d4bddb6278c2d28eb6ce87108424 passed its early GPU
controlled-sequence check but was superseded before delivery after review found
the missing end-to-end textured correspondence case. Its unfiltered shader is
frozen as another GPU negative control. The final filtered shader must pass
actual texture motion that rejects that preliminary shader. Its first workflow
43712641855 is historical, not the final delivered artifact.

The workflow runs this one GPU check before heavy driver compilation, then
retains the full required regression/setup/app/package gates. Linux portable
cache tests9/9 pass; spatial4pass/1Apple-only deferred. Actual Apple shader/GPU,
both driver rebuilds, full regressions, fresh app/three extensions/sign/package
and independent exact-source/raw delivery remain **pending** at this entry.
No candidate IPA is ready from portable checks alone.

Extra pyramid copies/filtering, fractional search/colour arithmetic and cubic texture reads cost GPU work.
The removed dual-source blend/read path and integer fast path do not establish
a net saving. Actual A20 GPU duration, presentation uniformity, input latency
and energy remain UNKNOWN; no code-only cooling/performance promise.

M9-FG-COHERENCE-v1 checklist1: I1 scoped source review; I2 actual GPU old/new
sequence regression plus retained tests; I3 exact dual-driver/app/package/raw
delivery. D1acceptable actual game motion/HUD detail and D2continued controls,
audio and lifecycle remain unverified. E1netGPU/latency/energy UNKNOWN. This is
not a new whole-roadmap gate definition; fixed31.11/I79.795918/M4scope34.5667/
Duo0 remain unchanged. Sequence: decoded defect → coherent reconstruction and
fractional correspondence → GPU old/new/whole integration → actual game visual
acceptance → separately measured net cost. Do not ask the user to repeat painful
switching; retain the known clearer FG-OFF path until a verified candidate.
