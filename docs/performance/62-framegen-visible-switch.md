# M9-FG-QUALITY-v1 — decoded movement-switch evidence

**Repair follow-up:** [Verified168 candidate](builds/023470100c159eb32ff2777a28658f334229e548.md)
implements coherent reconstruction/filtered correspondence with actual GPU
before/after controls; real-game image comfort and net cost remain unverified.
The clip remains167-context visual failure evidence, not a168device pass.

15 November 2026. Follows [the167 ON/OFF result](61-returned167-framegen-quality.md)
and the user's discomfort report. This valid replacement MOV supersedes the
earlier *unavailable footage* status; the incomplete Adobe Express MP4 remains
recorded as a separate failed input. Do not ask the user to reproduce discomfort.

## Actual inspected input

[Receipt](runs/METAL4-FG-167-valid-video.receipt.json): MOV5,933,036bytes,
SHA256`21e236c9d94aa60527f0063622dc53d920d36b41eb68363da8d76a68355f676a`.
HEVC/BT.709, encoded2008×2854, display rotation−90°, duration1.48seconds.
FFmpeg decodes88 displayed frames, PTS0.000–1.450seconds. The track's107sample
metadata is not the number of displayed frames decoded after the MOV edit.
No app/source/FG marker is embedded in the visible image. Attribution to the
reported167 FG problem uses the user's context and independently stamped paired
logs, not a new identity extracted from pixels.

Inspected a4×3overview at8samples/second, then consecutive frames19–42
(PTS0.300–0.683333seconds), including close crops of the character, wall and
ground. During movement, fine detail changes between clearer edges and softer,
doubled/smeared edges. Character/sword contours and brick/paving detail show
the problem more clearly than the comparatively steady host controller overlay.
This is positive visual evidence of the reported moving-image quality failure,
not just an FPS counter or a medical diagnosis.

No large whole-frame brightness flash is apparent in this short recording.
As a limited cross-check, after FFmpeg display rotation and scaling to1427×1004,
mean encoded RGB-derived luma ranges0.38665146–0.39951432; the largest adjacent
mean change is0.000993014 on a0–1scale. This is a code-value spatial mean,
not physical luminance, a linear-light measurement, or a flicker/comfort safety
test. It cannot exclude local contrast changes or actual panel behavior.
Compression/capture/scaling also affect detail and timing. Do not infer device
refresh, HDR behavior, GPU duration or real/generated classification from HEVC
frame types or nominal60FPS metadata.

## Source relationship and repair scope

The presenter in `patches/metalfx/HuskFramegen.inc` intentionally submits a
generated intermediate image followed by the unchanged current real image.
`HuskFramegen.metal` reconstructs accepted pixels at an intermediate warped
position but returns the **unwarped current pixel** at rejected locations.
This can put adjacent pixels from different motion phases in the same generated
image. Coarse bilinear flow and subpixel resampling can change edge sharpness;
the next real image has a different spatial response. These mechanisms are
consistent with the observed shimmer/softness switch. They do not establish
which individual captured frame was generated or exclude engine temporal AA
and30-real-FPS appearance as additional contributors.

The previous167guard tests establish selected HUD/colour/boundary/thin-object
behavior. They do not test spatially textured natural motion over a complete
real/intermediate/real sequence or temporal stability of rejection boundaries.
The returned footage exposes that gap; it does not justify calling the present
algorithm acceptable because its average output callback count approaches60.

Required next engineering acceptance before another FG candidate:

- Reproduce temporal edge/texture instability with a whole-sequence fixture,
  including accurate and inaccurate flow, static HUD, thin moving objects,
  occlusions and natural high-frequency patterns. Preserve existing regressions.
- Ensure the reconstruction/fallback policy is spatially and temporally
  coherent; simply tightening the same pixel threshold can increase phase
  discontinuities, and sharpening cannot establish correct motion.
- Preserve real source detail, frame chronology, ownership,166's lease fix,
  selected output, original Metal4/MoltenVK rollback and shader archive contract.
  Do not relabel duplicate frames as successful interpolation or manufacture
  engine depth/motion/jitter for native MetalFX temporal APIs.
- Validate on the actual GPU before a fresh exact-source IPA. Real-game
  comfort/quality, input latency and netGPU/energy remain separate gates.

No runtime change or new IPA is claimed in this analysis. Existing **FG OFF,
selected60FPS, sourceMetal4/enhancements retained** remains the working clearer
route. No reinstall/cache deletion or new logs/ON-versus-OFF test are needed
from the user now. The painful switch is a failed quality criterion, not a
reason to ask them to keep watching it.

## Reproduction of the offline inspection

Use the original MOV path as `$clip_path`; never overwrite it. FFprobe reads
the display matrix/frame PTS; FFmpeg autorotates by default. Commands used:

```sh
ffprobe -v error -select_streams v:0 -show_frames \
  -show_entries frame=best_effort_timestamp_time,width,height,pict_type \
  -of json "$clip_path" > frames.json
ffmpeg -hide_banner -loglevel error -i "$clip_path" -map 0:v:0 \
  -vf 'fps=8,scale=600:-2,tile=4x3' -frames:v 1 contact.png
ffmpeg -hide_banner -loglevel error -i "$clip_path" -map 0:v:0 \
  -fps_mode passthrough -vf 'scale=1427:1004' frame-%03d.png
```

For each decoded analysis RGB image, compute
`mean(R*0.2126 + G*0.7152 + B*0.0722)/255`; maximum adjacent absolute mean
difference produces the stated limited brightness cross-check. Images were
inspected locally; the original recording is not uploaded to the repository.

Sequence: M1 lease/lifecycle → M9 guarded reconstruction → paired visual failure
→ actual decoded motion evidence → coherent sequence regression/repair still
required → fresh GPU/build verification → separate game quality/latency/energy.
Existing I3/3 only refers to167's scoped implementation/build checks; D1 failed,
D2 partial lifecycle evidence, acceptedD0/2; EUNKNOWN. No fixed-roadmap credit
or benefit claim:31.11%overall/I79.795918%/M4scope34.5667%/Duo0 unchanged.
