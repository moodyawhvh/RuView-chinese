> 🌐 本文档由 [ruvnet/RuView](https://github.com/ruvnet/RuView) 翻译,英文原版见原项目。

# 可观测性:OTLP 日志导出

感知服务器可以把每一条 `tracing` 日志事件作为 OpenTelemetry 日志记录经 OTLP 导出,
其中一组精选的感知事件(在场状态切换、生命体征估计、节点上线/离线、跌倒检测、
CSI 采集统计、MQTT 错误、模型加载)在 `ruview.*` 命名空间下携带由注册表支撑的
事件名与属性。

## 事件注册表

这些名称不是拍脑袋定的:它们定义在经 weaver 校验的语义约定注册表
`semconv/registry/` 中(属性与日志事件名,OpenTelemetry 注册表格式)。Rust 常量
模块 `v2/crates/wifi-densepose-sensing-server/src/semconv.rs` 就是由该注册表
**生成**的(`weaver registry generate`,模板位于 `templates/registry/rust/`),
CI(`.github/workflows/semconv.yml`)会在注册表校验失败或生成模块发生漂移时直接
失败。可执行的 Rust 测试还会拒绝任何在生成注册表中不存在的硬编码 `ruview.*`
埋点键。导出的资源携带注册表的 schema URL,下游消费者借此识别确切的约定版本。

精选事件:

| 事件 | 触发时机 |
| --- | --- |
| `ruview.node.online` | 感知节点(CSI 或边缘生命体征)发来第一帧 |
| `ruview.node.offline` | 节点连续 60 秒无帧后被移除 |
| `ruview.presence.changed` | 平滑后的在场分类翻转(仅状态切换时) |
| `ruview.vitals.estimate` | 周期性呼吸/心率估计(每 100 个 tick) |
| `ruview.fall.detected` | 边缘生命体征跌倒标志的上升沿,按节点计 |
| `ruview.csi.stats` | 周期性采集快照:已处理帧数、活跃节点数 |
| `ruview.mqtt.error` | HA 发布器中的 MQTT 发布/连接错误 |
| `ruview.model.loaded` | 通过模型 API 加载推理模型 |

## 启用导出

导出受双重门禁保护,默认构建与默认运行时均不受影响:

1. **构建**时启用 `otel` cargo 特性(编译进 OTLP 导出器栈,与 `mqtt` 同一门禁
   原则):

   ```sh
   cargo build --release -p wifi-densepose-sensing-server --features mqtt,otel
   ```

2. **运行**时设置 `OTEL_EXPORTER_OTLP_ENDPOINT`(未设置则 OTLP 流水线根本不会
   构造,日志行为与从前完全一致):

   ```sh
   OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
   ./target/release/sensing-server --source simulated
   ```

在可信局域网之外请使用 `https://` 的 collector 端点。`otel` 特性包含 Rustls 与
系统原生证书根;标准 OTLP 环境变量可以提供认证头。Compose 示例中的明文仅用于
其私有网络上的容器间流量。

日志导出携带资源属性 `service.name = "ruview"` 与 schema URL
`https://raw.githubusercontent.com/ruvnet/RuView/main/semconv/schema/ruview-0.1.0.yaml`。
精选感知事件只在配置的导出器成功初始化之后才会发出;未启用时,既有的 stderr
输出保持不变。

## 全栈体验:`docker compose`

`docker/otel-compose.yml` 会拉起整条流水线——
感知服务器(默认合成 CSI)→ OpenTelemetry Collector →
[Ourios](https://github.com/jensholdgaard/ourios),一个基于 Parquet + 在线日志
模板挖掘 + DataFusion 的 OTLP 原生日志后端:

```sh
docker compose -f docker/otel-compose.yml up
```

collector 与后端镜像标签固定到不可变的多平台 digest,确保 demo 解析到经过审查
的镜像。

Ourios 从 `service.name` 推导租户,所以所有 RuView 日志都会落入 `ruview` 租户。

## 查询示例

Ourios 在接入时把每行日志在线归并到稳定的 `template_id`,让模板层面的问题变得
廉价。它的查询端点说一种小型日志 DSL:

哪些日志模板主导了 RuView 的输出?

```sh
curl -s http://localhost:4319/v1/query \
  -H 'X-Ourios-Tenant: ruview' \
  -H 'Content-Type: text/plain' \
  -d 'severity >= trace | range(-1h, now) | count by template_id | sort count desc | limit 10'
```

最近的警告与错误(跌倒检测、MQTT 故障):

```sh
curl -s http://localhost:4319/v1/query \
  -H 'X-Ourios-Tenant: ruview' \
  -H 'Content-Type: text/plain' \
  -d 'severity >= warn | limit 50'
```

某次 RuView 部署有没有改变服务日志的内容?两个时间窗之间的模板漂移
(新增/消失/变化的模板):

```sh
curl -s http://localhost:4319/v1/query \
  -H 'X-Ourios-Tenant: ruview' \
  -H 'Content-Type: text/plain' \
  -d 'drift from -7d to now'
```
