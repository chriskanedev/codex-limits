#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
product_name="Codex & Claude Limits"
executable_name="CodexLimits"
build_root="$HOME/Library/Caches/com.chriskane.codexlimits/build"
build_app="$build_root/$product_name.app"
install_root="$HOME/Applications"
installed_app="$install_root/$product_name.app"
legacy_app="$install_root/Codex Limits.app"

cd "$repo_root"
# Keep generated bundles outside file-provider folders (for example iCloud
# Documents), whose Finder metadata can make code signing fail.
swift build -c release --arch arm64 --scratch-path "$build_root"
bin_dir="$(swift build -c release --arch arm64 --scratch-path "$build_root" --show-bin-path)"

rm -rf "$build_app"
mkdir -p "$build_app/Contents/MacOS"
cp "$bin_dir/$executable_name" "$build_app/Contents/MacOS/$executable_name"
cp "$repo_root/Resources/Info.plist" "$build_app/Contents/Info.plist"
codesign --force --deep --sign - "$build_app"

mkdir -p "$install_root"
if pgrep -x "$executable_name" >/dev/null; then
    pkill -x "$executable_name"
    for _ in {1..20}; do
        pgrep -x "$executable_name" >/dev/null || break
        sleep 0.25
    done
    if pgrep -x "$executable_name" >/dev/null; then
        echo "Quit Codex & Claude Limits before installing the update." >&2
        exit 1
    fi
fi

backup_dir="$(mktemp -d /tmp/codex-limits-install.XXXXXX)"
restore_needed=false
if [[ -d "$installed_app" ]]; then
    mv "$installed_app" "$backup_dir/$product_name.app"
    restore_needed=true
fi

if ditto "$build_app" "$installed_app"; then
    # Same bundle identity preserves Launch at Login and preferences. Retire
    # the old display name only after the replacement has copied successfully.
    if [[ -d "$legacy_app" ]]; then
        mv "$legacy_app" "$backup_dir/Codex Limits.app"
    fi
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
