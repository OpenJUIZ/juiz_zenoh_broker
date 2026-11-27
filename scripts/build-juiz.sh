#!/usr/bin/env bash
# テストと確かめの相手にする juiz コマンドと例のプラグインを、juiz のソースからビルドする。
#
# - juiz のソースは juiz-rev.txt の rev を .juiz/ に取ってくる。JUIZ_SRC があればそのチェックアウトを使う (rev は確かめない)
# - ビルド先は CARGO_TARGET_DIR (無ければこのリポジトリの target)。このリポジトリのプラグインと同じ置き場所になる
# - 引数は cargo build に渡す (--release を付けると target/release に置かれる)
#
# 使い方: scripts/build-juiz.sh [cargo build の引数]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

rev="$(tr -d ' \r\n' < juiz-rev.txt)"
# Cargo.toml の juiz の rev は juiz-rev.txt と同じでなければならない (テストの juiz_core と相手の juiz をそろえる)
if grep -F 'git = "https://github.com/OpenJUIZ/juiz"' Cargo.toml | grep -vqF "rev = \"$rev\""; then
    echo "error: the juiz rev in Cargo.toml differs from juiz-rev.txt ($rev)" >&2
    exit 1
fi

if [ -n "${JUIZ_SRC:-}" ]; then
    juiz_src="$(cd "$JUIZ_SRC" && pwd)"
else
    juiz_src="$root/.juiz"
    if [ "$(git -C "$juiz_src" rev-parse HEAD 2>/dev/null || true)" != "$rev" ]; then
        echo "==> juiz $rev を .juiz/ に取ってくる" >&2
        if [ ! -d "$juiz_src/.git" ]; then
            git init -q "$juiz_src"
            git -C "$juiz_src" remote add origin https://github.com/OpenJUIZ/juiz
        fi
        git -C "$juiz_src" fetch -q --depth 1 origin "$rev"
        git -C "$juiz_src" checkout -q --detach FETCH_HEAD
    fi
fi

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$root/target}"
echo "==> juiz コマンドと例のプラグインをビルドする ($juiz_src → $CARGO_TARGET_DIR)" >&2
cargo build "$@" --manifest-path "$juiz_src/Cargo.toml" \
    -p juiz_app -p increment_process -p example_container -p example_container_get \
    -p example_container_increment -p timer_ec
