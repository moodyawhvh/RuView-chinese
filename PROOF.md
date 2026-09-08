> 🌐 本文档由 [ruvnet/RuView](https://github.com/ruvnet/RuView) 翻译,英文原版见原项目。

# PROOF —— 复现每一个声明,或者找出我们还复现不了的那一个

本项目(RuView / wifi-densepose)曾被公开称为 "AI slop" 和 "假的"。本文档就是
回应:**怀疑者可以克隆仓库、运行一条脚本,让每一条核心声明要么在自己的机器上被
验证,要么被明确标注为 "CLAIMED,尚未复现(并给出它到底需要什么)。"** 下面没有
任何一条断言是拿不出可运行命令的。

```bash
git clone https://github.com/ruvnet/RuView && cd RuView
bash scripts/prove.sh          # 核心门禁 + 反 slop 断言测试
bash scripts/prove.sh --full   # 同时尝试带特性门禁的子集
```

只有所有**非门禁**声明全部通过,`prove.sh` 才以 0 退出。带门禁的声明永远不会让
运行失败;它们会打印前置条件(一块 GPU、一个数据集、真实硬件、一个训练好的
checkpoint),方便你自己去复现。

## 分级标准

- **MEASURED** —— 在我们的硬件上复现,记录了精确命令,并由一个*在前置修复代码上
  会失败的测试*钉死。`prove.sh` 会重跑这些项。
- **CLAIMED** —— 引自某个来源,或由该来源测量,但未在本仓库的自动化测试舱中
  复现。
- **DATA-GATED / HARDWARE-GATED** —— *代码路径*是真实且经过测试的,但*精度/吞吐
  声明*需要我们不随仓库分发的数据或硬件。我们从不编造数字;代码会返回类型化的
  错误,或携带 `weights_trained`/来源标志。

## 硬门禁(任何装有 Rust + Python 的机器都可运行)

| 声明 | 等级 | 复现方式 |
|---|---|---|
| Rust workspace:3,128 个测试,0 失败 | **MEASURED** | `cd v2 && cargo test --workspace --no-default-features` |
| 确定性 CSI 流水线证明(比特级一致 SHA-256) | **MEASURED** | `python archive/v1/data/proof/verify.py` → `VERDICT: PASS` |

## 反 slop 断言测试(每一项在前置修复代码上都会失败)

| 声明 | 等级 | 测试(通过 `cargo test -p <crate> <name>` 运行) |
|---|---|---|
| Fusion 构造输入 DoS 崩溃已封堵(ADR-156 §2.2) | **MEASURED** | `wifi-densepose-ruvector :: triangulation_out_of_range_index_returns_none_no_panic` |
| **"Soul Signature" 身份声明的诚实边界:** 仅凭 WiFi 心跳+呼吸通道,两个人**不可区分**(差距 ≈ 0.0005) | **MEASURED** | `wifi-densepose-bfld :: cardiac_alone_cannot_separate_identity_matches_audit` |
| OccWorld `predict()` 是真实实现(依赖输入),不是随机噪声 | **MEASURED** | `wifi-densepose-occworld-candle :: predict_is_deterministic_for_same_input` |
| 姿态运行时在自身默认配置下即可输出帧(ADR-159 A1) | **MEASURED** | `cog-pose-estimation :: default_config_emits_frames_with_real_model` |
| 人数统计会标记未训练类别——杜绝计数虚高(ADR-159 A2) | **MEASURED** | `cog-person-count :: untrained_class_argmax_is_flagged_low_confidence` |
| 医疗边缘技能附带 "非医疗器械" 免责声明(ADR-160 A1) | **MEASURED** | `wifi-densepose-wasm-edge :: a1_med_modules_have_clinical_disclaimer` (`--features std`) |
| Survivor 去重 3→1,计数虚高被消灭(ADR-158 §2) | **MEASURED** | `wifi-densepose-mat :: test_identical_vitals_no_location_dedup_to_one` (`--features mat`) |

## 实测性能(criterion;可在你自己的机器上复现)

| 声明 | 等级 | 复现方式 |
|---|---|---|
| PSD FFT-planner 缓存 2.0–3.1×,DTW 频段 2.4–4.1×(ADR-154) | **MEASURED** | `cd v2 && cargo bench -p wifi-densepose-signal` |
| fuse() 移除双重克隆,marshalling 提速约 2.17×(ADR-156) | **MEASURED** | `cd v2 && cargo bench -p wifi-densepose-ruvector --bench fusion_bench` |
| 零拷贝 ORT 输入约 1.48×(ADR-155) | **MEASURED** | `cd v2 && cargo bench -p wifi-densepose-nn --features onnx --bench onnx_bench` |
| pointcloud splats 从 9 趟降到 2 趟,约 1.24×(ADR-160 研究) | **MEASURED** | `cd v2 && cargo bench -p wifi-densepose-pointcloud --bench splats_bench` |
| 原生 wlanapi 多 BSSID 扫描 9.74 Hz(对比 netsh 约 2 Hz) | **MEASURED (Windows)** | `cd v2 && cargo test -p wifi-densepose-wifiscan -- --ignored measure_native_scan_rate` |
| wasm-edge `process_frame` 热路径延迟(主机代理,ADR-163) | **MEASURED-on-host**(不是 ESP32/WASM3 预算——需要硬件) | `cd v2/crates/wifi-densepose-wasm-edge && cargo bench --features std` |
| cog 稳态 CPU 推理延迟约 305 µs(ADR-163;不是 manifest 冷启动) | **MEASURED-on-host** | `cd v2 && cargo bench -p cog-person-count -p cog-pose-estimation --no-default-features --bench infer_bench` |

## 我们不做声明的能力(诚实的负面清单——最有力的反 slop 信号)

| 能力 | 状态 |
|---|---|
| **从 WiFi 识别具名个人身份** | **未实现,且已测明原因。** §3.6 匹配器是真实的,但仅凭 WiFi 通道身份无法锁定(差距 0.0005)。DATA-GATED:需要真实注册流程接入 AETHER/身体共振通道——从未做过。不做任何具名身份声明。 |
| WiFlow-STD 约 96% PCK@20 | 在我们的 RTX 5080 上 **CLAIMED-reproduced**(`benchmarks/wiflow-std/RESULTS.md`);对你而言是 HARDWARE-GATED(需要 NVIDIA GPU + MM-Fi 数据集)。上游*随包发布的 checkpoint* 已被**证伪**(0.08% PCK)——我们公开了这一点。 |
| OccWorld 轨迹精度 | DATA-GATED:需要训练好的 checkpoint;在加载之前 `predict()` 携带 `weights_trained=false`——绝不悄悄造假。 |
| 边缘技能检测精度(癫痫、武器、情绪等) | UNVALIDATED——所有此类模块现已通过免责声明标注为实验/研究性质;DSP 是真实的,精度不做声明。 |
| 802.11bf-2025 空口一致性 | 截至 2026 年,没有量产芯片提供符合规范的接口;我们的是经模拟测试的前向兼容协议模型,不是认证实现。 |

## 来源追溯

上面的每一条声明都可追溯到一份入库的 ADR(`docs/adr/ADR-154`…`ADR-163`)、一个
测试、一个 criterion bench、`benchmarks/wiflow-std/RESULTS.md` 或
`benchmarks/edge-latency/RESULTS.md`。历史中包含已公开的**撤回记录**(92.9% PCK
撤回;WiFlow-STD 发布 checkpoint 证伪;NV-diamond BOM 现实核查)——造假者会隐藏
失败,而我们把失败提交进仓库。
