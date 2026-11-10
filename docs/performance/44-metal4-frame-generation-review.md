# M3/M9/M10 — native Metal 4 and frame-generation feasibility

2026-11-10. Informational user request after verified Husk3.4/build153 (e955a2d53e80f85627f220e5927333e879ac14b9): are a quoted fork's experimental nativeMetal4 renderer and frame generation already included,can they be added,and would they improve performance/cooling? No replacement IPA,major backend rewrite or FPS-default reduction requested in this assessment. Build153 and its ordinary-use/rollback instructions remain current.

## Confirmed current implementation

Dungeons calls Vulkan;husk-tl-vulkan.m loads the pinned MoltenVK implementation. ANGLE handles OpenGL ES overMetal. The spatial driver implements existing MetalFX spatial upscaling with input/output dimensions and image lifecycle. No MTLFXFrameInterpolator/MTL4FXFrameInterpolator integration,frame-generation settings,or independent nativeMetal4 renderer is wired in the app. A GPU supporting Metal4 or reporting MSL4 is not evidence that a dedicated MTL4 command backend is active. Existing native pipeline binary archives are also separate from a native game renderer or frame interpolation.

The supplied quotation has no repository/release/commit link. Asked for that link through the pending clarification. Searches did not establish the exact quoted fork. The previously reviewed MeloNX source13700519f3abc4e6d7ed8a065b118b2cc59bcd67,src treebc8d75c926bb8375f0e65a1b7f2a1a87876e02da,listsRyujinx.Graphics.Vulkan/OpenGL and noMetal graphics project at that revision. This does not disprove a different unpublished branch/fork. Do not attribute the quoted alignment/deferred-transfer fixes to any particular current source or call them present in Husk without an exact compatible diff.

## Native Metal 4 backend

Potential mechanism:reduce host command-recording/submission/resource-management overhead with modern Metal APIs and appropriate Apple GPU synchronization. That is not automatic from a newer API version. Texture-buffer alignment and transfer-order fixes principally establish correct resources/ordering;GPU regression/API-validation passes do not measure power,frame pacing or sustained phone heat.

Husk still must implement the Android game's Vulkan API contract. If the quoted backend targets SwitchNVN/Maxwell or a RyujinxGAL interface,its command decoder,shader translation,resource lifetime and game assumptions are not a drop-in AndroidVulkan replacement. A compatible Vulkan backend upgrade or a substantial new translation backend would be needed,with present/swapchain/lifecycle/cache compatibility and original-driver rollback retained. Exact feasible scope remains input-dependent on the fork link/diff. No projected energy percentage or guaranteed improvement.

## Frame generation

Apple primary references inspected directly:
- https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatordescriptor.md
- https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase.md
- https://developer.apple.com/documentation/metalfx/mtl4fxframeinterpolator

MetalFX frame interpolation is available fromiOS/iPadOS26 in the documented API,with runtime support checks still necessary. It uses rendered color,depth,motion inputs and temporal/camera/presentation metadata. The current spatial bridge handles presentation color/dimensions;it does not export identified engine motion/depth/camera data required by the interpolation path. Anonymous Vulkan image enumeration cannot establish those semantics. Need safe game/engine integration and texture lifetimes,temporal resets after pauses/resize/cuts,HUD treatment,latency-aware presentation and correct synchronization. A color-only optical-flow/RIFE approach is a different experiment with its own extra compute/artifact/memory costs;not equivalent to validated MetalFX integration. Metal3 andMetal4 interpolation APIs exist,so a full nativeMetal4 renderer is not a prerequisite in principle.

At unchanged60real frames/sec,adding generated frames to feed a higher-refresh display adds work;it does not inherently save power. Rendering30real+30generated could reduce CPU/scene-render work enough to save energy,only if that saving exceeds interpolation/display/buffering costs. Simulation/input cadence,latency and artifacts are separate from displayed image count;30+30 does not guarantee60realFPSresponsiveness. Never silently replace the protected60realFPStarget. Any such mode must be explicit and independently reversible. Higher-refresh output also requires actual display support.

Additional history/intermediate textures and synchronization matter because E-DUO-002 ended after a4MiBmmapENOMEM. Interpolation does not repair that failed allocation or prevent shader compilation from blocking the real-frame producer. No current generated-frame/energy/temperature measurements exist;benefitUNAVAILABLE.

## Disposition / plan sequence

M3/M9/M10 sequence:verified current Vulkan+spatial path and returnedDuo memory/hitch evidence ->exact-source compatibility assessment ->only then a defined optional backend/interpolation prototype ->correctness/latency/visual/memory and matched energy acceptance. No dummy switches,guessed motion vectors,broader worker caps,driver swap,new logs or new IPA introduced. Next independent decision is exactfork/interface review;physical benefit remains unknown. Overall31.11% and existing weightedimplementation79.795918% unchanged. Documentation-only review:source inspection plusdiff/link checks;no fabricated app/device test result.


## Follow-up source investigation after user authorizes continuation

Official MeloNX heads were enumerated. A metal-renderer branch exists at4feeb3fee563fd77efa5b97f7f82053f3bff7591,dated6July2025. Its src tree11f73a2d246a9aadcba5750e4ca6097e22ee5506 contains Ryujinx.Graphics.Metal. MetalRenderer.cs blobbb87b6a49a20b111856ee40fed95ac1b45135c23 is a C# net8.0 GAL.IRenderer with Ryujinx shader-translation dependencies and MTLCommandQueue fields. It is not a Vulkan ICD that Husk can load. This is not verification of the user's quoted newerMetal4 beta,alignment fixes or deferred-transfer tests;that exact fork/link is still missing.

Also checked Mesa's actual Metal4 Vulkan candidate,not a hypothetical toggle:https://docs.mesa3d.org/drivers/kosmickrisp.html . Primary documentation explicitly describes macOS26+AppleSilicon support and says no iOS support is present. It cannot currently replace Husk's iOS MoltenVK as a packaged drop-in. An iOS port/build/interface qualification would be prerequisite work;no Android/Vulkan contract,cache orMetalFX interoperability is established from desktop conformance. No fabricated renderer option or unsafe driver replacement made. Framegeneration remains optional/prospective with identified depth/motion input dependency. Current concrete implementation work continues independently on scalableRAM without reducing protected60realFPS.
