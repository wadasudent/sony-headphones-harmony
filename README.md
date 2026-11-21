# Sony Headphones Assistant for HarmonyOS

English · [简体中文](README.zh-CN.md)

An unofficial companion app for Sony Bluetooth headphones and earbuds on HarmonyOS 7 phones and tablets. Check battery levels, switch between noise canceling and ambient sound, adjust the equalizer, and see headphone status on a home screen widget.

## Using the app

- Pair and connect your headphones in system Bluetooth settings, then open the app. Auto-reconnect is enabled by default and gives priority to the last headset used. If several headsets are available and there is no preferred device, select one in the app.
- Long-press the app icon to add a home screen widget. It shows the battery level and listening mode while connected. The readings are hidden when disconnected. Tap the widget to reconnect.
- Choose a light or dark appearance, follow the system appearance, or change the accent color under **More → Appearance** (「更多 → 外观」). Appearance settings, widget readings, and the device identifier used for reconnection are stored locally.

## Headphone compatibility

| Model | Verification |
| --- | --- |
| WH-1000XM6 | Connection and status reporting tested on HarmonyOS phones and tablets. Supports noise canceling, ambient sound, and a 10-band equalizer. |
| WF-1000XM5 | Left earbud, right earbud, and charging case battery levels verified by replaying recorded Bluetooth packets. Testing on HarmonyOS hardware is pending. |
| Other Sony models | Controls appear according to the MDR V2 capabilities reported by the device. Compatibility varies by model. |

Legacy MDR V1 devices and firmware updates are currently unsupported. See the [device test notes](docs/DEVICE_TEST_2026-11-07.md), [firmware update investigation](docs/FIRMWARE_UPDATE_FEASIBILITY.md), and [manual ANC level investigation](docs/XM6_MANUAL_ANC_RESEARCH.md) for details. These notes are in Chinese.

## Building locally

Install DevEco Studio and the HarmonyOS API 26 SDK. Run the following commands from the repository root in Windows PowerShell.

```powershell
.\build.ps1 -CheckOnly
.\build.ps1
```

The first command runs the protocol, widget, and reconnection checks without a device or signing credentials. The second initializes the local configuration from `build-profile.example.json5` and builds a debug HAP. For a custom DevEco Studio installation, pass `-ToolHome 'path to DevEco Studio'` or set `DEVECO_STUDIO_HOME`.

To install on a device, configure your own debug signing in DevEco Studio under **Project Structure → Signing Configs**, then build again. The signed package is written to `entry/build/default/outputs/default/entry-default-signed.hap`. Git ignores local signing configuration, keys, and build packages.

## Credits and licensing

- **Adapted code.** Parts of the MDR protocol implementation and Bluetooth RFCOMM connection handling were ported or adapted from **SonyHeadphonesClient** by mos9527, Amr Satrio, and contributors. Those portions retain their upstream MIT license. [Upstream repository](https://github.com/mos9527/SonyHeadphonesClient)
- **Protocol and test data.** The WF-1000XM5 battery tests replay upstream captures from SonyHeadphonesClient. The WH-1000XM6 10-band equalizer implementation was checked against the packet data documented by sony-device-center. [sony-device-center PR #44](https://github.com/marconvcm/sony-device-center/pull/44)

OpenAI Codex assisted with this project's code, interface, and documentation. The maintainer provided requirements, test devices, and feedback. The license for this project's original work is pending. [Source files, upstream revisions, and full license notice](THIRD_PARTY_NOTICES.md)
