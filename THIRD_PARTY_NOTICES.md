# Third-party notices

## BatteryHog

The wake-log parsing approach in `rust/crates/covio-core/src/power/pmset.rs` follows BatteryHog.

- Source: https://github.com/luke-fairbanks/BatteryHog
- Copyright: Copyright (c) 2026 Luke Fairbanks
- License: MIT

```text
MIT License

Copyright (c) 2026 Luke Fairbanks

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

## MacFanControl

Covio adapts the SMC access, fan writer and temperature-sensor logic from MacFanControl.

- Source: https://github.com/skydeadpeng/MacFanControl
- Fixed revision: `e5bf78238f7c62b122834a291b15369cb3eb7043`
- Copyright: Copyright (c) 2026 skydeadpeng
- License: MIT

```text
MIT License

Copyright (c) 2026 skydeadpeng

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

## Stats

Covio copies the fan-mode, fan-target, fan-reset and sleep-recovery logic from Stats.

- Source: https://github.com/exelban/stats
- Fixed revision: `7d3f70dcd6a07177d0a529a1b907021eef740158`
- Copyright: Copyright (c) 2019 Serhiy Mytrovtsiy
- License: MIT

```text
MIT License

Copyright (c) 2019 Serhiy Mytrovtsiy

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

## Tendedero

The screenshot toolbar design follows Tendedero.

- Source: https://github.com/alejandrobujan/tendedero
- Copyright: Copyright (c) 2026 Alejandro Buján
- License: MIT

Covio does not use the Tendedero name, icon, or documentation images.

```text
MIT License

Copyright (c) 2026 Alejandro Buján

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

## MLX Swift and model runtime dependencies

Covio links the following Swift packages through `macosApp/Covio.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
Full license texts are in `third_party/licenses/`.

| Package | Revision | License |
| --- | --- | --- |
| `mlx-swift-lm` | `48114eedf3c3d4a682a6b1d644cc5af5c2945d10` | MIT |
| `mlx-swift` | `19601207e9a0de51e03ee6ec0c3c5f3784275075` | MIT |
| `swift-transformers` | `48473106a93b2d8dfb114b82f0628ebbb71734e7` | Apache-2.0 |
| `swift-huggingface` | `c30143a4616f3fa994ee3ab3e3464f752845c07c` | Apache-2.0 |
| `swift-syntax` | `79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1` | Apache-2.0 |
| `swift-jinja` | `1e4d0dc69f7ec1277131fb3853808229c5991825` | Apache-2.0 |
| `swift-crypto` | `da9d28d69ebe3894b18376c8f2395c2f37b8448f` | Apache-2.0 |
| `swift-collections` | `35a1edcb8ebd2bfe251d587f0b69e62af28f508c` | Apache-2.0 |
| `swift-numerics` | `0c0290ff6b24942dadb83a929ffaaa1481df04a2` | Apache-2.0 |
| `swift-asn1` | `3b6410f7dee09eb33cdd26260c5fd47fda19b0e2` | Apache-2.0 |
| `EventSource` | `86b5096ac59ab46e66bd1f6377c604bc1dab0bc2` | MIT |
| `yyjson` | `8b4a38dc994a110abaec8a400615567bd996105f` | MIT |

## Qwen3-VL-2B-Instruct

Covio includes the fixed MLX 4-bit model conversion for local, offline file naming.

- Original model: https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct
- Converted model: https://huggingface.co/mlx-community/Qwen3-VL-2B-Instruct-4bit
- Converted revision: `9c4f5209e57b31f4b9dfba735de3fb983739c9cc`
- License: Apache-2.0
- License file: `third_party/models/Qwen3-VL-2B-Instruct/LICENSE`
- Attribution: `third_party/models/Qwen3-VL-2B-Instruct/NOTICE`
- Fixed file manifest: `macosApp/src/AutoNaming/FileNamingModelManifest.json`


## Kotlin Toolchain wrapper

The `kotlin` and `kotlin.bat` launchers are adapted from the Kotlin Toolchain Compose desktop example.

- Source: https://github.com/JetBrains/kotlin-toolchain
- Fixed tag: `v0.12.1`
- Copyright: Copyright 2000-2026 JetBrains s.r.o. and contributors
- License: Apache-2.0
- License text: https://github.com/JetBrains/kotlin-toolchain/blob/v0.12.1/LICENSE.txt

The committed launchers only download and verify the pinned Kotlin CLI distribution. Covio does not embed the downloaded distribution in the repository.
