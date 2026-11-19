# JIT-aware native wait parking for Minecraft Dungeons (JIT-CPU-WAIT-v1)

Date: 19 November 2026. Branch: `feature/apple-native-metalfx-rebuild`.
Status: **source committed; Apple build/device energy unverified**.

## Evidence and mechanism

Minecraft Dungeons is native ARM64/UE4 in the translation-layer runtime.
The iOS executable memory/JIT/bootstrap region is acquired at launch and is
not itself a continuously executing worker. Reducing its size or disabling
JIT does not reliably reduce battery drain and may break the large game.

The native Bionic compatibility code in
`src/translation-layer-next/husk-tl-bionic-pthread.c` has two real
contention loops:

- Lazy pthread object initialisation when another thread observes `MAGIC_INIT`.
- `pthread_once` while the first thread runs the initializer.

The old default uses repeated `sched_yield()`, potentially consuming CPU
while the other thread works. Husk already implements a predicate-checked,
hashed condition-variable wait in `husk-tl-publication-wait.c`; it preserves
publication ordering, rechecks predicates, and handles collisions, cancellation
and fallback. Its 8 concurrency/race regression cases are existing coverage.

## Change

- `TLAppSettings.dungeonsJITLowPowerWait = true` by default, with per-game
  JSON persistence and old-settings migration.
- `effectiveExecution(for:)` enables `initializationParking` *only*
  for an identified UE4 Dungeons game. Unrelated UE4, Unity and other apps
  retain existing settings and their original opt-in experiments.
- Advanced > Graphics & Memory:
  **Park idle native JIT waits** toggle provides immediate saved opt-out;
  actual launch needs a complete game restart.
- `TLUnityView` passes the effective setting into the already-existing
  native `husk_ue4_set_initialization_parking()` before game threads begin.
  Duo automatic profile reset preserves this independent CPU wait setting
  when it clears GPU command-buffer experiments.
- Existing native JIT allocator, code pages, AOT conversion, app signatures,
  game data, spatial MetalFX and **60 real FPS request** remain untouched.
  This is a contention-path optimization, not a JIT-less conversion.

## Validation and decision gates

The source regression cases in `test_duo_automatic.py` and
`test_settings_grouping.py` now assert Dungeons-only admission, persistence,
manual opt-out, and unaffected 60 FPS. The native
`test_publication_wait.py` exercises the actual C sleep/notification
implementation (once, object, races, collision, cancellation and fallback).
Full Mac tests/Apple SDK build, IPA signing and device tests remain pending.

No evidence yet proves that enough foreground time is spent in these
initialization waits to materially improve overall battery life. Measure
source activity, native waiting counters, p95 frame time and actual
energy/heat over matched 60 FPS sessions. If launch or frame cadence regresses,
switch this setting OFF and fully restart Dungeons.

## Next

Run 52 required Mac suites and IPA build; verify actual native parking
admission, no startup hang, stable foreground 60 FPS and unchanged lifecycle.
Then compare matching scenes and conditions with parking ON/OFF. Do not infer
mAh or electrical power savings from using a condition variable alone.
