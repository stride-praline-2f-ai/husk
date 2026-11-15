# Dungeons settings and residual motion review

15 November 2026. Source baseline: `optimized` at `1a68a811f271eb310a2e057dd99b14b46244b413`. Local work: `fix/framegen-motion-clarity`. The user reports the previous branch did not help motion fuzziness. Treat visual acceptance as failed, not resolved by the prior build/test records. Scope is Husk's Dungeons settings and their launch/runtime implementation; the APK's own in-game menus have not been run or inspected in this environment.

## Findings that affect ordinary use

1. **Automatic and Sharp / Efficient are aliases for recognized Dungeons.** `usesSharpGraphics` and `usesEfficientGraphics` resolve both to the same behavior. Preserve their stored values for compatibility but display one Recommended option for this game.
2. **Resolution is spread across three concepts.** Display resolution is unused under Sharp presets; Rendering Resolution controls the output surface; MetalFX Input Budget controls a second, smaller render size. These last two are distinct and can compound. Show one output-resolution choice with pixel dimensions; expose input scale only under MoltenVK upscaling. Do not merge the two percentages or silently change either.
3. **Automatic Duo is a broad preset, not just automatic resolution.** `applyDuoAutomaticProfile` forces 60 source-FPS selection (FG subsequently requests 30), worker policy, default submission/queue options, MetalFX 80%, disabled clock experiments and detailed diagnostics. Native-archive choices survive only with enhanced Metal4. A control whose saved value is overridden needs an effective-value explanation. The entire Advanced Graphics & Diagnostics form is currently disabled under this preset, including report buttons that should remain accessible.
4. **Several visible controls cannot affect the selected renderer.** On actual Metal4 selection, launch explicitly disables MetalFX and both clock modes; compatibility Metal4 also disables archive settings. MoltenVK prefill/active-command-buffer/submission controls are not equivalent Metal4 tuning controls. Hide or explain unsupported choices without deleting saved rollback values.
5. **Frame-rate controls disagree about what is being set.** Main Frame rate combines native30/native60/30-to-60FG, whereas advanced Frame Limit sets the source preference. Under FG that source preference is overridden. Automatic Duo even labels Frame Limit as 60 while FG requests30. Use one authoritative control and separate requested rendered/output readouts.
6. **Profiles do not reproduce a full current configuration.** `EfficiencyProfilesView.save/apply/restoreReference` do not include `automaticDuoProfile`, `a20EfficiencyWorkers`, `metal4Renderer`, `enhancedMetal4` or `frameGeneration`. An old profile's FPS/MetalFX/queue choices can therefore be superseded by retained flags. Label them as partial legacy experiments until a versioned schema can represent effective settings; never promise an exact restore.
7. **Diagnostics have multiple homes.** FG capture is on the main page; performance/archive tools are two levels into Advanced; MetricKit is repeated globally. Consolidate navigation, not collection mechanisms: image capture, performance sampling, pipeline preparation and OS reports measure different things.

## Every per-game control

Decisions below are recommendations from source review, not UI changes already shipped. Stored preferences and manual rollback paths remain intact.

