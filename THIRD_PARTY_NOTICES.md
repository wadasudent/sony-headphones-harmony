# Third-party notices

## 其他资料

- [sony-device-center PR #44](https://github.com/marconvcm/sony-device-center/pull/44)：作者 Cyrus7、抓包贡献者 joncppl 及相关贡献者；用于交叉核对 XM6 十段均衡器报文及 `checks/equalizer.cjs` 中的公开抓包数值，不是本项目自行采集的数据。合并提交：`16749520f3adea905a6a3fe89a9b3068ed21d55b`。
- [Sony 帮助指南](https://helpguide.sony.net/mdr/2984/v1/en/contents/TP1001924935.html)：用于核对 Cinema 音效行为，不是控制 API 或源码授权。
- HarmonyOS / ArkUI / UIDesignKit：使用官方 SDK 接口，SDK 不随本仓库分发。

下方许可适用于注明的上游部分，不作为本项目新增部分的整体许可证。AI 开发不改变第三方署名与许可要求。

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
