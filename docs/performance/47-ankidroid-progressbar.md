# ANKI-PROGRESS-v1 — Material progress indicator compatibility

User report received14November2026, Husk3.4/build155, iPhone19,4/iOS27.3, AnkiDroid2.25.3-full-universal/com.ichi2.anki. This follows COMPAT-ANKI-v1's previously untested compatibility assessment and HOME-LAUNCH-v1; next gate is completing the original button action with the repaired framework. No performance milestone acceptance follows from an app launching.

## Observed result and cause

USER-REPORTED: Java/DEX and native librsdroid load, collection.anki2 opens, introduction screens render and receive a tap. The deck picker's SyncActionProvider then inflates res/RS1.xml line33/LinearProgressIndicator. Main-thread InflateException is caused by ColorDrawable→sv3 ClassCastException in the Material covariant getIndeterminateDrawable getter. Stack: ProgressBar constructor→refreshProgress→Material invalidate→getCurrentDrawable→getIndeterminateDrawable. About5.6GiB available-before-jetsam is reported near the rendered introduction; no ENOMEM or jetsam termination appears here. This is a caught Java UI failure, not evidence of the earlier Dungeons memory crash. The user's exact button identity and whether other features work remain unknown.

SOURCE-CONFIRMED: Husk's getter manufactured a transparent ColorDrawable when no indeterminate drawable existed. Android's getter returns the actual nullable field. Material's getter casts it to its own IndeterminateDrawable subtype; null is allowed. Additionally, base construction dispatched invalidate into an incompletely initialized subclass.

The earlier WindowManagerGlobal/LeakCanary warning, unresolved unwind imports and libcore IOException remain visible limitations. None is the terminal exception in this report; this patch does not claim to fix them. Native backend initialization/database opening is evidence of partial operation, not verified import/sync/study/audio support. Changing APK ABI/universal packaging would not repair this framework contract.

## Implementation and verification

ProgressBar no longer manufactures an unrelated drawable. It preserves a real themed drawable; explicit replacement/null clearing replaces the theme fallback too. Initialization refreshes levels but defers overridable invalidation until the base constructor finishes. Normal progress invalidation remains active. Real themed spinner drawing behavior is preserved.

Actual production widget bytecode is exercised on a host JVM, with facades only for the native window/resource/clock boundary. A covariant Material-like getter/invalidate reproduces the original ClassCastException at the same refreshProgress/constructor path. Fixed source passes10 assertions covering null semantics, typed identity/replacement/clear, real theme retention/clear, no subclass refresh during construction, and runtime progress level/invalidation. This is a component regression, not running the actual AnkiDroid APK on iOS.

The entire handwritten/generated Java framework is compiled with JDK21 --release8, then pinned R8/D8 8.5.35/minAPI26 generates both full/core DEX. CI now explicitly rebuilds that framework after staging pinned3.4 native runtime resources; packaging copies and compares the rebuilt runtime, preventing stale donor DEX from hiding the fix. A source/DEX hash receipt ships with the app. All prior RAM/MetalFX/framegen/Metal4/A20/audio/lifecycle/cache/Home Screen routing code remains unchanged. Build156 changes only this Java compatibility repair, its build/verification path and version metadata.

ANKI-PROGRESS-v1 gates: I1 source/old-failure regression; I2 fresh full/core DEX; I3 clean Apple build/package; I4 independently downloaded DEX/source verification. Current local I1/I2 passed2/4=50%, Apple/package pending. D1 original button completes; D2 deck list/basic study/Home Screen launch,0/2=0%. Energy benefit UNAVAILABLE; no energy optimization claimed or gate awarded. Existing HUSK-ROADMAP-v1 accepted31.11% and I79.795918% unchanged; M4-only34.5667%, Duo whole-milestone acceptance0.

Candidate install: update existing slot using the same identity/all extensions, preserve collection/saves/cache, close/reopen and enable usual JIT. Retry the original button once; no general long playthrough/log collection required. If it fails, use Husk's existing app report and preserve collection data; return to verified155 for unrelated working games if necessary. Actual AnkiDroid operation beyond this failure remains pending.
