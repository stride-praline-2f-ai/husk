#!/bin/bash
# Rebuild the Android stand-in framework; never silently ship the release donor's stale DEX.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export HUSK_JDK="${HUSK_JDK:-${JAVA_HOME:?Set JAVA_HOME or HUSK_JDK to a full JDK}}"
JAVA_CACHE="${HUSK_TOOL_CACHE:-$ROOT/build/tool-cache}/java-framework"
mkdir -p "$JAVA_CACHE" build/java-runtime
export HUSK_D8="$JAVA_CACHE/r8-8.5.35.jar"
R8_SHA=cb112407ef132dfcb1e5e1a9d4e6fefa89807822e65a9ffbdbb68ee442985405
if [ ! -s "$HUSK_D8" ]; then
    curl --fail --location --retry 3 https://storage.googleapis.com/r8-releases/raw/8.5.35/r8.jar --output "$HUSK_D8.partial"
    mv "$HUSK_D8.partial" "$HUSK_D8"
fi
python3 - "$HUSK_D8" "$R8_SHA" <<'PY'
import hashlib,sys
from pathlib import Path
if hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()!=sys.argv[2]:
    raise SystemExit('Pinned R8 checksum mismatch')
PY
DONOR=build/graphics-base/Payload/Husk.app/java-runtime
test -s "$DONOR/husk-framework.dex"
cp -R "$DONOR/." build/java-runtime/
export HUSK_JAVA_TEST_CLASSES="$ROOT/build/java-framework-test-classes"
rm -rf "$HUSK_JAVA_TEST_CLASSES"
bash src/java-framework/build.sh "$ROOT/build/java-runtime/husk-framework.dex"
python3 tests/java-framework/run_progress_bar.py "$HUSK_JAVA_TEST_CLASSES"
python3 - <<'PY'
import hashlib,json
from pathlib import Path
root=Path('build/java-runtime')
files=['husk-framework.dex','husk-framework-core.dex']
receipt={'schema':1,'r8':'8.5.35','min_api':26,'regression':'ProgressBarContract:10 checks',
         'files':{f:{'bytes':(root/f).stat().st_size,'sha256':hashlib.sha256((root/f).read_bytes()).hexdigest()}for f in files},
         'progressbar_source_sha256':hashlib.sha256(Path('src/java-framework/src/android/widget/ProgressBar.java').read_bytes()).hexdigest()}
(root/'husk-framework-build.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
PY
