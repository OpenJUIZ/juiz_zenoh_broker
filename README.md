# juiz_zenoh_broker

[JUIZ](https://github.com/OpenJUIZ/juiz) の Zenoh ブローカーです。[Zenoh](https://zenoh.io/) の TCP で、別プロセス・別ホストの juiz を呼び出します。仕様は juiz の [docs/spec/zenoh-broker.md](https://github.com/OpenJUIZ/juiz/blob/main/docs/spec/zenoh-broker.md) です。

ブローカーのプラグインの C ABI([docs/spec/broker-plugin-abi.md](https://github.com/OpenJUIZ/juiz/blob/main/docs/spec/broker-plugin-abi.md))で作ってあるので、読み込む juiz と違う rustc・違う版でビルドしたものでも使えます(ブローカーの ABI の版が同じなら)。

## 入れ方

```sh
juiz broker install zenoh
```

このリポジトリの [Releases](https://github.com/OpenJUIZ/juiz_zenoh_broker/releases) から、その juiz が読める ABI の版とその OS・CPU のアーカイブを取り、sha256 を照合して `~/.juiz/brokers/zenoh/<版>/` に置きます(`JUIZ_BROKER_HOME` で変えられます)。版を決めるときは `--version <版>`、手元のアーカイブは `--from <パス>` です。`juiz broker list` で入っているものが、`juiz broker remove zenoh` で消せます。

| OS・CPU | アーカイブ |
|---|---|
| Linux x86_64 / arm64 | `juiz_broker-zenoh-<版>-abi<N>-x86_64-unknown-linux-gnu.tar.gz` / `…-aarch64-unknown-linux-gnu.tar.gz` |
| macOS Intel / Apple シリコン | `…-x86_64-apple-darwin.tar.gz` / `…-aarch64-apple-darwin.tar.gz` |
| Windows x86_64 | `…-x86_64-pc-windows-msvc.zip` |

## 使い方

入れた後は、conf に `type_name: zenoh` を書くだけで使えます(`plugins.broker_factories` は要りません)。

```yaml
brokers:
  - type_name: zenoh
    host: 0.0.0.0     # 省略すると 0.0.0.0
    port: 7448        # 省略すると 7448
```

繋ぐ側は `broker_proxies` / `subsystems` / `mastersystem` に `type_name: zenoh`、`name: <host>:<port>` を書くか、ID `zenoh://<host>:<port>` を使います(`juiz -s zenoh://<host>:<port> process list` など)。応答の待ち時間は `timeout_ms`(既定 10 秒)で変えられます。

- 要求と応答は、IPC・qmp と同じ生バイトのフレーム(先頭が `JZF1`、[docs/spec/large-data.md](https://github.com/OpenJUIZ/juiz/blob/main/docs/spec/large-data.md) §3)を、Zenoh の query / reply に 1 つずつ載せます。key expression は `juiz/v1/crud` に固定です。
- scouting(同じネットワークの Zenoh を自動で見つけること)は切ってあり、`tcp/<host>:<port>` の相手とだけ話します。
- 平文の TCP で、暗号化もアクセス制御もしません。信頼できるネットワークの中で使ってください。
- 1 回の要求・応答の大きさの上限は `max_frame_bytes`(既定 1 GiB)で、超えるフレームは送る前にエラーになります。
- Zenoh の設定は `zenoh_config`(`{"<キー>": <値>}`)で重ねられます。
- 同じホストの相手へは、64 KiB 以上のフレームを Zenoh の共有メモリで送ります(feature `shared-memory`、既定オン)。`shared_memory: false` で切れます。pool の大きさは `shm_pool_bytes`(既定 64 MiB)で、これより大きなフレームや、pool が空かないときは TCP で送ります。Zenoh は pool の全体を mlock するので、`ulimit -l`(RLIMIT_MEMLOCK、一般ユーザーの既定は多くの Linux で 8 MiB)が pool より小さいと警告を出して共有メモリを切ります。使うときは上限を上げるか `shm_pool_bytes` を下げてください。

自分で `System` を作る Rust のアプリケーションに組み込むときは、このクレートを git の依存で `default-features = false, features = ["shared-memory"]` にして、`setup()` の前に `juiz_core::register_builtin_cabi_broker(juiz_zenoh_broker::broker_entry)` を呼んでください。

## 版

版は juiz の版とそろえません。juiz と合わせるのはブローカーの ABI の版だけで、アーカイブの名前の `abi<N>` がそれです。`juiz broker install` は、その juiz が読める ABI の版のうちで一番新しいリリースを選びます。

## ビルドとテスト

```sh
cargo build --release                  # target/release/libjuiz_zenoh_broker.so など
scripts/test.sh                        # テスト (ポート 5212〜5254 などを使う)
scripts/package.sh x86_64-unknown-linux-gnu    # dist/ にアーカイブと .sha256
scripts/check-install.sh dist/juiz_broker-zenoh-*.tar.gz target/debug   # juiz broker install で入れて使えるか
```

テストはブローカー共通のスイート(juiz の `brokers/broker_suite`)を git の依存で使い、juiz コマンドと例のプラグインを相手にします。`scripts/test.sh` は `juiz-rev.txt` の rev の juiz を `.juiz/` に取ってきて、このリポジトリと同じ `target/debug` にビルドします(手元の juiz を使うときは `JUIZ_SRC=../juiz scripts/test.sh`)。juiz の rev を変えるときは、`Cargo.toml` の 3 か所の `rev` と `juiz-rev.txt` をそろえてください。

ベンチ(720p・4K の画像を TCP と共有メモリで送る):

```sh
cargo test --release --test broker -- bench:: --ignored --nocapture --test-threads=1
JUIZ_ZENOH_BENCH_TCP_ONLY=1 cargo test --release --test broker -- bench:: --ignored --nocapture --test-threads=1   # 共有メモリを切る
```

## 公開

`Cargo.toml` の `version` を上げてマージし、`v<版>` のタグを付けると、[release.yml](.github/workflows/release.yml) が 5 つのターゲットのアーカイブを作り、それぞれ `juiz broker install --from` で入れて使えることを確かめてから、タグのリリースに置きます。crates.io には出しません。

## ライセンス

MIT または Apache-2.0 のどちらか([LICENSE-MIT](LICENSE-MIT)・[LICENSE-APACHE](LICENSE-APACHE))。
