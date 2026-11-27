#!/usr/bin/env bash
# 作ったアーカイブを juiz broker install --from で入れ、conf に type_name: zenoh を書くだけで使えることを確かめる
# (docs/spec/broker-plugin-abi.md §10.4)。
#
#   1. juiz broker install zenoh --from <アーカイブ> (隣の .sha256 で照合される)
#   2. juiz broker list で used と出る
#   3. conf の brokers に type_name: zenoh を書いた juiz を立て、置き場所から読んだログを確かめる
#   4. conf なしの juiz -s zenoh://… で Process を呼べる (クライアントも置き場所から読む)
#   5. juiz broker remove zenoh
#
# 置き場所は一時ディレクトリ (JUIZ_BROKER_HOME) にするので、手元の ~/.juiz/brokers は触らない。
#
# 使い方: scripts/check-install.sh <アーカイブ> <juiz と increment_process のあるディレクトリ> [ポート (既定 7458)]
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "usage: $0 <archive> <juiz_bin_dir> [port]" >&2
    exit 2
fi
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
bin_dir="$(cd "$2" && pwd)"
port="${3:-7458}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$root/Cargo.toml" | head -n 1)"

windows=false
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) windows=true ;; esac
juiz="$bin_dir/juiz"
if $windows; then juiz="$bin_dir/juiz.exe"; fi

work="$(mktemp -d)"
server=""
cleanup() {
    if [ -n "$server" ]; then
        kill "$server" 2> /dev/null || true
        if $windows; then taskkill //F //IM juiz.exe > /dev/null 2>&1 || true; fi
    fi
    rm -rf "$work"
}
trap cleanup EXIT

# conf や juiz に渡すパスは Windows でも / 区切りにする
native() {
    if $windows && command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

export JUIZ_BROKER_HOME="$(native "$work/brokers")"
export RUST_BACKTRACE=0

echo "==> juiz broker install zenoh --from $archive"
out="$("$juiz" broker install zenoh --from "$(native "$archive")" 2>&1)"
echo "$out"
echo "$out" | grep -qF "installed zenoh broker $version (juiz_zenoh_broker, broker ABI "

echo "==> juiz broker list"
out="$("$juiz" broker list 2>&1)"
echo "$out"
echo "$out" | grep -E "^zenoh" | grep -F "$version" | grep -q "used"

echo "==> juiz with 'type_name: zenoh' in the conf (port $port)"
cat > "$work/server.conf" <<CONF
name: zenoh_install_check
option:
  http_broker:
    start: false
plugins:
  process_factories:
    increment_process: { path: "$(native "$bin_dir")" }
brokers:
  - { type_name: zenoh, host: 127.0.0.1, port: $port }
processes:
  - { type_name: increment_process, name: inc0 }
CONF
RUST_LOG=info "$juiz" -f "$(native "$work/server.conf")" -d > "$work/server.log" 2>&1 &
server=$!

host="zenoh://127.0.0.1:$port"
ok=false
for _ in $(seq 1 60); do
    if out="$("$juiz" -s "$host" process call "$host/process/inc0::increment_process" '{"arg1": 2}' -p 2>&1)" \
        && echo "$out" | grep -q "Value(3)"; then
        ok=true
        break
    fi
    sleep 1
done
if ! $ok; then
    echo "error: process call over zenoh did not succeed: $out" >&2
    echo "--- server log" >&2
    cat "$work/server.log" >&2
    exit 1
fi
echo "$out"
if ! grep -qF "(installed juiz_zenoh_broker $version, C ABI) Loaded" "$work/server.log"; then
    echo "error: the server did not load the installed broker" >&2
    cat "$work/server.log" >&2
    exit 1
fi
echo "the server loaded the installed broker and answered over zenoh"

kill "$server" 2> /dev/null || true
if $windows; then taskkill //F //IM juiz.exe > /dev/null 2>&1 || true; fi
wait "$server" 2> /dev/null || true
server=""

echo "==> juiz broker remove zenoh"
"$juiz" broker remove zenoh
test ! -e "$work/brokers/zenoh"
echo "ok"
