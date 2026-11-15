# NX18-HENGE-A20-v1 — transferable mechanisms and candidate 162

15 November 2026. M3/M6/M8/M10 follow-through on the user's explicit request to adapt NX18 and Henge A20/native Metal 4 improvements for Minecraft Dungeons. Depends on the existing METAL4-FG-v1 backend and the separately prepared [ANKI-EDITOR-v1 fix](53-ankidroid-editor-ios.md). [Final verified162 build/handover](builds/a597f11bff10ce403d1b8b77f7aed0f3f2d0ba88.md) now supersedes source-only Apple gating. This remains no physical-device performance result.

## Exact reference sources

| Repository / ref | Reviewed commit | Actual execution interface |
|---|---|---|
| [kencalx/NX18](https://github.com/kencalx/NX18) main | `b545929fc230dfe529aa922f6d21686e1bb69644` | Switch NVN calls translated to native Metal 4; title-specific shaders and guest scheduling |
| [stride-praline-2f-ai/henge-](https://github.com/stride-praline-2f-ai/henge-) main | `47dced9cd3f49582ddcc1ed444617f90475d053f` | Pinned patch/manifest build repository; main alone is not the A20/Metal 4 implementation |
| Henge `feature/metal4-pipeline-efficiency` | `79fc181be5a39c56aa368f257c1a0e7cfe5a2ec6` | Native Metal 4 runtime, pipeline/archive and guest Metal replay changes in `audit-repairs.patch` |
| Henge `feature/duo-efficiency` | `343d2d84caff07b2aeff6315c77108d39efbe823` | Validated host topology, role-based QoS, guest VM/JIT/MMU work in `henge.patch` |
| Henge `feature/m4-ultra-efficiency` | `8f615e63be9a716e3c2170efe0e8c19026ad804c` | Related host/cache/Metal mechanisms and bounded work |

Reference checkouts and extracted feature patches were inspected without editing or publishing to either repository. The initial main-only Henge assessment is superseded by the feature-branch inspection above. Native Metal 4 and A20 implementations do exist there.

## Complete transfer inventory for this review

| Mechanism | Husk disposition | Remaining gate or exact boundary |
|---|---|---|
| Kernel P/E topology queried once, validated, unknown if incomplete | Added `husk-tl-host-topology.c/.h`; immutable `pthread_once` result; total/active/P/E consistency checks; cached Swift GPU/topology queries | Apple compilation and actual device sysctl availability |
| A20-aware worker allowance | Actual A20/A20 Pro GPU identity plus validated kernel split feeds the existing guarded worker policy. Retains only the prior six-core A20 Pro fallback when both counts are unavailable; malformed or unknown identities do not gain an allowance | Physical admission/rollback, responsiveness and energy; QoS is not core affinity |
| Concrete Metal 4 capabilities | Added one-time GPU-family plus real queue/compiler/allocator/residency/argument-table/shared-event admission; no command submission, shader compilation or per-frame probes | Apple API compilation/execution; successful object creation is not Dungeons rendering proof |
| Native Metal 4 rendering | Retains actual KosmicKrisp Vulkan ICD, not a renamed Metal 3 path. Fixed windowed launch forwarding of Metal 4 and frame-generation selections | Actual Dungeons correctness and lifetime tests on selected backend |
| Native queue synchronization/resource retirement | Already provided by the selected Vulkan driver; NX18 NVN and Henge PVG serialized Metal command records cannot be fed Vulkan calls | A different renderer would require a full Vulkan command/resource frontend; copying those encoders would not implement it |
| Persistent native pipeline archives | Retains bounded, compiler-contract-keyed MoltenVK archive and fallback. Henge archive ideas already overlap the existing bounded/lazy architecture | KosmicKrisp exposes no matching Husk native-descriptor/archive ABI; do not send its opaque pipeline handles into the MoltenVK bridge |
| Reuse shader libraries and precompile host shaders | Existing host shaders are built/staged; existing caches and exact-source component reuse retained | NX18's title-specific NVN shaders and Henge's replay pipeline inputs are not Android Dungeons SPIR-V inputs; no fabricated prebuilt game PSOs |
| Avoid polling and busy work | Existing predicate/condition publication parking retained; Anki close interruption repairs the confirmed blocked socket shutdown contract | NX18 backoff uses guest-register forward progress and critical-acquire-thread knowledge absent from Android `pthread_yield`; arbitrary sleeps would risk latency/deadlocks |
| Guest priority/QoS roles | Existing Dungeons critical-role protection, explicit trial admission and rollback retained | NX18 priority numbers/Henge vCPU roles differ; blindly replacing Android roles is incorrect |
| Henge EL1/MMU/JIT/TLB/timer changes | Not copied | Henge runs a macOS virtual machine; Dungeons uses Husk's Android user-code translation path, without those VM interfaces |
| MetalFX / generated frames / presentation controls | Existing independent controls retained; windowed forwarding repaired | Custom MoltenVK effects and frame-generation ABI do not operate through KosmicKrisp. Frame generation explicitly selects MoltenVK; Metal 4 never silently lowers the requested output extent |

This inventory closes the source-level applicability review. It does **not** represent a literal full port of both emulators or claim every renderer-specific improvement is active in Husk. The new code implements transferable host mechanisms around Husk's existing graphics frontend. A20 hardware identity, GPU family and API availability are queried rather than inferred from an iPhone model string. No cache schema, driver compiler contract, selected game resolution/FPS or fallback default is changed.

## Reliability and iOS feel retained in the consolidated source

Candidate 162 includes the frozen 161 socket-close repair, Java-only native glass controls and native toolbar clearance. It also preserves 160's corrected Roboto weight/italic axes and 159/160 download, WebKit, message, storage and lifecycle fixes. Native iOS chrome can improve the host controls; the Android guest view hierarchy is still AnkiDroid. No blanket claim of an iOS-native Anki rewrite is made.

The reported Add freeze has a concrete packaged-library signal failure and a passing blocked-accept regression, but no phone thread stack confirms the complete wait chain. Shared Decks testing on 160 remains active and is independent of this source preparation.

## Validation and release gates

[Local check receipt](runs/NX18-HENGE-A20-v1.local-checks.json): **77 passed, 9 Apple-only checks skipped** across the nine relevant suites; `git diff --check` passed. Portable checks execute production topology/mapping/thread-policy code and verify complete/unknown/invalid layouts, concurrent one-time initialization, actual blocked `accept()` interruption, preserved standard signals and policy behavior. Subsequent Apple Swift/Metal/WebKit/fullIPA checks passed in run43658021067 attempt3 (448tests/zero skips); initial Linux skips are preserved as local evidence, not counted as passes. Metal4 admission correctly declined the runner GPU; capable-device rendering remains unverified.

The private Husk runs `43655114047` (including one rerun) and `43655343175` fail with no runner and no steps. Both `xcode-27` and `macos-latest` were tried; the service has not provided a reason through the available tools. Public Henge Apple jobs succeeding does not establish that private Husk can allocate a runner. Do not publish private Husk source into public Henge as a workaround. After the user fixed GitHub, candidate162 attempt3 succeeded and the raw IPA was independently verified/delivered; no161 IPA was produced. Earlier failures remain in the build history.

Required next sequence:

1. On an available Apple runner: all required regression suites, extra Anki/topology/Metal tests, font paths, shaders, fresh app/helper build and package checks. Preserve exact pinned component cache keys and all extensions.
2. Independently inspect the resulting IPA identity, native symbols, driver libraries, framework DEX and retained assets before giving a raw IPA URL.
3. Short Anki check: open Add, type front/back, return; repeat preview teardown and verify host toolbar no longer covers guest actions. Preserve collections and caches.
4. Dungeons: keep chosen resolution and real FPS target; first test native Metal 4 with frame generation OFF. Evaluate A20 worker policy independently, using the existing admission/rollback evidence. Compare matched conditions before claiming efficiency. M4 evidence does not validate A20.

Readiness checklist NX18-HENGE-A20-v1 v1: source applicability inventory and transferable changes prepared; Apple build/package **passed**; device reliability **pending**; measured benefit/energy **unavailable**. Existing weighted roadmap scores receive no new credit from build-only evidence. This is not whole-plan or full-emulator completion.
