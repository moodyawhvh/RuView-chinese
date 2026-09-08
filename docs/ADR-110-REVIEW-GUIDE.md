> 🌐 本文档由 [ruvnet/RuView](https://github.com/ruvnet/RuView) 翻译,英文原版见原项目。

# ADR-110 评审指南

这是 `adr-110-esp32c6` 分支 / 草稿 PR 评审者的**单页速览**。规范记录在
[`docs/WITNESS-LOG-110.md`](WITNESS-LOG-110.md);本指南只是更快的入门坡道。

## 这个分支交付了什么

`firmware/esp32-csi-node` 的双目标构建:同一份源码树既编译 `esp32s3`(现有生产
目标)也编译 `esp32c6`(带 Wi-Fi 6 / 802.15.4 / TWT / LP-core 的新研究目标)。
所有 C6 专属模块都用 `#ifdef CONFIG_IDF_TARGET_ESP32C6` 门控,S3 构建路径与之前
字节级一致。

## 评审者五分钟导览

1. **读 ADR**:[`docs/adr/ADR-110-esp32-c6-firmware-extension.md`](adr/ADR-110-esp32-c6-firmware-extension.md) —— 设计、阶段、权衡。
2. **读 witness**:[`docs/WITNESS-LOG-110.md`](WITNESS-LOG-110.md) —— 4 个分区(A = 实证验证,B = 架构就位但未实测,C = 已修复 bug,D = 已发现未修复 bug,D-workaround = ESP-NOW 转向方案)。
3. **略读新固件模块**:`firmware/esp32-csi-node/main/c6_{twt,timesync,lp_core,sync_espnow}.{h,c}`。
4. **略读新宿主解码器与测试**:
   - Rust:`v2/crates/wifi-densepose-hardware/src/{csi_frame,esp32_parser}.rs`(搜索 `PpduType`、`Adr018Flags`、`adr110_*` 测试名)
   - Python:`archive/v1/src/hardware/csi_extractor.py` + `archive/v1/tests/unit/test_esp32_binary_parser.py`(搜索 `TestAdr110ByteEncoding`)
5. **瞄一眼 CI**:`firmware-ci.yml` 的 `c6-4mb` 矩阵行在 Ubuntu 上同时跑 C6 构建
   与宿主单元测试——本分支全程绿。

## 实证记分卡(哪些真正测过)

| 维度 | 状态 |
|---|---|
| C6 构建 + 启动 + 双目标 | ✅ 3 块板(COM6/COM9/COM12)实测,CI 矩阵绿,S3 回归绿 |
| HE-LTF 线格式(ADR-018 字节 18-19) | ✅ 固件 / Rust / Python 端到端验证(17 个单元测试) |
| HE-LTF 实机抓包 | ⏸ 受阻——需要 11ax AP(台面上只有 11n AP) |
| TWT 优雅 NACK | ✅ 实机验证——捕获并处理了 `c6_twt: iTWT setup failed: ESP_ERR_INVALID_ARG` |
| TWT 节奏确定性 | ⏸ 受阻——同样是缺 11ax AP |
| ESP-NOW 传输 TX + 稳定性 | ✅ 已验证——120 s + 300 s 浸泡测试,累计 4102 次发送,0 失败 |
| ESP-NOW 跨板 RX | ⏸ 受阻——实验中 4 块板有 3 块中途掉 USB 枚举 |
| 原生 802.15.4 跨节点同步 | ❌ 损坏——IDF v5.4 驱动 bug,测试并否决了 5 个假设;已落地 ESP-NOW 变通方案 |
| 5 µA 休眠 | ⏸ 受阻——数据手册数字,需要 INA / Joulescope 才能实测 |
| Witness bundle 可再生且干净 | ✅ 6/7 PASS(1 个失败是既有的 Python 证明环境问题,与 ADR-110 无关),全部哈希已记录,密钥已脱敏 |

## 诚实结论

协议层 + 传输底座已经加固到位。**四个 header SOTA 维度没有一个完成实测**——每个
都卡在台面没有的硬件上。每个阻塞点都在 `WITNESS-LOG-110.md` §B 中记录了所需的
确切仪器。**这个分支是供测量展开的地基,不是测量本身。**

工作过程中发现并修复的五个具体 bug(MAC/EUI 双 FFFE、`wifi_pkt_rx_ctrl_t` 双
结构体变体、C6 的 LED GPIO 38、TWT INVALID_ARG 传播、witness bundle 密钥泄漏)
无论 SOTA 叙事走向如何,都独立成立且有用。

## 面向运维者的安全提示(不是给评审者的)

Witness bundle 的 Python 证明步骤曾通过 Pydantic 校验错误转储把 `.env` 内容泄漏
进打包日志。推送前 bundle 已被销毁,并添加了 `scripts/redact-secrets.py` 过滤器
(commit `f8a2e3695`)。**此前暴露的 Docker Hub + PI 集群令牌应当轮换**——它们
虽未到达 `origin`,但已出现在本地会话日志中。

## 本分支提交时间线

| # | SHA 前缀 | 内容 |
|---|---|---|
| 1 | `f23e34e` | ADR-110 固件 + ADR + 测试 + 文档 + witness 脚手架 |
| 2 | `6652384` | TWT INVALID_ARG 优雅处理 + 诊断计数器 |
| 3 | `4c39e28` | PAN 匹配 + 4 实验 D1 记录 |
| 4 | `f8a2e36` | **安全**:witness bundle 密钥脱敏 |
| 5 | `88be283` | ESP-NOW 传输(D1 变通方案) |
| 6 | `3959fab` | Rust 宿主解码器 + 6 个单元测试 |
| 7 | `8eaa92c` | Python 宿主解码器 + 5 个单元测试 |
| 8 | `b808a63` | 120 s ESP-NOW 浸泡 witness |
| 9 | `89972c0` | CHANGELOG 扩充 |
| 10 | `fc75a8a` | Fuzz 测试舱扩展至字节 18-19 |
| 11 | `9de34ba` | ADR-110 收录进 docs/adr/README.md |
| 12 | `553b07d` | README C6 行收紧(声明 → 线格式就绪) |
| 13 | `e255b7d` | firmware/README 承认 S3+C6 |
| 14 | `9a46fc8` | 300 s ESP-NOW 浸泡 witness(2.5× 样本) |
| 15 | _(本次提交)_ | 本评审指南 |