| Current control or feature | Actual role / overlap | Recommendation |
|---|---|---|
| Name | Husk label; recognition also checks known package | Keep in app details |
| Use recommended graphics | Resets graphics preset to Automatic; not all advanced preferences | Keep as preset selection; do not label a full reset |
| Graphics preset: Automatic | Recommended efficient policy for recognized Dungeons | Combine display choice with Sharp / Efficient |
| Graphics preset: Sharp / Efficient | Same policy as Automatic for Dungeons | One Recommended choice; preserve decoding |
| Graphics preset: Sharp / High Quality | Sharp policy, native output; efficient FPS/resolution controls unavailable | Keep as advanced quality override, explain consequences |
| Graphics preset: Game Default | Bypasses sharp/efficient overrides | Keep compatibility rollback in Advanced |
| Active Preset | Derived text, not a setting | Replace duplicate row with effective-settings summary |
| Frame rate:60 /30 /60 with FG | Native output or30 real frames plus generated/repeated slots | Keep one main selector; explicitly label30 rendered →60 output target |
| Advanced Frame Limit | Same saved native source cap, overridden by FG/automatic policy | Remove duplicate editor for Dungeons; show effective source cap |
| Resolution: Automatic /Native /Custom | Main surface size | Keep one main selector plus current pixel estimate |
| Rendering Resolution presets65–100% | Alternate editor for same surface-size preference | Combine with main selector; optional quick stops on custom slider |
| Custom percentage /Render Scale slider | Same custom dimension percentage in two places | One slider65–100%,1% steps; retain exact existing percentages |
| Display Resolution:Low/Medium/High/Native | Used outside Sharp presets only | Hide irrelevant editor; keep only for Game Default |
| Fullscreen Target | Estimate from selected scale, not measured output | Put beside resolution; label estimate |
| Renderer:Metal4 /Compatibility /MoltenVK | Source-built, published Metal4, or MoltenVK | Keep one advanced picker; show selected/effective renderer |
| Metal4 Enhancements | Underlying source-driver selection; already folded into renderer picker for Dungeons | No extra Dungeons toggle |
| Dungeons Frame Generation toggle | Legacy alternate editor; Dungeons now routes through simple page | Remove unreachable duplicate Dungeons block; use main selector |
| Automatic Duo Inner Screen | Coupled device preset, conditionally applicable to matching inner panel | Present as explicit Automatic device tuning mode, distinct from resolution |
| A20 Efficiency Workers | Runtime-matched worker-budget policy under automatic profile | Keep nested hardware option; no claimed core affinity or energy win |
| Shared Game Memory | Separate supported-iPhone helper/residency mechanism | Keep advanced Memory option with availability/status |
| MetalFX Spatial | MoltenVK-only lower internal input followed by upscale | Single advanced Upscaling picker:Off /MetalFX when supported |
| MetalFX Input Budget80/85/90/95% | Fraction of output dimensions, not output resolution | Nested input-scale choice; show input →output pixels |
| Render Target Inventory | Image-size diagnostics, no quality tuning | Move to Diagnostics; independent opt-in |
| Worker Scheduling | Five scheduling/observation policies, overridden by automatic Duo | Keep in Developer experiments, distinguish observation from changing policy |
| Engine-only60FPS Limiter | Host-limiter comparison, not the normal FPS choice | Keep diagnostic experiment; display effective cap and FG interaction |
| Guest-Clock Feedback Only | Timing experiment; overridden by FG and Metal4 | One advanced clock-mode editor only after checking mixed legacy flags |
| Clock-Correct Presentation | Different timing experiment; also overridden by FG/Metal4 | Same clock-mode editor, preserving old stored combinations/migration |
| Vulkan Submission | MoltenVK synchronous/default versus async experiment | MoltenVK-only Developer control |
| Metal Command Preparation | MoltenVK prefill strategy | Same queue experiments group; keep independent from submission |
| Active Metal Buffer Limit | MoltenVK per-queue limit | Same group, hide for unsupported driver |
| Swapchain Images | Surface-limited2/3-image override | Keep independent; it is not the command-buffer limit or FG lease count |
| Block During Initialization Waits | Startup wait behavior | Keep Developer startup experiment; not a smoothness preset |
| Native Pipeline Cache:Off /Driver Only /Archive | Native archive mode; Driver Only is a comparison path | Ordinary Off/On; preserve Driver Only in Developer comparisons |
| Verify Native Archive Reuse | Extra lookup evidence, depends on Archive Enabled | Nested diagnostic option; not another cache feature |
| Pipeline Identification | Pipeline-key diagnostic capture | Consolidate UI with feedback into diagnostics detail level |
| Pipeline Creation Feedback | Requires identification; extra compiler evidence | Off /Identification /Identification+Feedback; retain legal stored behavior |
| Driver Phase Profiling | Additional detailed driver overhead | Detailed Diagnostics; default off |
| Device Graphics Profiles | Manual device/game experiments, incomplete modern flags | Keep saved profiles; version schema before offering full save/restore |
| Performance readout | On-screen statistics only | Display group, separate from diagnostic capture |
| Orientation | Startup surface orientation | Display group; keep |
| Keep the screen on | Idle-lock prevention | Display group; keep |
| Open In:Default /Window /Full Screen | Window routing; affects automatic-profile eligibility | Display group; explain automatic profile is fullscreen-only |
| Hide the interface | Hides bar/controller/readout at launch, three-finger restore | Combine placement under Display/Overlay; keep separate setting |
| On-screen controller:Automatic /Always /Never | Same editor on main and advanced pages | One Controls page, optional main-page link/status |
| Controller opacity | Appearance only | Nested Controls setting |
| Vibrate on a press | Controller haptics | Nested Controls setting |
| Generate App Clip | Home Screen launch helper | App details /Home Screen; unrelated to graphics |
| Saved by the game | Storage readout | App details /Storage |
| Reset Game Data | Deletes saves/settings/caches; guarded while loaded | Keep separate destructive Storage action; never include in graphics reset |
| Geode | Geometry Dash-only; not a Dungeons feature | Already excluded; no Dungeons setting needed |

