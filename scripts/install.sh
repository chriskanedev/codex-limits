#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
product_name="Codex Limits"
executable_name="CodexLimits"
build_app="$repo_root/.build/$product_name.app"
install_root="$HOME/Applications"
installed_app="$install_root/$product_name.app"

cd "$repo_root"
swift build -c release --arch arm64

rm -rf "$build_app"
mkdir -p "$build_app/Contents/MacOS"
cp "$repo_root/.build/arm64-apple-macosx/release/$executable_name" "$build_app/Contents/MacOS/$executable_name"
cp "$repo_root/Resources/Info.plist" "$build_app/Contents/Info.plist"
codesign --force --deep --sign - "$build_app"

mkdir -p "$install_root"
osascript -e 'tell application id "com.chriskane.codexlimits" to quit' >/dev/null 2>&1 || true

backup_dir="$(mktemp -d /tmp/codex-limits-install.XXXXXX)"
restore_needed=false
if [[ -d "$installed_app" ]]; then
    mv "$installed_app" "$backup_dir/$product_name.app"
    restore_needed=true
fi

if ditto "$build_app" "$installed_app"; then
    rm -rf "$backup_dir"
else
    if [[ "$restore_needed" == true ]]; then
        mv "$backup_dir/$product_name.app" "$installed_app"
    fi
    rmdir "$backup_dir" 2>/dev/null || true
    exit 1
fi

open "$installed_app"
for _ in {1..20}; do
    if pgrep -x "$executable_name" >/dev/null; then
        echo "Installed and running: $installed_app"
        exit 0
    fi
    sleep 0.25
done

echo "Installed, but the app did not remain running: $installed_app" >&2
exit 1
