> 🌐 本文档由 [ruvnet/RuView](https://github.com/ruvnet/RuView) 翻译,英文原版见原项目。

# 参与 WiFi Veil 贡献

感谢你的关注。WiFi Veil 是一个隐私防御项目,附带严格的诚实与安全契约——提交
PR 前请先读完本文。

## 不可协商的规则

- **只做合规波形控制——绝不干扰压制。** 不要添加、建议或搭建基于干扰的"防御"。
  每个控制手段只能塑形节点*自身*符合标准的发射并保留其能量。
- **绝不把 WiFi 感知宣传成摄像头级。** 精度/防御声明必须标注 `SYNTHETIC`、
  `CLAIMED` 或 `MEASURED`。只有附带复现脚本的数字才配称 `MEASURED`;硬件声明需要
  真实芯片采集的日志。本仓库目前的一切都是 `SYNTHETIC / L0`。
- **证明 witness 是承重墙。** 默认场景由确定性 FNV-1a witness
  (`src/proof.rs`)钉死。如果某次变更有意移动了它,必须在*同一个 PR 内*重新钉住
  常量并说明原因;意外变更就是测试失败,而不是去随手 bump witness。

## 开发

Rust crate 零依赖,可离线构建。

```bash
cargo test                        # 43 tests + the pinned witness
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo build --lib --target wasm32-unknown-unknown   # WASM leaf must stay green

cd firmware/core && make test     # portable C core host test
node harness/bin/cli.js guidance --topic overview   # harness (dependency-free)
```

推送前运行诚实/反 slop 守卫(CI 也会跑):

```bash
bash scripts/ci-guard.sh
```

它静态强制维持本项目诚实的不变量:不提交遥测/构建产物/lockfile/临时文件;源码
中无 debug 或 mock 探针标记;每个固件 provider README 都带 `SYNTHETIC` 证据标签;
"绝不干扰"合规免责声明必须存在;不得出现不诚实的硬件验证声明(诚实的否定式/
`TODO(hw)` 表述没问题);代码表层不得残留过期的 monorepo 标识。

CI(`.github/workflows/ci.yml`)运行同样的门禁。保持变更是最小自洽单元,编辑前
先阅读,绝不提交遥测(`.claude-flow/`)、构建产物、凭据或 CSI/个人数据。

## 架构决策

实质性设计变更应引用或在 [`docs/adr/`](docs/adr/) 下新增 ADR。以源码、测试和
已采纳的 ADR 为权威,优先级高于注释和生成的文本。
