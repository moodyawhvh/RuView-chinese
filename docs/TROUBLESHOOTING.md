> 🌐 本文档由 [ruvnet/RuView](https://github.com/ruvnet/RuView) 翻译,英文原版见原项目。
>
> 注:原文超过 10000 字符,此处仅翻译核心章节;第 7、8 节(局域网 SSH、USB-C 端口等环境特定问题)请参阅英文原版。

# RuView 故障排查指南

来自 rebase-to-upstream 分支(upstream #301)的已知问题与修复。

---

## 1. 节点不出现在 /api/v1/nodes

**症状:** ESP32-S3 节点关联上 WiFi,LED 闪烁,但服务器收不到 CSI 帧。节点在
`/api/v1/spatial/nodes` 中缺失。

**根因:** USB 烧录后,节点进入一种"跛行"状态:WiFi 已关联,但 UDP CSI 发送器
静默失败。SoftAP + mDNS 栈初始化正常,但 CSI 回调从不触发。

**修复:** 给节点断电重启(拔 USB,等 2 秒,再插回)。如果无效,通过串口发送 DTR
复位:`python -m serial.tools.miniterm --dtr 0 COMx 115200` 然后按 Ctrl+C。

**预防:** 固件 0.8.0+ 内置看门狗,检测到 30 秒零 CSI 帧会自动触发软复位。节点
1-10 仍在旧固件上,缺少该恢复机制(OTA 与 BLE 的先有鸡还是先有蛋问题;见
issue #6)。

---

## 2. 人数统计卡在 1

**症状:** 无论房间里有几个人,`estimated_persons` 始终返回 1。

**根因(ADR-044):** 八个叠加的 bug:
1. `score_to_person_count` 上限为 3
2. `fuse_multi_node_features` 用了 `.max()` 而不是求和——N 个相同读数坍缩成 1
3. 四处 `.max(1)` 钳位把最小计数强制为 1,即使房间无人
4. `field_model.estimate_occupancy` 被 `.min(3)` 封顶
5. 归一化饱和(除以硬编码阈值,而不是自适应 p95)
6. 场模型无自动校准——特征值路径从未激活
7. 生命体征路径的钳位不对称
8. 层析成像只产出一团连通域(CC=1),去重后计数错误

**已实施修复(Waves 1-3):**
- Wave 1(`9cc5f604`):上限 3→10,`.max()` 改为 sum/3 聚合,放宽 `.max(1)` 钳位
- Wave 2(`306f1262`):RollingP95 自适应归一化,field_model 30 秒自动校准,
  生命体征钳位对称化
- Wave 3(`c3df375a`+`0d4bfb09`+`6ac70ddf`):CC 洪泛填充基础设施,lambda
  0.1→5.0,阈值 0.01→0.15,CC>1 门控

**当前状态:** 5 个目标(3 人 + 2 狗)输出 `estimated_persons` = 6-8。仍会多计,
因为 sum/3 去重因子是估计值。层析成像仍只产出一团(CC=1),CC 路径未激活。
支持运行时可配置的 lambda 会有助于无需重新部署的调参。

---

## 3. 心率/呼吸率抖动

**症状:** HR 与 BR 读数在帧间剧烈跳动。BR 变异系数 23.3%,HR 变异系数 12.9%。

**根因(ADR-045):** 11 个 ESP32 节点各自独立计算生命体征。服务器采用最后写入
获胜策略——最后到达的 UDP 包来自哪个节点,全局生命体征就被哪个覆盖。每节点约
20 fps,意味着每 50ms 生命体征就在不同观测点之间随机交错。

**已实施修复(`46fbc061`):** 最佳节点选择。每个节点的生命体征经中值滤波 + EMA
独立平滑,选择 `breathing_confidence + heartbeat_confidence` 组合最高的节点作为
权威来源。结果:BR 变异系数 23.3% → 12.6%,HR 变异系数 12.9% → 11.6%。

**已知局限:** `wifi-densepose-vitals` crate 有更优的 4 级流水线(带通 → Hilbert
包络 → 自相关 → 峰值检测),但尚未接入感知服务器。当前 `VitalSignDetector` 使用
更简单的 FFT 方案,频率分辨率 4 BPM。

---

## 4. 信号质量永远显示 50%

**症状:** 仪表盘的信号质量指针一直卡在约 50%。

**根因:** 信号质量是硬编码的占位值,并非来自实际 CSI 数据。

**已实施修复:** ADR-044 Wave 2 用 RollingP95 自适应归一化替换了假指针。UI 诚实化
改造(`b2070ab4`)为未验证指标加了 beta 标签,用每节点胶囊指示器替换假指针,并
暴露了真实的每节点信号数据。

---

## 5. 仪表盘每 2-4 秒冻结一次

**症状:** 空间视图与仪表盘冻结后重连,每 2-4 秒出现一次肉眼可见的卡顿。

**根因:** 客户端落后时,WebSocket 广播通道的 `recv()` 返回 `Err(Lagged)`。服务器
将其当作致命错误并断开连接。客户端立即重连,形成连接/断开循环。

**已实施修复(`581daf4f`):**
- 服务器:`Lagged` 错误 → `continue`(跳过错过的帧而不是断连)
- 服务器:30 秒 ping/pong keepalive,防止 Caddy 代理空闲超时
- 结果:8 秒内持续 154 帧,零断连

---

## 6. OTA 更新在 59% 崩溃

**症状:** 通过 `/api/v1/firmware/download` 的 OTA 固件更新推进到约 59% 后,节点
在 Core 1 上以 `StoreProhibited` 崩溃。

**根因:** NimBLE BLE 广播/扫描运行在 Core 1。OTA 期间 HTTP 客户端也运行在
Core 1。BLE 与 OTA 争抢栈空间,BLE 扫描回调在 OTA 写入期间触发内存访问违例。

**修复:**
1. 在调用 `esp_https_ota_begin()` 之前停止 NimBLE 广播与扫描
2. 把 httpd 栈从 4KB 提到 8KB(`CONFIG_HTTPD_MAX_REQ_HDR_LEN` 与任务栈)
3. OTA 完成或失败后恢复 BLE

**注意事项:** 运行旧固件的节点(1-10)无法通过 OTA 收到该修复,因为崩溃恰恰发生
在 OTA 过程中。这些节点必须先 USB 烧录 0.8.0+ 固件,之后的 OTA 更新才能正常。
节点 11 已 USB 烧录带看门狗的固件,可以接收 OTA 更新。

---

## 9. Windows 上的 Docker Desktop 丢弃多个 ESP32 节点的 UDP

**症状:** 两个或更多 ESP32 节点已烧录、配置完成,并在网络上可见地发包——
Windows 宿主机上的 `tcpdump`/Wireshark 能看到每个节点的数据报——但容器内只有
一个源 IP 到达。`/api/v1/sensing/latest` 只显示单个节点,实时 UI 冻结或只跟踪一个
目标。#374(4 节点基准)报告,并在 #386(6 节点演示,RuView v0.7.0)中复现。

**根因:** Windows 上的 Docker Desktop 把引擎跑在 WSL2 / Hyper-V 虚拟机内。来自
宿主机局域网的入站 UDP 经 `vpnkit` / `vEthernet` 转发,多源 IP 数据报被解复用到
单个虚拟套接字上。第一个源 IP "获胜";后续不同来源在 VM 边界被静默丢弃。这是
Docker Desktop 的限制,不是感知服务器的 bug——`host.docker.internal` 与
`--network host` 都帮不上忙(Windows 上的 Linux 引擎未实现主机网络)。

**修复:** 在宿主机上运行附带的 UDP 中继,让每个转发的数据报都来自同一个回环源
IP,Docker 会原样放行。

```powershell
# 1. Start the relay (PowerShell or any terminal)
python scripts/udp-relay.py --listen-port 5005 --forward-port 5006

# 2. Edit docker/docker-compose.yml — change the ESP32 UDP mapping from
#       - "5005:5005/udp"
#    to
#       - "5006:5005/udp"

# 3. Bring the stack up
docker compose -f docker/docker-compose.yml up
```

ESP32 节点仍以 `--target-ip <host>:5005` 指向宿主机——无需重新配置固件。中继脚本
是 `scripts/udp-relay.py`(仅标准库,零额外依赖)。用 `--verbose` 验证每个节点的
源 IP 在转发稳定到单一临时中继端口前至少出现过一次。

**预防:** Linux 与 macOS 宿主机不受影响;该中继只需在 Windows 的 Docker Desktop
上运行。如果 Docker Desktop 未来支持按源 UDP 转发(追踪于
[docker/for-win#1144](https://github.com/docker/for-win/issues/1144) 及相关
issue),此变通方案即可退役。

**先前工作:** PR #413(`txhno`)曾提出仅文档化的同类变通方案;本条目取代之。

---

## 10. 运行 sensing-server 时可视化页面返回 `404`

**症状:** `sensing-server` 正常启动,日志输出
`HTTP server listening on http://localhost:3000`,但访问 `http://localhost:3000/`
(或 `/ui/index.html`)返回 `404 Not Found`。#188 报告。

**根因:** 默认 `--ui-path ../../ui` 是相对于二进制*当前工作目录*解析的,而不是
二进制所在位置。从 `crates/wifi-densepose-sensing-server/` 之外的任何目录启动时,
相对路径够不到 UI 资源,Axum 的静态文件处理器就返回 404。

**修复:** 传入绝对 UI 路径、从 crate 目录运行,或使用 Docker 镜像(内置于
`/app/ui`)。

```bash
# Option A — absolute path (recommended for production)
sensing-server --source esp32 --udp-port 5005 --http-port 3000 \
  --ws-port 3001 --ui-path /absolute/path/to/ui

# Option B — run from the crate dir (works for local dev / cargo run)
cd v2/crates/wifi-densepose-sensing-server
cargo run -- --source esp32

# Option C — Docker (no path config needed)
docker compose -f docker/docker-compose.yml up sensing-server
```

**预防:** #188 中追踪后续工作:当 cwd 相对路径不存在时回退到相对可执行文件解析,
让二进制在任何位置启动都能工作。

---

## 11. `--edge-tier 1` 或 `--edge-tier 2` 启动死循环

**症状:** ESP32-S3 用 `--edge-tier 0` 正常启动,但同一固件以 `--edge-tier 1` 或
`2` 烧录后进入启动死循环。串口输出到达 `cpu_start` 和 `heap_init` 后反复复位。
#438 针对 `v0.4.3.1-esp32-3-g66e2fa083-dir` 固件报告。

**根因:** 边缘层级 1 和 2 会在 Core 1 上启用片上 DSP 流水线。在受影响的构建中,
`edge_dsp` 任务以紧凑的逐帧循环运行且从不让出,导致 FreeRTOS 任务看门狗在 Core 1
触发并 panic。Tier 0 仅做透传,不激活流水线,因此看门狗从不触发。

**修复:** 烧录 [v0.4.3.1-esp32](https://github.com/ruvnet/RuView/releases/tag/v0.4.3.1-esp32)
或更新版本——DSP 任务让出修复自报告中提及的构建起已进入 `main`。

```bash
# Verify what version you're on (look for "App version" in serial output on boot)
python -m serial.tools.miniterm COM7 115200
# Expect: "App version: v0.4.3.1-esp32" or higher
```

如果正式版仍出现启动死循环,采集包含看门狗回溯的完整串口轨迹,并附新构建哈希
重开 #438。
