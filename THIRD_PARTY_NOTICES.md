# Third-party notices

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
