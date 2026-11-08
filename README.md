# 索尼耳机助手

面向 HarmonyOS 7 手机和平板的索尼耳机控制应用，当前版本 **0.5.0**。

项目主要由 **OpenAI Codex** 完成代码、界面及文档开发，维护者提供需求、设备和使用反馈。协议基于社区开源成果，来源见下文。项目与索尼、华为无官方关联。

## 功能

- 查看电量、固件版本和音频编码。
- 切换降噪、环境声，调整耳机均衡器及支持的音效设置。
- 提供桌面服务卡片；断链后隐藏读数，点击可重连。
- 支持深浅色主题、鸿蒙原生导航与平板双栏布局。

功能按耳机返回的能力开放。目前实测耳机为 **WH-1000XM6**，手机为 Pura 70 Pro+，平板为 PCE-W30；其他索尼型号仍待适配和验证。暂不支持固件升级、旧款 MDR V1 协议及左右耳独立电量。

## 构建与使用

使用 DevEco Studio 和 API 26 SDK，在项目目录执行：

```powershell
.\build.ps1
```

首次构建会从 `build-profile.example.json5` 创建本地配置。在 DevEco 中配置设备调试签名后，安装包输出到 `entry/build/default/outputs/default/entry-default-signed.hap`。

先在系统蓝牙中配对，再到应用中连接。长按桌面应用图标可添加服务卡片。后台同步受系统调度限制。

签名配置、证书、密钥及安装包不上传 Git。应用需要蓝牙和后台运行权限，无网络权限；历史读数和重连设备标识仅保存在本机。

## 验证

`checks/equalizer.cjs` 和 `checks/widgets.cjs` 可用 DevEco 自带 Node 运行。真机检查见 [测试记录](docs/DEVICE_TEST_2026-11-07.md)；平板竖屏、分屏及长期耗电仍待验证。AI 生成与编译通过不代表完整人工审计或全型号兼容。

## 来源与许可

- [SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient)：MDR 协议与 RFCOMM 处理的参考或移植来源，作者 mos9527、Amr Satrio 及贡献者，采用 MIT 许可。
- [sony-device-center PR #44](https://github.com/marconvcm/sony-device-center/pull/44)：XM6 十段均衡器格式与公开抓包数据的交叉核对来源。

引用范围、固定提交及上游许可原文见 [第三方声明](THIRD_PARTY_NOTICES.md)。仓库目前私有，新增部分尚未指定整体开源许可证；第三方部分保留原许可。
