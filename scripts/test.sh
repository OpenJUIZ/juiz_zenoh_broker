#!/usr/bin/env bash
# このリポジトリのテストを、手元と CI で同じ手順で実行する。
#
# テストはブローカー共通のスイート juiz_broker_suite (juiz の brokers/broker_suite、git の依存) で、
# juiz コマンドと例のプラグイン (increment_process など) を相手にする。それらは juiz のソースからビルドする。
#
#   1. juiz コマンドと例のプラグインを、このリポジトリと同じ target/debug にビルドする (scripts/build-juiz.sh)
#   2. プラグイン libjuiz_zenoh_broker (cdylib) をビルドする
#   3. cargo test (固定のポート 5212〜5254 などを使うので --test-threads=1)
#
# テストは JUIZ_BROKER_SUITE_TARGET_DIR (= target/debug) から juiz と例のプラグインを読む。
#
# 使い方:
#   scripts/test.sh                       # すべて
#   scripts/test.sh --verbose             # cargo に渡す引数 (debug ビルドのまま使うこと)
#   JUIZ_SRC=../juiz scripts/test.sh      # 手元の juiz のチェックアウトを使う
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$root/target}"
export JUIZ_BROKER_SUITE_TARGET_DIR="$CARGO_TARGET_DIR/debug"

scripts/build-juiz.sh "$@"

printf '\n==> %s\n' "プラグイン libjuiz_zenoh_broker をビルドする"
cargo build "$@"

printf '\n==> %s\n' "テスト"
cargo test "$@" -- --test-threads=1
