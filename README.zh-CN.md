<div align="center">

# RuView 中文文档

[![原项目](https://img.shields.io/badge/原项目-ruvnet--RuView-blue?style=flat-square&logo=github)](https://github.com/ruvnet/RuView)
[![微信联系](https://img.shields.io/badge/微信-uaycar-brightgreen?style=flat-square&logo=wechat)](#)

**用 WiFi 看穿墙壁:把普通路由器信号变成实时空间感知系统**

</div>

> 本文档是 [ruvnet/RuView](https://github.com/ruvnet/RuView) README 的中文翻译,可能滞后于原项目,请以英文原文为准。
> 代部署 / 定制服务 / 技术咨询 请添加微信:**uaycar**

## 📖 项目简介

RuView 是一个 WiFi 感知平台,把无线电信号转化为空间智能。每台 WiFi 路由器都在向空间辐射电波,人的移动、呼吸甚至静坐都会以可测量的方式扰动这些电波。RuView 通过低成本 ESP32 传感器采集信道状态信息(CSI),把扰动变成可用的数据:房间里有没有人、在做什么、状态是否正常。

它不依赖摄像头和可穿戴设备,穿墙、黑暗环境均可工作,纯靠物理原理:一块 9 美元的 ESP32 开发板读取室内人体反射的无线电信号,配合发布在 Hugging Face 的小型预训练模型 [`ruvnet/wifi-densepose-pretrained`](https://huggingface.co/ruvnet/wifi-densepose-pretrained)(4-bit 量化仅 8 KB),即可判断在场人员、呼吸频率和心率趋势,在树莓派上微秒级运行。系统基于 [RuVector](https://github.com/ruvnet/ruvector/) 与 [Cognitum Seed](https://cognitum.one) 构建,完全运行在边缘硬件上——无云端、无摄像头、无需联网。

## ✨ 主要特性

- **存在与占用检测** — 穿墙感知人员、统计人数、追踪进出
- **生命体征监测** — 非接触式呼吸率与心率测量,睡眠或静坐时均可
- **活动识别** — 从 CSI 时序模式识别行走、落座、手势与跌倒
- **环境建图** — RF 指纹识别房间、检测家具移动与新物体
- **睡眠质量** — 整夜监测,含睡眠分期分类与呼吸暂停筛查
- **无摄像头姿态估计** — 从 WiFi CSI 估计 17 个身体关键点
- **本地自动化** — HOMECORE 提供状态、历史、自动化、签名 Wasm 插件与 HomeKit 支持
- **智能家庭生态原生接入** — Home Assistant 一条 `--mqtt` 参数即插即用;Apple Home / Google Home / Alexa / SmartThings 以 Matter Bridge 方式配对;每个节点输出 21 个实体(11 个原始信号 + 10 个语义状态,如有人睡眠、疑似不适、浴室占用、跌倒风险升高等),并附 3 个 HA Blueprint
- **密码学可信** — 每次测量经 Ed25519 见证链认证;脉冲神经网络 30 秒内完成本地环境自适应
- **多频 mesh 扫描** — 跨 6 个 WiFi 信道跳频 TDM 调度,把邻居路由器当作免费雷达照射源

## 🚀 快速开始

**方式一:Docker(模拟数据,无需硬件)**

```bash
docker pull ruvnet/wifi-densepose:latest
docker run -p 3000:3000 ruvnet/wifi-densepose:latest
# 打开 http://localhost:3000
```

**方式二:Python(已发布到 PyPI)**

```bash
pip install ruview                # 或: pip install wifi-densepose
pip install "ruview[client]"      # 附加 asyncio WebSocket + MQTT 客户端
```

**方式三:ESP32-S3 实时感知(约 $9)**

```bash
python -m esptool --chip esp32s3 --port COM9 --baud 460800 \
  write_flash 0x0 bootloader.bin 0x8000 partition-table.bin \
  0xf000 ota_data_initial.bin 0x20000 esp32-csi-node.bin
python firmware/esp32-csi-node/provision.py --port COM9 \
  --ssid "YourWiFi" --password "secret" --target-ip 192.168.1.20
```

**方式四(进阶):ESP32-C6 研究节点(Wi-Fi 6 + 802.15.4,约 $6-10)或 Cognitum Seed 全家桶(约 $140,含持久存储 + kNN + 见证链)**,详见原项目 README。

**下载 Hugging Face 预训练模型**

```bash
pip install huggingface_hub
huggingface-cli download ruvnet/wifi-densepose-pretrained --local-dir models/wifi-densepose-pretrained
```

> [!NOTE]
> 存在检测、生命体征、穿墙感知等高级能力需要 CSI 硬件;Docker 镜像使用模拟数据仅供评估;普通笔记本 WiFi 只能提供基于 RSSI 的粗略存在检测。

## 🔧 硬件选项(节选)

| 方案 | 硬件 | 成本 | 说明 |
|------|------|------|------|
| ESP32 + Cognitum Seed(推荐) | ESP32-S3 + Seed | ~$140 | 全部能力 + 持久向量存储 + kNN + 见证链 |
| ESP32 Mesh | 3-6× ESP32-S3 + 路由器 | ~$54 | 除持久记忆外能力相同 |
| ESP32-C6 研究节点 | C6-DevKit | ~$10 | Wi-Fi 6 CSI,双目标固件 |
| 研究级网卡 | Intel 5300 / Atheros AR9580 | ~$50-100 | 3x3 MIMO 完整 CSI |
| 任意 WiFi | 笔记本 | $0 | 仅 RSSI 粗略存在/运动检测 |

## 📊 感知能力一览(节选)

| 能力 | 实现方式 | 速度 / 规模 |
|------|----------|------------|
| 🫁 呼吸率 | 0.1–0.5 Hz 带通 + 相位过零 BPM | 6–30 BPM,实时 |
| 💓 心率 | 0.8–2.0 Hz 带通 + 过零 BPM | 40–120 BPM,实时 |
| 👤 存在检测 | HF 预训练头 + 相位方差兜底 | < 1 ms,约 30 s 环境校准 |
| 🧬 CSI 嵌入 | 128 维对比编码器,4-bit 仅 8 KB | 164,183 emb/s(M4 Pro) |
| 🦴 17 关键点姿态 | MM-Fi 姿态模型 82.69% torso-PCK@20 | Pi 5 冷启动 8.4 ms |
| 🤸 跌倒检测 | 相位加速度阈值 + 防抖 + 冷却 | < 200 ms |
| 🧮 多人计数 | 自适应 P95 归一化 + 可调去重因子 | 实时,自校准 |
| 🧱 穿墙感知 | 菲涅尔区几何 + 多径建模 | 最远约 5 m,视信号而定 |
| 🧠 边缘智能 | 105 个签名边缘模块目录 | 整机 BOM 约 $140 |

## 🧩 边缘模块目录(节选)

原项目提供 105 个签名的边缘模块(健康、安防、楼宇、零售、工业、研究、AI、集群、信号、网络、开发工具等),直接运行在 ESP32 传感器本地——无需联网、无云费用、即时响应,安装前逐个验签并支持 OTA 目录更新。完整目录见 [seed.cognitum.one/store](https://seed.cognitum.one/store) 或原 README 的 Edge Module Catalog 章节。代表性模块:

| ID | 功能 | 大小 |
|----|------|-----:|
| `fall-detect` | 两段式冲击+静止跌倒检测 | 402 KB |
| `sleep-apnea` | 睡眠呼吸暂停检测 | 4 KB |
| `health-monitor` | 非接触心率/呼吸/睡眠/跌倒告警 | 30 KB |
| `cardiac-arrhythmia` | 心律不齐与异常心搏识别 | 8 KB |
| `intrusion` | 未授权人员闯入告警 | 6 KB |
| `glass-break` | 玻璃破碎声学检测 | 451 KB |
| `gait-analysis` | 步态异常检测与跌倒风险评分 | 12 KB |
| `vital-trend` | 呼吸/心率数周趋势追踪 | 6 KB |

## 🤗 预训练模型与基准

- **CSI 编码器 + 存在检测头**:[`ruvnet/wifi-densepose-pretrained`](https://huggingface.co/ruvnet/wifi-densepose-pretrained) — 60K 帧 / 610K 对比三元组训练,**82.3% held-out 时序三元组准确率**(旧版"100% 存在"数字已在原项目中被撤回),量化档位 q2/q4/q8 最小 4 KB。
- **17 关键点姿态模型**:[`ruvnet/wifi-densepose-mmfi-pose`](https://huggingface.co/ruvnet/wifi-densepose-mmfi-pose) — MM-Fi 基准 **82.69% torso-PCK@20**(3 模型集成 + TTA 达 83.59%),超过此前 SOTA MultiFormer(72.25%)与 CSI2Pose(68.41%)。
- **可复现证明**:原仓库提供确定性管线校验脚本 `archive/v1/data/proof/verify.py`(输出 SHA-256 与公布哈希比对,须打印 `VERDICT: PASS`),并有 33 行能力证明矩阵与见证记录。

### 模型权重:哪些是真的

原项目以诚实标注著称,把"WiFi→姿态"分成三个成熟度等级(详见原 README 的 "Model weights: what's real, what's not" 章节):

- **真实且已验证**:上述两个 Hugging Face 模型与 `cog-person-count/count_v1`,为项目当前可背书的数字。
- **真实但较弱(诚实标注)**:仓内 `pose_v1.safetensors` 为初版端侧模型,PCK@20 仅 3.0%,低于 ADR-079 ≥35% 目标;其运行时路径仍是返回 `confidence=0` 的占位桩,权重尚未接入。
- **仅有架构,无权重**:`archive/v1` 的 DensePoseHead 为随机初始化,无任何检查点,已弃用。

单天线 56 子载波 CSI 流尚不携带多天线研究方案所需的细粒度空间信息;当前可背书的姿态精度是 MM-Fi 基准数字,而非单块 ESP32 的实时数字。

## 🔗 相关链接

- 原项目:https://github.com/ruvnet/RuView
- 在线演示:[Live Observatory Demo](https://ruvnet.github.io/RuView/) · [3D 点云](https://ruvnet.github.io/RuView/pointcloud/)
- 预训练模型:[wifi-densepose-pretrained](https://huggingface.co/ruvnet/wifi-densepose-pretrained) · [wifi-densepose-mmfi-pose](https://huggingface.co/ruvnet/wifi-densepose-mmfi-pose)
- Docker 镜像:[ruvnet/wifi-densepose](https://hub.docker.com/r/ruvnet/wifi-densepose) · PyPI:[ruview](https://pypi.org/project/ruview/)

---

**代部署 / 定制服务 / 技术咨询 请添加微信:uaycar**

---

本文档为 [ruvnet/RuView](https://github.com/ruvnet/RuView) 的中文翻译,所有代码与内容版权归原项目作者所有,遵循其原始许可证(MIT)。如果觉得有用,请给原项目点个 Star!⭐
