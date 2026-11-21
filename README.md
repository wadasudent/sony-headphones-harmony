# Sony Headphones Assistant for HarmonyOS

English · [简体中文](README.zh-CN.md)

Switch listening modes, adjust the equalizer, and check your Sony headphones' battery from a HarmonyOS phone or tablet. Sony lists its Sound Connect app for Android and iOS. This community app brings those everyday controls to HarmonyOS over the headphones' Bluetooth MDR V2 protocol. [Sony Sound Connect downloads](https://www.sony.com/electronics/support/wireless-headphones-bluetooth-headphones/wh-1000xm6/software/00269130)

**Version 0.5.0** · [Install](#install) · [Change history](https://github.com/wadasudent/sony-headphones-harmony/commits/main/)

<p>
  <a href="docs/screenshots/phone.png"><img src="docs/screenshots/phone.png" width="21%" alt="Phone app showing the connected WH-1000XM6, battery level, and listening modes"></a>
  <a href="docs/screenshots/tablet.png"><img src="docs/screenshots/tablet.png" width="72%" alt="Tablet app showing WH-1000XM6 status and equalizer in a two-column layout"></a>
</p>

## Install

The repository provides source code. A public installer is currently unavailable.

1. [Download the source ZIP](https://github.com/wadasudent/sony-headphones-harmony/archive/refs/heads/main.zip) or clone the repository. Install DevEco Studio with the HarmonyOS API 26 SDK.
2. Copy `build-profile.example.json5` to `build-profile.json5` if the latter is missing. Open the project in DevEco Studio.
3. Enable USB debugging on your device and connect it to your computer. Set up debug signing for that device in **Project Structure → Signing Configs**, then click **Run**. [Huawei device debugging guide](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/app-debugging-faq-0005/)

If you already have a HAP signed for your device, run `hdc install -r <path-to-signed.hap>` with Huawei Device Connector. [HDC installation reference](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/hdc/)

The build targets API 26. Its configured minimum is **HarmonyOS 6.0 (API 20)**. Physical-device testing has covered HarmonyOS 7. Testing on 6.0 is pending.

## Using the app

- Pair and connect your headphones in system Bluetooth settings, then open the app. Auto-reconnect is enabled by default and gives priority to the last headset used. If several headsets are available and there is no preferred device, select one in the app.
- Long-press the app icon to add a home screen widget. It shows the battery level and listening mode while connected. The readings are hidden when disconnected. Tap the widget to reconnect.
- Choose a light or dark appearance, follow the system appearance, or change the accent color under **More → Appearance** (「更多 → 外观」).

## Headphone compatibility

| Model | Verification |
| --- | --- |
| WH-1000XM6 | Tested on a HarmonyOS phone and tablet. The app reads battery, firmware, and active codec, switches between noise canceling, ambient sound, and off, and exposes the headset's 10-band EQ. |
| WF-1000XM5 | Left earbud, right earbud, and case battery readings verified through packet replay. All features are still awaiting HarmonyOS hardware testing. |
| Other Sony models | Controls depend on the device's reported MDR V2 capabilities. Model-by-model verification is pending. |

See the [device test notes](docs/DEVICE_TEST_2026-11-07.md) in Chinese for the tested setup and scope.

## Current limits

- Listening mode selection and ambient sound level are available on supported headsets. Manual ANC strength control is unavailable. [ANC investigation](docs/XM6_MANUAL_ANC_RESEARCH.md)
- The app displays the active codec reported by the headset. It has no controls for LDAC bitrate, LE Audio, multipoint connections, wear detection, DSEE, or Sony's activity- and location-based Adaptive Sound Control. Automatic ambient sound is available on headsets that report support for it.
- Firmware updates and legacy MDR V1 models are unsupported. [Firmware update investigation](docs/FIRMWARE_UPDATE_FEASIBILITY.md)

## Privacy and permissions

Bluetooth access (`ACCESS_BLUETOOTH`) lets the app find and control paired headphones. Background running (`KEEP_BACKGROUND_RUNNING`, `bluetoothInteraction`) lets an active control connection keep syncing the widget while the app is in the background, subject to system limits. Disconnecting in the app stops that session.

The app has no Internet permission. Appearance preferences, the last headset identifier, and widget readings stay on the device. Connection logs are kept in memory.

## Building locally

Install DevEco Studio and the HarmonyOS API 26 SDK. Run the following commands from the repository root in Windows PowerShell.

```powershell
.\build.ps1 -CheckOnly
.\build.ps1
```

The first command runs the protocol, widget, and reconnection checks without a device or signing credentials. The second initializes the local configuration from `build-profile.example.json5` and builds a debug HAP. For a custom DevEco Studio installation, pass `-ToolHome 'path to DevEco Studio'` or set `DEVECO_STUDIO_HOME`.

With debug signing configured, the build writes `entry/build/default/outputs/default/entry-default-signed.hap`. Git ignores local signing configuration, keys, and build packages.

## Credits and licensing

- **Adapted code.** Parts of the MDR protocol implementation and Bluetooth RFCOMM connection handling were ported or adapted from **SonyHeadphonesClient** by mos9527, Amr Satrio, and contributors. Those portions retain their upstream MIT license. [Upstream repository](https://github.com/mos9527/SonyHeadphonesClient)
- **Protocol and test data.** The WF-1000XM5 battery tests replay upstream captures from SonyHeadphonesClient. The WH-1000XM6 10-band equalizer implementation was checked against the packet data documented by sony-device-center. [sony-device-center PR #44](https://github.com/marconvcm/sony-device-center/pull/44)

OpenAI Codex assisted with this project's code, interface, and documentation. The maintainer provided requirements, test devices, and feedback. The license for this project's original work is pending. [Source files, upstream revisions, and full license notice](THIRD_PARTY_NOTICES.md)

Sony and model names identify compatible hardware. This independent project has no affiliation with Sony or Huawei.
