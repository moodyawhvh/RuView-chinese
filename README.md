<div align="center">

# RuView 中文翻译版

**[中文版] RuView — 把普通 WiFi 信号变成实时空间智能的开源感知平台**

[![原项目](https://img.shields.io/badge/原项目-ruvnet--RuView-blue?style=flat-square&logo=github)](https://github.com/ruvnet/RuView)
[![中文文档](https://img.shields.io/badge/中文文档-README.zh--CN.md-orange?style=flat-square)](README.zh-CN.md)
[![GitHub Stars](https://img.shields.io/github/stars/ruvnet/RuView?style=flat-square&label=原项目Stars)](https://github.com/ruvnet/RuView/stargazers)
[![微信联系](https://img.shields.io/badge/微信-uaycar-brightgreen?style=flat-square&logo=wechat)](#)

</div>

---

> 这是 [ruvnet/RuView](https://github.com/ruvnet/RuView) 的中文翻译版本。
> 完整源代码请访问原项目:https://github.com/ruvnet/RuView

**代部署 / 定制服务 / 技术咨询 请添加微信:uaycar**

---

## 📖 项目简介

RuView 是一个 WiFi 感知平台,把空气中的普通无线电信号转化为空间智能。人在空间中移动、呼吸甚至静坐时,都会以可测量的方式扰动 WiFi 电波;RuView 用低成本 ESP32 传感器采集信道状态信息(CSI),把这些扰动变成可用的数据:房间里有没有人、在做什么、状态是否正常。

它不依赖摄像头和可穿戴设备,穿墙、全黑环境都能工作——一块 9 美元的 ESP32 开发板,配合一个仅 8 KB 的量化预训练模型,就能非接触式地感知人员存在、呼吸率和心率趋势,并在树莓派上微秒级运行。整套系统完全跑在边缘硬件上:无云端、无摄像头、无需联网。

## ✨ 主要特性

- **存在与占用检测** — 穿墙感知人员、统计人数、追踪进出
- **生命体征监测** — 非接触式呼吸率与心率测量,睡眠或静坐时均可
- **活动识别与跌倒检测** — 从 CSI 时序模式识别行走、落座、手势与跌倒(< 200 ms 响应)
- **睡眠质量分析** — 整夜监测,含睡眠分期与呼吸暂停筛查
- **无摄像头姿态估计** — 从 WiFi CSI 估计 17 个身体关键点(MM-Fi 基准 82.69% torso-PCK@20)
- **智能家居原生接入** — Home Assistant、Apple Home/HomePod、Google Home、Alexa 经同一桥接或 Matter 端点接入,可语音播报
- **105 个签名边缘模块** — 健康、安防、楼宇、零售、工业、研究、AI 等场景,离线运行、安装验签
- **密码学可信** — 每次测量经 Ed25519 见证链认证,支持确定性复现证明
- **多频 mesh 扫描** — 跨 6 个 WiFi 信道跳频,把邻居路由器当免费雷达照射源
- **完全边缘化** — 基于 RuVector 与 Cognitum Seed,30 秒内完成本地环境自适应学习

## 📁 文件说明

| 文件 | 说明 |
|:-----|:-----|
| README.md | 本文件(中文简介) |
| README.zh-CN.md | 详细中文文档(完整汉化) |

## 🚀 快速开始

**1. Docker 体验(模拟数据,无需硬件)**

```bash
docker pull ruvnet/wifi-densepose:latest
docker run -p 3000:3000 ruvnet/wifi-densepose:latest
# 浏览器打开 http://localhost:3000
```

**2. Python 安装(已发布到 PyPI)**

```bash
pip install ruview                # 或: pip install wifi-densepose
pip install "ruview[client]"      # 附加 WebSocket + MQTT 客户端
```

**3. ESP32-S3 实时感知(约 $9)**

```bash
python -m esptool --chip esp32s3 --port COM9 --baud 460800 \
  write_flash 0x0 bootloader.bin 0x8000 partition-table.bin \
  0xf000 ota_data_initial.bin 0x20000 esp32-csi-node.bin
python firmware/esp32-csi-node/provision.py --port COM9 \
  --ssid "YourWiFi" --password "secret" --target-ip 192.168.1.20
```

**4. 下载 Hugging Face 预训练模型**

```bash
pip install huggingface_hub
huggingface-cli download ruvnet/wifi-densepose-pretrained --local-dir models/wifi-densepose-pretrained
```

> 注:存在检测、生命体征、穿墙感知等高级能力需要 CSI 硬件(ESP32-S3 或研究级网卡);Docker 镜像使用模拟数据仅供评估。

完整源代码与最新版本请访问原项目:https://github.com/ruvnet/RuView

## 📞 联系方式

**代部署 / 定制服务 / 技术咨询 请添加微信:uaycar**

---

本项目为 [ruvnet/RuView](https://github.com/ruvnet/RuView) 的中文翻译版本,所有代码版权归原项目作者所有,遵循其原始许可证。

**如果觉得有用,请给原项目点个 Star!** ⭐
