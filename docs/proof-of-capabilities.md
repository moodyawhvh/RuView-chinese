> 🌐 本文档由 [ruvnet/RuView](https://github.com/ruvnet/RuView) 翻译,英文原版见原项目。
>
> 注:原文超过 10000 字符,此处翻译核心章节(§2 公平批评界定、§4 自证流程、§6 诚实的局限),其余章节(舆论引用、领域科学背景、公开开发史、来源列表)见英文原版。

# 能力证明 —— 回应"造假/误导"的指控

**简短版:别信我们——去验证。** 下面每一条声明都附带一条你几分钟内就能自己运行
的命令。本项目早期版本若有夸大,我们会直说,并精确指出改了什么。这个页面存在的
原因:对一个声称"WiFi 能感知人"的项目,怀疑才是正确默认值,而对怀疑唯一诚实的
回应是可复现的证据,不是断言。

---

## 2. 哪些批评是公平的,哪些不是

最初的版本**早期但可用**——是能跑的原型,不是空壳。把公平批评与范畴错误分开:

| 批评 | 我们的诚实立场 |
|-----------|--------------------|
| "`csi_extractor` 返回随机数组 → 整个项目是假的" | **范畴错误。** 那些数组是**模拟/无硬件模式**——让你在没有网卡的情况下跑 demo 的路径(每个感知项目都带一个)。真实的 DSP 流水线从一开始就是真实且*确定性*的,`verify.py` 可比特级证明(见 §4 步骤 1)。随机数据不可能产生可复现哈希。 |
| "核心信号处理/姿态未实现" | **被证明本身反驳。** `verify.py` 端到端跑生产流水线(去噪 → 加窗 → FFT 多普勒 → PSD)并复现已发布的 SHA-256。流水线存在且在运行;早期*缺失*的是训练好的模型权重——与"缺流水线"是两回事。 |
| "100% 在场检测精度"缺乏支撑 | **公平——已正式撤回。** 该数字测自单类别录音(只有"在场"样本)。现已全面替换为诚实的 **82.3% 留出时序三元组**精度。撤回声明就地写在 `README.md` / `docs/user-guide.md` 中。 |
| 部分 header 指标(94.2% 姿态、96.5% 跌倒)早期没有公开评估 | **当时是公平的。** 那些愿景式数字已删除;当前数字绑定**已发布模型 + 可复现的公开基准评估**(见 §4 步骤 3)。 |
| 文档读起来像 AI 广告文案 | **部分公平。** 我们现在以可运行命令和公开的负面结果研究开篇,而不是堆形容词——包括本页。 |

如果本仓库的某条声明没有可运行命令背书,把它当营销话术并告诉我们——我们会修复
或撤回。

---

## 4. 自己动手证明(约 10 分钟,无需特殊硬件)

### 步骤 1 —— 确定性流水线证明("信任终止开关")

这是对"信号处理是假的"的直接回答。一个已知参考信号被送入**生产** DSP 流水线
(去噪 → Hamming 窗 → 幅度归一化 → FFT 多普勒 → PSD),输出做 SHA-256 哈希。
如果流水线是随机或 mock 的,哈希不可能可复现。

```bash
python archive/v1/data/proof/verify.py
# Expect:  VERDICT: PASS
# Pipeline hash: f8e76f21a0f9852b70b6d9dd5318239f6b20cbcb4cdd995863263cecdc446f7a
```

发布的期望哈希提交在 `archive/v1/data/proof/expected_features.sha256`。在你自己的
机器上跑——它**跨平台比特级一致**(已在 Windows、两台独立 Linux 主机和 GitHub
Azure CI runner 上验证一致)。唯一不比特稳定的特性——峰值归一化多普勒频谱,其
argmax 会在跨微架构 FFT 重排下翻转——被排除在哈希之外,并额外以严格相对容差对照
入库参考向量(`expected_features_reference.npz`)逐项检查其余特性:真实回归仍会
失败,CPU 级浮点噪声不会。五个特性(幅度均值/方差、相位差、相关矩阵、基于 FFT
的 PSD)承载确定性证明。

**关于"假数据"指控:** 参考信号*有意是合成的*且**自我标注**——
`archive/v1/data/proof/sample_csi_meta.json` 写明:

```json
{ "is_synthetic": true, "is_real_capture": false, "numpy_seed": 42, ... }
```

`generate_reference_signal.py` 的文件头声明:*"It is NOT a real WiFi capture."*
一个有标注、有文档、可复现的测试向量,与"把假数据冒充真实传感器输出"恰恰相反
——它正是让 DSP 流水线*可证伪*的方式。把两者混为一谈是"假 CSI"审计的核心错误。

### 步骤 2 —— 真代码,真测试(回应"核心未实现")

```bash
cd v2
cargo test --workspace --no-default-features
```

Rust v2 workspace 有 **38 个 crate**,测试分布在 **490+ 个文件**(数千个测试
函数)。这不是脚手架——它包含信号处理库(`wifi-densepose-signal`,16 个 RuvSense
模块)、推理栈(`wifi-densepose-nn`)、Axum 感知服务器、ESP32 硬件/固件 crate 等。
测试运行*就是*证明——别信数字,自己跑。

### 步骤 3 —— 真训练模型,公开基准可验证

header 数字**不是**在私有划分上自报的——它在**公开 MM-Fi 基准**上,权重已发布,
你可以重跑:

```bash
pip install huggingface_hub
huggingface-cli download ruvnet/wifi-densepose-mmfi-pose --local-dir models/mmfi-pose
```

| 指标(MM-Fi,匹配的 `random_split`) | 数值 |
|----------------------------------------|-------|
| torso-PCK@20,单模型 | **82.69%** |
| torso-PCK@20,3 模型集成 + TTA | **83.59%** |
| 75K 参数微型(边缘)变体 | 74.30% |
| 先前已发布 SOTA —— MultiFormer(2025) | 72.25% |
| 先前 —— CSI2Pose | 68.41% |

- 模型卡:[`ruvnet/wifi-densepose-mmfi-pose`](https://huggingface.co/ruvnet/wifi-densepose-mmfi-pose)
- 自纠错、可审计排行榜:[AetherArena Space](https://huggingface.co/spaces/ruvnet/aether-arena)
- 预训练编码器(82.3% 留出时序三元组):[`ruvnet/wifi-densepose-pretrained`](https://huggingface.co/ruvnet/wifi-densepose-pretrained)

### 步骤 4 —— 来自真实硬件的真实 CSI

一块 9 美元的 ESP32-S3 产出真实的 802.11 CSI;固件从本仓库构建并烧录
(`firmware/esp32-csi-node/`)。数据通路是 ESP-IDF CSI 回调(或树莓派上经
[rvCSI](https://github.com/ruvnet/rvcsi) 运行时的 nexmon_csi `.pcap`)——实测的
射频反射,不是合成数组。构建/烧录/配置步骤见
[`docs/user-guide.md`](user-guide.md) 与 `CLAUDE.local.md`。

---

## 6. 诚实的局限(今天依然成立)

- **零样本跨房间/跨人能力弱。** 每次部署请预留约 30 秒的房间内校准。
- **单节点空间分辨率有限。** 多人/定位请使用 2+ 个 ESP32 节点(或加一个
  Cognitum Seed)。
- **多人计数很难。** 它曾被两个服务器端 bug 钳在 "1"(现已修复——见 CHANGELOG
  #803);超出之后的精度仍取决于每节点估计器,并需要多人硬件验证。
- **仅以代理标签训练的无摄像头姿态**精度较低;摄像头监督微调
  ([ADR-079](adr/ADR-079-camera-ground-truth-training.md))才是好姿态的路径。
- **Beta 软件。** API 与固件都会变。

---

*如果本页任何命令在你的机器上没有产生所述结果,那就是一个 bug,我们想知道——
带输出开一个 issue。可复现性就是全部意义所在。*
