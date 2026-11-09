#!/bin/bash
# Tools/dependencies stay inside the runner's own cache, without sudo or user shell/profile changes.
set -euo pipefail
TASK_CACHE="${RUNNER_TOOL_CACHE:-$RUNNER_TEMP}/husk"
mkdir -p "$TASK_CACHE"
TASK_CORES=$(sysctl -n hw.logicalcpu)
TASK_RAM=$(sysctl -n hw.memsize)
TASK_JOBS=$(python3 -c 'import sys; print(max(1,min(int(sys.argv[1]),max(1,int(sys.argv[2])//(2*1024**3)),6)))' "$TASK_CORES" "$TASK_RAM")
export CARGO_BUILD_JOBS="$TASK_JOBS"
printf 'HUSK_XCODE_JOBS=%s\nCARGO_BUILD_JOBS=%s\n' "$TASK_JOBS" "$TASK_JOBS" >> "$GITHUB_ENV"
echo "Mac build concurrency: $TASK_JOBS jobs"
mkdir -p "$TASK_CACHE/rppairing-target"
if [ ! -e src/rppairing-ios/target ]; then ln -s "$TASK_CACHE/rppairing-target" src/rppairing-ios/target; fi
echo "HUSK_TOOL_CACHE=$TASK_CACHE" >> "$GITHUB_ENV"
export CARGO_HOME="$TASK_CACHE/cargo" RUSTUP_HOME="$TASK_CACHE/rustup"
if [ ! -x "$CARGO_HOME/bin/rustup" ]; then
    curl --proto '=https' --tlsv1.2 --fail --location --retry 3 https://sh.rustup.rs --output "$TASK_CACHE/rustup-init.sh"
    sh "$TASK_CACHE/rustup-init.sh" -y --no-modify-path --profile minimal --default-toolchain stable
fi
export PATH="$CARGO_HOME/bin:$PATH"
rustup toolchain install stable --profile minimal
rustup target add aarch64-apple-ios --toolchain stable
printf 'CARGO_HOME=%s\nRUSTUP_HOME=%s\nRUSTUP_TOOLCHAIN=stable\n' "$CARGO_HOME" "$RUSTUP_HOME" >> "$GITHUB_ENV"
echo "$CARGO_HOME/bin" >> "$GITHUB_PATH"
XCODEGEN_PIN=21ac9944b0ab546a07422dbed86f33dd2ebd76f8
XCODEGEN="$TASK_CACHE/xcodegen-$XCODEGEN_PIN"
if [ ! -d "$XCODEGEN/.git" ]; then
    git init "$XCODEGEN"
    git -C "$XCODEGEN" remote add origin https://github.com/yonaskolb/XcodeGen.git
    git -C "$XCODEGEN" -c http.https://github.com/.extraheader= fetch --depth 1 origin "$XCODEGEN_PIN"
    git -C "$XCODEGEN" checkout --detach FETCH_HEAD
fi
test "$(git -C "$XCODEGEN" rev-parse HEAD)" = "$XCODEGEN_PIN"
if [ ! -x "$XCODEGEN/.build/release/xcodegen" ]; then
    xcrun swift build --package-path "$XCODEGEN" --configuration release --product xcodegen --jobs "$TASK_JOBS"
fi
echo "$XCODEGEN/.build/release" >> "$GITHUB_PATH"
# Only Vulkan headers are needed to re-check the host observer ABI; the verified driver itself is unchanged.
VK_PIN=e3b1eec08173d6b825cd3ac88c885a63b621504a
VK_HEADERS="$TASK_CACHE/vulkan-headers-$VK_PIN"
if [ ! -d "$VK_HEADERS/.git" ]; then
    git init "$VK_HEADERS"
    git -C "$VK_HEADERS" remote add origin https://github.com/KhronosGroup/Vulkan-Headers.git
    git -C "$VK_HEADERS" -c http.https://github.com/.extraheader= fetch --depth 1 origin "$VK_PIN"
    git -C "$VK_HEADERS" checkout --detach FETCH_HEAD
fi
test "$(git -C "$VK_HEADERS" rev-parse HEAD)" = "$VK_PIN"
mkdir -p third_party/build/mvk-abi/External
ln -s "$VK_HEADERS" third_party/build/mvk-abi/External/Vulkan-Headers
python3 scripts/verify_vulkan_observer_abi.py third_party/build/mvk-abi --ios