## Diagnostic actions and subfeatures

| Feature | Decision |
|---|---|
| Capture FG evidence /status /cancel | One Image quality section in Diagnostics; retain bounded local capture and cancellation |
| Share diagnostic bundle | Single FG export entry; preserve incomplete-stage metadata and manual sharing |
| Performance & Efficiency Diagnostics | One Performance section; ordinary report access must survive Automatic tuning |
| GPU execution sampling | Optional performance detail; not interchangeable with phase profiling |
| CPU-thread/submit sampling | Optional CPU detail; retain independently selectable collection |
| Component CPU/wait sampling | Optional component detail; may collect different evidence than thread sampling |
| Native display sampling | Optional presentation detail; distinguish actual callbacks from generated-frame counts |
| Start /stop test | One session action; do not conflate with changing FPS or graphics |
| Phase marker /manual interruption exclusion | Keep within an active diagnostic session; preserve evidence exclusions |
| Export report+JSON /share exported files | Combine navigation/wording where useful; preserve stop/export/in-progress states |
| Inspect /share native archive inspection | Cache Diagnostics subsection; inspecting is not enabling archives |
| Pause and prepare captured pipelines | MoltenVK-only manual operation; retain actual pause/cost safeguards |
| Share preparation receipt | Same cache subsection; retain separately from unrelated performance reports |
| Delayed OS Reports (MetricKit) | Link to shared OS reports destination; not a per-game rendering switch |
| Save /apply /undo /share /delete local profile | One Profiles tool; retain device/game/version validation, existing files and undo |
| Restore M4 reference | M4-only historical reference; fix incomplete-modern-flag restore before describing as full reset |

## Proposed organization

Main: **Frame rate, Resolution, Controls**, plus **Advanced** and **Diagnostics**. A compact readout shows effective renderer, requested real/output rate, output pixels, and upscaling input where applicable. No new quality switches.

Advanced: **Graphics** (one preset, renderer, supported upscaling), **Device tuning** (Automatic/Manual and hardware-specific options), **Display & Controls**, **Memory**, **Saved experiments**. Keep low-level queue/worker/clock comparisons in a separate Developer experiments destination. Diagnostics remains available regardless of tuning mode. Keep app name/Home Screen/storage actions in app details.

Implement UI consolidation separately from the FG shader change so neither a setting migration nor a changed output scale can masquerade as a motion-quality fix. Before merging a new settings UI, test old settings decoding, preset equivalence,30FPS preservation, custom scale retention, renderer/FG admission, profile partial/full semantics, and saved-versus-effective launch values. Do not combine distinct execution mechanisms just because their labels sound similar.

## Separate concrete reconstruction defect

The current flow field is defined at current-frame positions, but171 samples it at midpoint output positions and samples the reverse field relative to that wrong anchor. Constant translation tests do not expose this: a field is then spatially constant. Under affine motion such as zoom/shear, the correct current position q satisfies `q + f(q)/2 = p`. Local fix performs three bounded lookup corrections and checks reverse motion at `q + f(q)`. It preserves single-source cubic reconstruction, exact real copies, existing HUD/quality guards, ahead-of-tick preparation and lease ownership. Adds three low-resolution flow samples per generated pixel; GPU cost and nonconvergent/occlusion behavior need Apple testing. This is not proof of the sole cause of the user's blur.

Portable test executes the actual Metal helper body through a C++ analytic-sampler adapter: zero motion, translation, zoom and shear match analytic inverse coordinates within0.03pixels. Frozen171's central zoom sample is wrong by more than0.8pixels. Full actual-GPU fixture adds an injected affine field/image assertion and frozen171 negative control after all prior cases. No Apple SDK/GPU is available in this Linux workspace: GPU compilation/execution, full iOS regression/build, both driver packaging and physical quality remain pending. No IPA is declared ready or new recording requested.

Validation here: seven relevant suites discover29 cases:10 pass,19 Apple-dependent skips, no failures. The standalone portable coordinate case also passes. Settings code/storage are unchanged; this document is the review, not a shipped cleanup.
