#!/usr/bin/env bash
# cargo build --release で作ったプラグインを、juiz broker install で入れられるアーカイブにする
# (docs/spec/broker-plugin-abi.md §10.1・§10.2、OpenJUIZ/juiz の docs/spec/)。
#
#   juiz_broker-zenoh-<版>-abi<N>-<ターゲット>.tar.gz (Windows のターゲットは .zip) と .sha256
#
# 中身は先頭にディレクトリを置かずに juiz-broker.json・lib/<ライブラリ>・LICENSE-MIT・LICENSE-APACHE・README.md。
# ABI の版はライブラリの中の印 juiz_broker_abi=<N>; から読む。版は Cargo.toml の version。
#
# 使い方: scripts/package.sh <ターゲット> [出力先 (既定 dist)]
#   ターゲットは x86_64-unknown-linux-gnu・aarch64-unknown-linux-gnu・x86_64-apple-darwin・
#   aarch64-apple-darwin・x86_64-pc-windows-msvc のどれか。ホストでビルドしたものを詰める (クロスビルドはしない)
# 作ったアーカイブのパスを標準出力に出す。
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <target> [out_dir]" >&2
    exit 2
fi
target="$1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${2:-$root/dist}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
cd "$root"

case "$target" in
    x86_64-unknown-linux-gnu | aarch64-unknown-linux-gnu) lib_file=libjuiz_zenoh_broker.so; ext=tar.gz ;;
    x86_64-apple-darwin | aarch64-apple-darwin) lib_file=libjuiz_zenoh_broker.dylib; ext=tar.gz ;;
    x86_64-pc-windows-msvc) lib_file=juiz_zenoh_broker.dll; ext=zip ;;
    *)
        echo "error: unknown target '$target'" >&2
        exit 2
        ;;
esac

version="$(sed -n 's/^version *= *"\(.*\)"/\1/p' Cargo.toml | head -n 1)"
lib="${CARGO_TARGET_DIR:-$root/target}/release/$lib_file"
if [ ! -f "$lib" ]; then
    echo "error: $lib is not found. Run 'cargo build --release' first" >&2
    exit 1
fi
abi="$(LC_ALL=C grep -ao 'juiz_broker_abi=[0-9][0-9]*;' "$lib" | head -n 1 | sed 's/[^0-9]//g')"
if [ -z "$abi" ]; then
    echo "error: $lib has no broker ABI marker (juiz_broker_abi=<N>;)" >&2
    exit 1
fi

name="juiz_broker-zenoh-$version-abi$abi-$target.$ext"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/lib"
cp "$lib" "$stage/lib/$lib_file"
cp LICENSE-MIT LICENSE-APACHE README.md "$stage/"
cat > "$stage/juiz-broker.json" <<JSON
{
  "format": 1,
  "type_name": "zenoh",
  "plugin_name": "juiz_zenoh_broker",
  "version": "$version",
  "abi_version": $abi,
  "target": "$target",
  "library": "lib/$lib_file"
}
JSON

rm -f "$out/$name" "$out/$name.sha256"
files=(juiz-broker.json lib LICENSE-MIT LICENSE-APACHE README.md)
if [ "$ext" = zip ]; then
    # Windows の Git Bash には zip が無いことがあるので Python で作る
    # Windows の python3 は Microsoft Store のスタブのことがあるので python を使う
    py=python3
    case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) py=python ;; esac
    (cd "$stage" && "$py" - "$out/$name" "${files[@]}" <<'PY'
import os, sys, zipfile
dest, names = sys.argv[1], sys.argv[2:]
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
    for n in names:
        if os.path.isdir(n):
            for d, _, fs in os.walk(n):
                for f in sorted(fs):
                    p = os.path.join(d, f)
                    z.write(p, p.replace(os.sep, "/"))
        else:
            z.write(n, n)
PY
    )
else
    tar -C "$stage" -czf "$out/$name" "${files[@]}"
fi

if command -v sha256sum > /dev/null 2>&1; then
    hash="$(cd "$out" && sha256sum "$name" | cut -d' ' -f1)"
else
    hash="$(cd "$out" && shasum -a 256 "$name" | cut -d' ' -f1)"
fi
printf '%s  %s\n' "$hash" "$name" > "$out/$name.sha256"
echo "$out/$name"
