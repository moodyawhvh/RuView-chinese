> 🌐 本文档由 [ruvnet/RuView](https://github.com/ruvnet/RuView) 翻译,英文原版见原项目。

# RuView Streaming Engine v0.3.0 —— 可审计的环境智能

## 这是什么

大多数 WiFi 感知栈丢给你一个数字,然后指望你信它。**RuView 的流式引擎的构建目标
就是让你不必盲信。** 它得出的每一个结论——"客厅有人"、"跌倒风险升高"、"房间布局
变了"——都带着完整的证据链:哪些传感器看到了它、它们之间的一致程度、哪套校准和
模型产生了它,以及它是在什么隐私策略下被发出的。

主线是**信任**。当你问*"它说有人跌倒了,我凭什么信?"*,引擎的回应是信号证据、
传感器一致性、校准来源和可审计的隐私姿态——而不只是一个置信度分数。

本版本落地了 ADR-135→146 系列:数据契约、信任/隐私/审计机制,以及算法——全部
真实、经过测试,并组装成一条端到端流水线循环。

## 让它可审计的两层结构

- **WorldGraph(`wifi-densepose-worldgraph`)** —— "在哪里 & 为什么"图。一张类型化
  的图:房间、传感器、RF 链路、人员轨迹、物体锚点、事件与信念,通过类型化边
  连接:`observes`、`located_in`、`derived_from`、`contradicts`、
  `privacy_limited_by`。隐私姿态*直接可见于持久化图中*——审计者能确切读到什么
  被抑制了、为什么。
- **可信语义记录** —— "我们此刻相信什么"记录。每条语义状态携带模型版本、校准
  版本、证据引用、置信度、过期时间与隐私动作。高风险动作(照护者升级通知)需要
  **多信号一致**,而不是单个嘈杂的原语。

## v0.3.0 新增内容

| 领域 | 能力 |
|------|-----------|
| 帧契约(ADR-136) | `ComplexSample`(LE 规范),每帧携带来源字段,`CanonicalFrame` BLAKE3 witness,`Stage`/`Versioned`/`QualityScored` trait |
| 校准(ADR-135) | `BaselineCalibration::apply()` 为每帧盖上确定性的 `calibration_id` |
| 融合质量(ADR-137) | `QualityScore` 含每节点权重、证据引用与矛盾标志;校准不匹配检测 |
| 阵列协同(ADR-138) | 时钟质量 + 几何门控;降级节点转为"仅观察" |
| WorldGraph(ADR-139) | 类型化数字孪生 + 隐私汇总 + 确定性持久化 |
| 语义记录(ADR-140) | 可审计状态记录 + 多信号 agent 路由 |
| 隐私控制平面(ADR-141) | 具名模式 + 动作 + BLAKE3 哈希链、防篡改的证明 |
| 演化 + VoxelMap(ADR-142) | 跨链路"房间变了"检测 + 贝叶斯占用,隐私门控后仅输出直方图 |
| RF-SLAM(ADR-143) | 持久反射体发现 → 学习得到的静态锚点 |
| UWB 融合(ADR-144) | 带离群点剔除的距离约束精化(前瞻性) |
| 消融测试舱(ADR-145) | 特征矩阵指标,含成员推断隐私泄漏 |
| RF 编码器(ADR-146) | 多任务头 + 每头不确定度 + 对比学习批处理器(前瞻性) |
| **引擎(`wifi-densepose-engine`)** | 组合根:一次 `process_cycle()` 跑完整条信任流水线 |

## 快速上手

```rust
use wifi_densepose_engine::StreamingEngine;
use wifi_densepose_bfld::PrivacyMode;
use wifi_densepose_geo::types::GeoRegistration;
use wifi_densepose_signal::ruvsense::fusion_quality::CalibrationId;

// 1. Build the engine with a privacy posture + model version.
let mut engine = StreamingEngine::new(PrivacyMode::PrivateHome, 1, GeoRegistration::default());

// 2. Describe the space (rooms + sensors are WorldGraph nodes).
let room = engine.add_room("living_room", "Living Room");
let sensor = engine.add_sensor("esp32-com9", room);
engine.register_node_geometry(0, 1.0, 0.0, 0.0);   // ADR-138 array geometry (optional)

// 3. Each 50 ms cycle: feed per-node CSI frames + the calibration epoch.
let out = engine.process_cycle(&node_frames, CalibrationId(0xABCD), room, now_ms)?;

// 4. The result is a *trusted* belief — fully traceable.
println!("class={:?} demoted={} evidence={:?}",
         out.effective_class, out.demoted, out.provenance.evidence);
assert_eq!(out.quality.calibration_id, Some(CalibrationId(0xABCD)));

// 5. Persist the world model; reload reproduces the same query results.
let snapshot = engine.snapshot_json()?;        // RVF payload — never raw RF frames
```

每节点校准(不匹配时自动降级隐私等级):

```rust
let out = engine.process_cycle_calibrated(
    &node_frames,
    &[Some(CalibrationId(1)), Some(CalibrationId(2))], // disagree → CalibrationIdMismatch
    room, now_ms)?;
assert!(out.demoted);                          // privacy class demoted to Restricted
assert_eq!(out.quality.calibration_id, None);  // no single calibration epoch
```

## 已验证(证明该架构的验收测试)

- **ADR-137** `two calibrated frames → calibration mismatch → QualityScore contradiction → Restricted → calibration_id None → witness stable`
- **ADR-139** `live_frame → fusion → worldgraph_update → privacy_rollup → persist → reload → same_contents`(不持久化任何原始 RF)
- **ADR-140** `raw snapshot → semantic primitive → SemanticStateRecord → agreement rule → expired record rejected`
- **ADR-142** `3 links drift 30 frames → ChangePoint → VoxelMap accumulates → low-confidence suppressed → VoxelGate Restricted histogram → ADR-137 contradiction`

## 性能与安全

- **全循环约 6.35 µs**(4 节点 / 56 子载波)——比 50 ms / 20 Hz 预算快约 7,800×
  (criterion:`cargo bench -p wifi-densepose-engine`)。
- 新 crate 均为 `#![forbid(unsafe_code)]`;无硬编码密钥;边界处校验输入;隐私降级
  是单调的;模式变更有哈希链证明。
- `wifi-densepose-core` 与 `wifi-densepose-bfld` 以 `#![no_std]` 构建,支持
  ESP32-S3 片上路径。

## 构建与测试

```bash
cd v2
cargo build --release --workspace --no-default-features    # optimized build
cargo test --workspace --no-default-features                # full suite
cargo test -p wifi-densepose-engine                         # 13 integration tests
cargo bench -p wifi-densepose-engine                        # per-cycle latency
```

## 状态(诚实版)

已端到端集成并验证:ADR-135/136/137/138/139/141/142/143,经由
`wifi-densepose-engine` 组合根。前瞻性/待办:实时 20 Hz 感知服务器循环接线、UWB
硬件(ADR-144)、RF 编码器模型训练(ADR-146)。每个 GitHub issue(#840–#850)
都列明了哪些是 *Built*、哪些是 *Integration glue*。
