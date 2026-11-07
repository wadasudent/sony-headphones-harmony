# Third-party notices

## 中文说明与引用范围

本项目主要由 OpenAI Codex 辅助生成和修改，由维护者提出需求并提供设备与反馈。AI 生成不改变第三方源码的署名与许可要求，也不构成对上游协议研究工作的原创声明。

| 来源 | 本项目中的使用范围 | 版本 / 定位 |
| --- | --- | --- |
| [mos9527/SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient)；mos9527、Amr Satrio 及贡献者 | MDR 帧、能力查询、状态与控制指令的参考或移植，以及 RFCOMM 连接生命周期处理；对应 `entry/src/main/ets/protocol/MdrCore.ts` 与 `entry/src/main/ets/services/Headphones.ets` | 固定提交 `68dfced0403b38114b77f2b374e606ce12a206a8`；MIT 许可原文保留于下方 |
| [marconvcm/sony-device-center PR #44](https://github.com/marconvcm/sony-device-center/pull/44)；PR 作者 Cyrus7，抓包贡献者 joncppl 及相关贡献者 | XM6 十段均衡器报文格式、公开抓包数值及修复记录的交叉核对；对应 `MdrCore.ts` 和 `checks/equalizer.cjs`。其中检查用数值是社区公开记录，不是本项目自行采集的抓包 | PR #44，合并提交 `16749520f3adea905a6a3fe89a9b3068ed21d55b`；此条标注技术资料与测试数据来源，不将该项目整体列为运行时依赖 |
| [Sony 官方帮助指南](https://helpguide.sony.net/mdr/2984/v1/en/contents/TP1001924935.html) | 核对 360 Upmix for Cinema 的产品行为；不是公开控制 API 或源码授权 | README 中相应功能说明 |
| HarmonyOS / ArkUI / UIDesignKit 官方 SDK | 原生界面、蓝牙、后台任务与服务卡片使用的平台接口 | API 26；SDK 不随仓库分发，使用条件以华为提供的条款为准 |

社区协议和抓包记录不等于 Sony 官方接口承诺；本项目的适配修改与局限由本项目自行说明。品牌名称不表示官方认可。下方 MIT 声明针对所注明的上游部分，不作为本项目新增部分的整体许可证。

## SonyHeadphonesClient attribution and license

The protocol implementation in `entry/src/main/ets/protocol/MdrCore.ts` and the
RFCOMM lifecycle handling in `services/Headphones.ets` are informed by / ported from
SonyHeadphonesClient, by mos9527, Amr Satrio and contributors.

Upstream: https://github.com/mos9527/SonyHeadphonesClient
Analyzed commit: 68dfced0403b38114b77f2b374e606ce12a206a8 (v1-compat branch).

Reference files: Command.cpp, Headphones.cpp, HeadphonesV2.cpp,
HeadphonesV2T1.cpp, ProtocolV2.hpp, ProtocolV2T1.hpp, RfcommSession.ets.
Early fixtures, now archived outside this source repository, were a small
selection of upstream's publicly recorded WF-1000XM5 frames. They are not
XM6 captures or HarmonyOS 7 test results.

This independent application is not affiliated with or endorsed by Sony or Huawei.
The original license follows in full.

MIT License

Copyright (c) 2026 mos9527, Amr Satrio and other contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
