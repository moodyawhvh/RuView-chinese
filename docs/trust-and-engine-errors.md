> 🌐 本文档由 [ruvnet/RuView](https://github.com/ruvnet/RuView) 翻译,英文原版见原项目。
>
> 注:原文超过 10000 字符,此处翻译核心章节并做了适度压缩;完整论证与逐行代码引用见英文原版。

# 信任状态与引擎错误

如果你看到感知服务器的 `engine_error_count` 不断增长,或者注意到部署在状态端点上
显示 `"demoted": true`,本页从实际代码(而非设计文档)出发,解释这两件事的含义、
触发条件、观察位置,以及你真正的可选动作。

以下内容基于
`v2/crates/wifi-densepose-sensing-server/src/engine_bridge.rs`、
`v2/crates/wifi-densepose-sensing-server/src/main.rs`、
`v2/crates/wifi-densepose-engine/src/lib.rs` 与
`v2/crates/wifi-densepose-signal/src/ruvsense/multistatic.rs`。

## 两件容易被混淆的事

感知服务器在每个感知 tick 运行一次"受治理的信任循环"
(`StreamingEngine::process_cycle`,由 `engine_bridge.rs` 的
`EngineBridge::observe_cycle` 驱动)。每次循环产生**两种结果之一**,且被完全分开
跟踪:

1. **循环彻底失败**(`Result::Err(EngineError)`)——该 tick 不发布任何内容。这会
   递增 `engine_error_count`,一个单调递增计数器。
2. **循环成功但处于降级隐私等级**
   (`Result::Ok(TrustedOutput { demoted: true, .. })`)——信念*会*发布,只是以比
   常规更受限的隐私等级发布。这会设置 `demoted` 标志,每次成功循环都会重新计算。

一个部署可能 `engine_error_count` 很高但 `demoted: false`(大量循环失败,但成功
的那些是干净的),也可能 `demoted: true` 而 `engine_error_count: 0`(循环全部
成功,但都以降级隐私等级发布),或者两者同时出现——issue 报告者看到的就是最后
这种。

## 1. 各自的确切触发条件

### 引擎错误(`engine_error_count`)

只有当 `StreamingEngine::process_cycle` 返回
`Err(EngineError::Fusion(..))` 时,`engine_error_count` 才递增。`EngineError`
包装的是
`wifi_densepose_signal::ruvsense::multistatic::MultistaticError`,它恰好有四个
变体:

| 变体 | 条件 |
|---|---|
| `NoFrames` | 没有节点帧传入融合。实际上经 bridge 不可达:没有帧时 `process_cycle_from_states` 返回 `None`(不是错误,不计数),根本不会调用引擎。 |
| `InsufficientNodes(n)` | 多基地模式下参与融合的节点少于 2 个。 |
| `TimestampMismatch { spread_us, guard_us }` | 参与节点的帧时间戳离散度超过**硬保护间隔**,默认 **60,000 µs(60 ms)**。 |
| `DimensionMismatch { node_idx, expected, got }` | 某节点的子载波数与其他节点不一致。自 #1170 起,实时 bridge 在融合前把每个节点规范化到统一的 56-tone 网格,真实硬件上如今已罕见。 |

无论原因如何,错误日志都做了**限速**:每 10 秒至多一条 `tracing::warn!`
(`ENGINE_ERROR_WARN_INTERVAL`)——每个循环仍会照常计数,被节流的只是*日志行*,
所以 20 Hz 循环持续失败也不会以每秒 20 行的速度刷爆日志。

### 信任降级(`demoted`)

这是与引擎错误**不同的机制**:它发生在*成功*的循环上,把输出的隐私等级下调一级,
而不是让循环失败:

```rust
let demoted = quality.forces_privacy_demotion() || array_contradiction || mesh_at_risk;
let effective_class = if demoted { demote_one(base_class) } else { base_class };
```

三个独立条件可以触发它:

- **`quality.forces_privacy_demotion()`** —— 融合质量记录携带任何非空的
  `contradiction_flags` 即为真。这些是*被容忍的*分歧,与硬性融合失败不同:
  - `TimestampMismatch` —— 离散度在**硬**保护之内但超出**软**保护(默认
    **20,000 µs / 20 ms**,`soft_guard_us`)——即"松散但可容忍"的时间对齐。
  - `CalibrationIdMismatch` —— 参与帧在所属校准纪元(基线)上不一致。
  - `PhaseAlignmentFailed`、`DriftProfileConflict`、`CoherenceDrop`、
    `GeometryInsufficient` —— 由上游阵列协调器/基线漂移检查抛出。
- **`array_contradiction`** —— 独立的阵列级方向性融合矛盾检查。
- **`mesh_at_risk`** —— mesh 接近分区(`mesh_guard.rs`)。

`demote_one()` 把隐私等级向 `Restricted` 精确移动一档(绝不一次跳多档,也绝不
在同一循环内放宽等级——由 `forced_contradiction_never_relaxes_class` 测试证明)。
到达 `PrivacyClass::Restricted` 时,`EngineBridge::suppress_raw_outputs()` 变为
true,`main.rs` 会从发布的 `SensingUpdate` 中剥离每节点原始幅度向量。

**关键点:`demoted` 不具粘性。** 每次成功循环都会覆盖它,反映*该循环*的结果。
如果触发降级的矛盾是瞬态的,下一个干净循环会立刻重新报告 `demoted: false`,
无需你做任何事。如果你看到 `demoted: true` *持续存在*,那说明底层条件(通常是
时钟漂移超出保护间隔,或几何/校准分歧)本身就是持续性的,而不是什么东西"卡住
了"。

## 2. 在哪里观察

`GET /health/ready` 与 `GET /api/v1/status` 接到同一个 handler,返回一个 `trust`
块:

```json
{
  "status": "ready",
  "trust": {
    "last_witness": "…64 hex chars or null…",
    "effective_class": "Anonymous | Restricted | …",
    "demoted": false,
    "recalibration_recommended": false,
    "engine_error_count": 0,
    "raw_outputs_suppressed": false
  }
}
```

**这是一个真实、当前已发布的诊断面——但坦率地说,它的能力有限。** 它告诉你
*发生了*错误、*当前*等级被降级以及总计数,但不告诉你*为什么*:

- `engine_error_count` 只是一个累计值。API 与 `EngineBridge` 状态中**没有任何按
  错误类型的分解**——你无法从 `/health/ready` 判断那 20,000 次错误是 20,000 次
  `TimestampMismatch` 还是 20,000 次 `DimensionMismatch`。
- `demoted` 只是个布尔值,没有附带的 `ContradictionFlag` 触发列表。底层
  `contradiction_flags` 向量存在于 `QualityScore` 中,但我们没有找到任何把它
  上报到网络层的地方。
- 没有错误历史/时间线,也没有按节点分解(比如到底是哪个节点的时钟在漂移)。

**当前最接近真实诊断的手段是那条限速日志本身。** 与 API 不同,日志消息包含实际
`EngineError` 的 `Display` 文本,对 `TimestampMismatch` 和 `DimensionMismatch`
会给出具体数字(例如 `"Timestamp spread 87000 us exceeds guard interval 60000
us"`、`"Dimension mismatch: node 2 has 114 subcarriers, expected 56"`)。要诊断
某次具体的降级/错误,在感知服务器日志里 grep `"governed trust cycle failed"`
是目前最具体的答案——仅靠状态端点给不出底层原因。请把这当作诊断能力的诚实现状,
而不是我们假装存在的缺失功能。

## 3. 降级/错误状态是永久的吗?能重置吗?

**`demoted` 永远不需要重置** ——如前所述,它在每个成功循环中由该循环自身的
矛盾/mesh 状态重新计算。代码里没有持久化、没有计数器、没有冷却计时器。

**`engine_error_count` 完全没有重置机制。** 它是 `EngineBridge` 上的一个普通
`u64` 字段,在 `EngineBridge::new` 中初始化为 `0`,只会递增——crate 中不存在
任何递减或清除它的方法、管理端点或计时器。归零的唯一方式是**重启感知服务器
进程**,从而构造一个全新的 `EngineBridge`。如果你的计数在增长,想确认修复是否
生效:重启服务器,观察计数是否重新攀升——目前没有比重启更轻量的"清零计数器"
办法。

**如果降级(或错误)是持续性的而非偶发**,针对最常见原因——节点间时钟漂移超过
固定的 60 ms 硬保护——文档给出的真实修复是环境变量覆盖,而不是重启或等待:

- `WDP_GUARD_INTERVAL_US` —— 直接覆盖硬保护(例如 `WDP_GUARD_INTERVAL_US=200000`
  即 200 ms 保护)。这是真实部署(issue #1049)需要的逃生口:WiFi/ESP-NOW 同步的
  ESP32 节点实测漂移 10–150 ms,发布的 60 ms 默认值无法吸收,导致**每个**循环都
  降级且"无逃生口"。
- `WDP_SOFT_GUARD_US` —— 可选覆盖软(容忍矛盾)保护,始终被钳在硬保护之下。
- `WDP_TDM_SLOTS` + `WDP_TDM_SLOT_US` —— 从你的实际 TDM 调度推导保护间隔,而非
  直接设置。

精确的优先级规则见 `multistatic_guard_config_from_env` /
`multistatic_guard_config_from`(直接设置的 `WDP_GUARD_INTERVAL_US` 永远优先于
TDM 推导值)。

## 4. 换转换过的 Hugging Face 模型能解释这些吗?

**我们找不到任何把 `--convert-model` 与引擎错误或信任降级联系起来的代码路径
——它们看起来是完全独立的子系统。** 直说而非臆测:

- `--convert-model` 把**姿态模型权重文件**——Hugging Face `safetensors` 或
  `jsonl` manifest——转换成本项目自己的 RVF 二进制容器格式,以便经 `--model`
  加载。这完全关乎姿态估计器用哪套神经网络权重。
- `engine_error_count` 与 `demoted` 来自 `wifi-densepose-engine` 的
  `StreamingEngine::process_cycle`,它做的是**多基地 CSI 传感器融合**——检查节点
  数、每节点时间戳离散度和每节点子载波维度。这条代码路径不依赖加载了哪个姿态
  模型,`load_or_convert_model` / `run_convert_model` 也从不调用 `engine_bridge`
  或 `StreamingEngine`。

既然代码显示二者无耦合,我们不会编造一个。若两个症状同时出现,代码不排除但也
不证实的可能性有两种:一是**巧合**(该部署另外存在融合时序或节点数问题,例如
#1049 式时钟漂移或活跃节点不足 2);二是**换模型同时做了其他配置变更**(节点数、
几何或保护设置),模型本身并非原因。

可执行的排查动作:无论加载了哪个模型,都**独立**检查 `engine_error_count` 与
日志错误文本——如果错误是
`TimestampMismatch`/`DimensionMismatch`/`InsufficientNodes`,修复在传感器融合侧
(见 §3),与模型无关。

## 速查

```bash
# Check current trust state
curl -s http://localhost:3000/api/v1/status | jq .trust

# Watch for the rate-limited error log line (most specific diagnostic today)
# — look for "governed trust cycle failed" in the sensing-server's stderr/log.

# If demotion/errors are persistent due to node clock drift, raise the guard:
WDP_GUARD_INTERVAL_US=200000 wifi-densepose-sensing-server ...

# The only way to reset engine_error_count is a process restart.
```

以上全部内容的源码出处:
- `v2/crates/wifi-densepose-sensing-server/src/engine_bridge.rs`
- `v2/crates/wifi-densepose-sensing-server/src/main.rs`(搜索 `trust`、`health_ready`、`multistatic_guard_config_from`、`convert_model`)
- `v2/crates/wifi-densepose-engine/src/lib.rs`
- `v2/crates/wifi-densepose-engine/src/mesh_guard.rs`
- `v2/crates/wifi-densepose-signal/src/ruvsense/multistatic.rs`
- `v2/crates/wifi-densepose-signal/src/ruvsense/fusion_quality.rs`
