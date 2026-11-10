# E-DUO-002 — returned A20 worker trial and allocation failure

2026-11-10. Source: user's inline native output in this conversation; no original file/hash, build header, wall-clock duration or OS incident supplied. Mode4/two-worker allowance/VA-age fields match recent build152, but this excerpt alone does not stamp exact binary identity. Do not mix this crash with the earlier M4 startup fault or diagnose the optional patch OBB as missing required data.

Sequence M10/M7/M1 -> returned trial/rollback and terminal mapping failure -> memory compatibility/resource fixes and M8 bounded reserve candidate. Preserve excellent reported visuals,1816x1280 output/1448x1024 guest,60FPS,cache/audio/V4/lifecycle and protected M4 reference.

## Observations from the supplied output

- MEASURED by host log: Apple A20Pro renderer,6CPUs; Sharp/Efficient,Driver Default,synchronous submission;1448x1024 actual guest swapchain and1816x1280 drawable. This is Vulkan -> MoltenVK -> Metal; ANGLE also initializes ES-over-Metal. Neither guest dimensions nor configured scaler request alone proves every MetalFX encode executed.
- Cache seed3910481bytes restored/accepted,matching E-DUO-001's pause save. That is persistence/acceptance,not verified hits.341 pipeline calls before trial;363 near the end. New pipelines still include648.296ms worst call and3410.846ms aggregate in one window; host durations can overlap and do not measure GPU/energy. Worst cadence interval921.88ms. Pipeline creation is a real hitch source; cache corruption is not established. Do not clear it.
- Host cadence51.9–60FPS; long stretches60; thermal classification0/LPM0. No watts,battery slope,numerical temperature,physical display timing or CPU-core residency. Nominal thermal does not invalidate user's felt heat.
- Admission occurs near13814frames: NP0/1 stayDefault0x15; NP2/3 actually changeDefault -> Utility0x11,rc0. Render/RHI/audio/high-priority/unknown workers preserved. At next window58.9FPS,p95 20.49ms,max24.39ms,controller requests Balanced and NP2/3 actually restore0x15,rc0. This validates observed application/restoration; it does not prove efficiency-core residence,benefit,or causality of all cadence variation. Later cadence remains below60 at times after restoration.
- VM monitoring ages increase toward30seconds and refresh; low-headroom periods trigger shorter refresh. The implemented reduction in VM-walk frequency is visible,not a measurement of saved battery.
- MappedVA6.5–7.1GiB is not physical footprint. Anonymous guest part~0.9–1.0GiB after loading. Early minimum reported additional process headroom482MiB; later snapshots roughly500–760MiB. Last reported values645/665MiB do not guarantee the next mapping succeeds.
- Terminal evidence: `mm: mmap FAILED len=0x400000 prot=3 flags=0x22 errno=12`, immediately followed by SIGSEGV,fault0x40000,libUE4.so+0x8816838.4MiB private anonymous RW request failed; no adjacent TL_MM artificial-limit refusal. Address-space cap/fragmentation,real allocation pressure or other mapping constraints remain unresolved. This is not a recorded jetsam kill. No matching APK/library/symbol map exists here to resolve that UE4 offset further.
- Main OBB2937151339bytes found inside APK. Optionalpatch42 warning precedes>16000frames; does not explain terminal failure. Xbox connected. No lifecycle interruption shown in tail.

## Consequences

Treat152 as a returned functional regression until allocation resilience is checked; retain build151 rollback and original evidence. Worker actual application/rollback is new scoped evidence,not whole M7 acceptance because sustained stability and energy remain unmet. No whole-roadmap score change. No new general logging/playthrough request.

The next candidate fixes confirmed false memory reporting and VM object-port leaks; independently adapts MeloNX2.7 donor mechanism; retains Balanced for the rest of a launch after an admitted relative trial fails its cadence guard. None is labeled a proven root-cause fix or measured cooling gain. See [memory design](../43-memory-resilience.md).
