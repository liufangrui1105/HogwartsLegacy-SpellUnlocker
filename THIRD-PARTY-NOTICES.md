# 第三方组件与授权说明 / Third-Party Notices

本仓库**不包含**任何游戏资源（模型、贴图、音频、数据表等），也不包含游戏本体文件。

## 1. UE4SS (RE-UE4SS)

- 项目：https://github.com/UE4SS-RE/RE-UE4SS
- 使用构建：`UE4SS_v3.0.1-201-g7cd4e3f`（experimental 通道）
- 下载来源：https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental
- 许可：MIT License，Copyright (c) 2022 Narknon

本仓库**不携带** UE4SS 二进制。`fetch-ue4ss.ps1` 会在安装时从上述官方 Release 下载未修改的
官方构建（`dwmapi.dll` + `ue4ss\`），仅对 `UE4SS-settings.ini` 做了《霍格沃茨之遗》所需的配置调整：

```ini
[EngineVersionOverride] MajorVersion = 4 / MinorVersion = 27
[General] bUseUObjectArrayCache = false
[Hooks]  HookLocalPlayerExec = 1 / FExecVTableOffsetInLocalPlayer = 0x28
[Debug]  ConsoleEnabled = 1 / GuiConsoleEnabled = 1 / GuiConsoleVisible = 0
```

### MIT License（UE4SS）

```text
MIT License

Copyright (c) 2022 Narknon

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
```

## 2. 游戏与商标

Hogwarts Legacy / 霍格沃茨之遗 及其相关商标、角色、素材归 Warner Bros. Games / Avalanche Software 所有。
本项目为非官方同人 Mod，与权利方无任何隶属或背书关系，仅供个人单机使用。