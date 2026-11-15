# M9-FG-LEASE-v1 — four-frame Metal4 launch freeze

15 November 2026. Build165/source62689726af641a121d72a17346cabcdb9eb10507-dirty is positively identified in the supplied current-run header on iPhone19,4/iOS27.3. This follows the source Metal4/colour-flow implementation in58 and blocks its device acceptance. Preserve the currently working frame-generation-OFF route, all data/caches/resolution, original drivers, thermal safeguards and separate experiments.

## Returned evidence and scope

The first supplied session explicitly selects HuskKosmicKrisp, Metal4Enhancements and frame generation, with1816×1280 output and30realFPS requested. The render counter reaches exactly4, then remains4 through~73.5seconds of heartbeat sampling. JIT self-test executed42; main OBB is present; audio starts, no fatal/OOM is reported and at least~4.6GiB reported headroom remains. These are positive launch observations, not GPU execution measurements. Pause1 completes/saves5,047,656Vulkan-cache bytes; resume2 begins without completion. The freeze predates that background interruption.

The user confirms that switching frame generation OFF runs. The second pair of logs still selects the same source Metal4 enhancements at1816×1280, now60requested/FGfalse, and reaches1529frames. Pause/resume1/2 complete and rendering resumes; detach/pause3 completes. The cache restores5,047,656compatible bytes/accepted seed, then saves5,740,672and13,600,458bytes. Host summary windows55.9/56.6FPS include pipeline work; these are not displayed60FPS or proof of native archive hits/energy benefit. Scene/images/input/audio beyond the user's 'runs' statement remain unmeasured. This positive control isolates the new combined framegen boundary; it does not validate FG-on.

The [kk-wsi] present trace's1819×1280 comes from bounds×contentsScale (`wsi_metal_layer_size`); actual drawable/swapchain logs both1816×1280. It is not proof of an actual drawable mismatch. No resolution/quality workaround is applied. Worker trial logs are waiting for healthy baseline/pipeline cost, not evidence that extra caps caused the four-frame stop. Optional missing patchOBB/JNI notices are present on the running FG-OFF path too.

## Source-confirmed ownership defect and repair

`huskFramegenDrawable` returns an autoreleased offscreen lease. Build165's new C/Objective-C boundary retained it for WSI without creating/draining a local autorelease pool. The Vulkan/game loop can have no pool or a pool lasting its whole thread. Even after producer feedback, consumer/history and WSI release their references, the autorelease reference can keep each lease alive. Slots become reusable only in lease dealloc; all four fill and acquisition waits forever. This explains the observed four-frame cutoff and can obstruct engine resume waiting on rendering. Exact thread stacks/GPU completion traces were not supplied, so the returned log alone does not prove every internal blocking stack.

The new acquire bridge wraps creation and its +1 WSI retain in a scoped `@autoreleasepool`. The pool drains before returning the caller's owned reference. WSI still owns one reference; producer feedback and GPU consumer blocks continue retaining their leases until actual completion. No early release, reuse before GPU completion, larger pool, CPU-present-as-completion, busy polling, forced FPS/quality change or hidden feature removal.

The actual bridge component test now reproduces the old retain/autorelease boundary inside one long-lived outer pool: after four caller releases, all slots remain occupied and acquisition returnsnil. Draining that outer pool frees them. The repaired real C entrypoint then completes32producer-feedback/history-retirement/WSI-release cycles inside the same long-lived outer pool; every slot must return after each iteration. Existing CPU-present prohibition, GPU-error, epoch cancellation and exact-once callback tests remain. Metal protocol doubles establish ownership, not physical GPU output. Apple-only check must pass with full app/driver/package before delivery.

## Checklist and next gate

M9-FG-LEASE-v1 checklist1: I1 ownership repair/review; I2 actual Apple old-boundary reproduction and repaired32-cycle test; I3 full source driver/app/extension/sign/package and independent raw delivery. Device D1 FG-on launch advances past4frames with correct images/input/audio, D2 one normal pause/resume without pool starvation. E1 sustained latency/quality/energy acceptance staysUNKNOWN. No fixed whole-roadmap gate is credited from a compile or this short positive control.

FG OFF remains the immediate165 workaround. After a verified166IPA, only a30–60second same-settings FG-on launch plus one pause/resume is needed. No repeat archive campaign/cache deletion or general benchmark. Confirm continued frame progress, sourceMetal4/FGactive with no failure/errors, visible images and controls/audio; stop FG and restart if stuck/corrupt. The normal30rendered→60output distinction remains.


## Final166 gates

[Verified build/handover](builds/eacafb426fc73fcf02e9b07103dd4c7f342f3ddf.md): Apple43702777875/job132777309996 passed461test executions/60invocations/zero test skips; old-boundary reproduction and repaired32-cycle actual bridge test passed twice, full49-suite/font/SDK/10setupgroups passed, new sourceMetal4/app/three extensions/sign/package pass. Independent package confirms current source/code/patch hashes and unchanged compiler contract, original driver/Anki/fonts/helper retention and full773regular notice set. Raw154255997byteIPA SHA256`19fa2fbcb3779929ec5db13341e4d7251b5c98f1d0dfb6bb629f39546183dbe1`; full anonymous download matches. ScopeI3/3=100%, repairedD0/2, E0/1UNKNOWN. Fixed global31.11/I79.795918/M4scope34.5667/Duo0 unchanged. Positive165FGoffcontrol is preserved; actual166FGonverification remains required.
