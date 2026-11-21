# 索尼耳机助手 · HarmonyOS

[English](README.md) · 简体中文

面向鸿蒙手机和平板的非官方索尼蓝牙耳机管理工具。查看电量、切换降噪与环境声、调整均衡器，还可以把耳机状态放到桌面服务卡片。当前以 HarmonyOS 7 为目标平台。

## 使用

- 在系统蓝牙设置中配对并连接耳机，再打开助手。智能重连默认开启，优先接入上次使用的耳机。有多副可选设备且无优先设备时，请在应用内选择。
- 长按应用图标添加服务卡片。卡片显示电量和聆听模式，断链时隐藏读数，点按可重连。
- 在「更多 → 外观」选择深浅色模式和强调色。外观设置、卡片读数和重连标识保存在本机。

## 耳机兼容性

| 型号 | 当前验证情况 |
| --- | --- |
| WH-1000XM6 | 已在鸿蒙手机和平板上实测连接与状态读取。支持降噪、环境声和十段均衡器。 |
| WF-1000XM5 | 左耳、右耳和充电盒电量已通过报文回放验证，待鸿蒙真机测试。 |
| 其他索尼耳机 | 按设备报告的 MDR V2 能力显示功能，待逐型号验证。 |

当前版本暂不支持旧款 MDR V1 协议和固件升级。详见[真机测试记录](docs/DEVICE_TEST_2026-11-07.md)、[固件升级调查](docs/FIRMWARE_UPDATE_FEASIBILITY.md)和[手动降噪档位调查](docs/XM6_MANUAL_ANC_RESEARCH.md)。

## 本地构建

安装 DevEco Studio 和 HarmonyOS API 26 SDK。在 Windows PowerShell 的项目根目录运行以下命令。

```powershell
.\build.ps1 -CheckOnly
.\build.ps1
```

第一条运行协议、卡片和重连检查，无需设备或签名。第二条从 `build-profile.example.json5` 初始化本地配置，构建调试 HAP。自定义安装位置可通过 `-ToolHome '你的 DevEco Studio 安装目录'` 指定，或设置 `DEVECO_STUDIO_HOME`。

真机安装需在 DevEco Studio 的 **Project Structure → Signing Configs** 配置自己的设备调试签名，再次构建。安装包为 `entry/build/default/outputs/default/entry-default-signed.hap`。本地签名配置、密钥和安装包均由 Git 忽略。

## 作者与许可

主要代码、界面和文档由 OpenAI Codex 辅助完成，维护者提供需求、设备和使用反馈。MDR 协议实现参考并移植自 **SonyHeadphonesClient**（MIT）。本项目新增部分的许可证尚待确定。上游署名、许可原文和测试报文来源见[第三方声明](THIRD_PARTY_NOTICES.md)。
