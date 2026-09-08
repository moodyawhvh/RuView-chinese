> 🌐 本文档由 [ruvnet/RuView](https://github.com/ruvnet/RuView) 翻译,英文原版见原项目。

# ADR-270 厂商 RF Provider

RuView 为厂商感知与 RF 遥测提供了一个能力安全的 Rust provider 层。它绝不把 RSSI、
占用、位置或网络清单转换成复杂 CSI。

## API

- `GET /api/v1/rf/vendors` — 所有 provider 描述符与访问状态。
- `GET /api/v1/rf/vendors/latest` — 每个 provider 最新一条已验证事件。
- `GET /api/v1/rf/vendors/:vendor/latest` — 某个稳定厂商 ID 的最新事件。
- `POST /api/v1/rf/vendors/:vendor/events` — 通过该厂商严格的 provider 解码器
  接入其文档定义的 sidecar/webhook 负载。配置后,此 `/api/v1/*` 路由遵循服务器的
  bearer-token 策略。

稳定 ID 为 `origin_ai`、`plume`、`mist`、`netgear`、`electric_imp`、
`rf_solutions`、`linksys`、`luma`、`google_nest` 和 `wifigarden`。

## 确定性模拟器

```bash
cd v2
cargo run -p wifi-densepose-hardware --bin vendor-rf-sim -- \
  --vendor plume --frames 100 --output plume.jsonl

# Stream canonical synthetic events to the sensing server UDP port.
cargo run -p wifi-densepose-hardware --bin vendor-rf-sim -- \
  --vendor mist --frames 100 --udp 127.0.0.1:5005 --realtime
```

支持的模拟器名称为 `origin-ai`、`plume`、`mist`、`netgear`、`electric-imp`、
`rf-solutions`、`luma` 和 `google-nest`。Linksys 被拒绝,因为其感知服务已停运。
Wifigarden 被拒绝,直到存在合同化的事件 schema。

每条合成事件都带 `synthetic: true`、确定性的序列号与时间戳,以及以 `-sim-01`
结尾的来源。

规范 UDP JSON 仅在 `synthetic: true` 时被接受。真实厂商负载必须走 HTTP 接入路由,
这样厂商专属 schema、指标白名单、访问状态与边界就无法被绕过。

## 真实/provider 负载

Provider 解码器是严格、有边界的,会拒绝未知 schema 字段。Origin 路径与凭据由商业
合同提供。Plume 使用只读、白名单化的 OVSDB 请求计划。Mist 与 NETGEAR 配置使用
区域 HTTPS 端点,令牌已脱敏。Electric Imp、RF Solutions 与 Luma 只接受白名单内的
标量指标。Google Nest 仍仅限网络侧。

凭据绝不内嵌在 fixture 或描述符中。Linksys 返回 `Unsupported`;Wifigarden 返回
`ContractRequired`。这些是可用、有测试覆盖的 provider 结果——不是模拟出来的
集成。

## 硬件诚实性

在验证过确切的硬件/云端版本、合法访问、可重复采集、适用时的校准,以及 fixture
发布授权之前,所有描述符保持 `hardware_validated: false`。通过模拟器与 API 测试
只验证了 RuView 软件本身。
