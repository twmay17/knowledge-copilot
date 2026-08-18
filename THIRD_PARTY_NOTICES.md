# Third-Party Notices

OpenOats depends on the following third-party Swift packages. Each is used under its own
license; the license below was verified directly from the package's local checkout under
`OpenOats/.build/checkouts/` (no network lookup required).

This file enumerates the components and the license each is used under. The
`.build/checkouts/` directory is a local build artifact — it is not part of what ships to end
users — so its presence here does not itself satisfy any distribution license requirement.
Anyone redistributing this software, or a derivative of it, is responsible for including each
listed component's full license text alongside their own distribution; the checkout paths
below identify where that text can be found today.

## FluidAudio

- Repository: https://github.com/FluidInference/FluidAudio
- Version: 0.13.5
- License: Apache License 2.0 (verified from `OpenOats/.build/checkouts/FluidAudio/LICENSE`)

  FluidAudio is licensed under the Apache License, Version 2.0, which requires reproducing the
  license and retaining copyright notices in any distribution. This file records that license;
  it does not by itself satisfy that requirement, since `.build/checkouts/` is not part of what
  ships to end users — redistributors must separately include the full Apache-2.0 license text
  (available in the checkout above, or from the upstream repository) alongside their
  distribution. Per the project's own citation request, this distribution attributes FluidAudio
  as follows:

  > FluidInference Team. FluidAudio: Local Speaker Diarization, ASR, and VAD for Apple Platforms

## LaunchAtLogin-Modern

- Repository: https://github.com/sindresorhus/LaunchAtLogin-Modern
- Version: 1.1.0
- License: MIT (verified from `OpenOats/.build/checkouts/LaunchAtLogin-Modern/license`)
- Copyright (c) Sindre Sorhus <sindresorhus@gmail.com>

## Sparkle

- Repository: https://github.com/sparkle-project/Sparkle
- Version: 2.9.0
- License: MIT (verified from `OpenOats/.build/checkouts/Sparkle/LICENSE`)
- Copyright (c) Andy Matuschak and contributors (full copyright list in the checkout's LICENSE
  file). Sparkle's own LICENSE file additionally bundles BSD-style notices for its embedded
  bsdiff/bspatch and sais-lite components; those terms are included in that same file and are
  not restated here.

## WhisperKit

- Repository: https://github.com/argmaxinc/WhisperKit
- Version: 0.17.0
- License: MIT (verified from `OpenOats/.build/checkouts/WhisperKit/LICENSE`)
- Copyright (c) 2024 argmax, inc.

---

## Transitive dependencies

The packages above pull in the following transitive dependencies, per
`OpenOats/Package.resolved`. Licenses were verified the same way — directly from each
package's local checkout under `OpenOats/.build/checkouts/`. Only the component, version, and
license are listed; the full license text is not inlined here and can be found at the checkout
path in the last column (run `swift package resolve` from `OpenOats/` first if a checkout is
missing locally).

| Package | Version | License | License file (under `OpenOats/.build/checkouts/`) |
|---|---|---|---|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.7.1 | Apache License 2.0 | `swift-argument-parser/LICENSE.txt` |
| [swift-asn1](https://github.com/apple/swift-asn1) | 1.5.1 | Apache License 2.0 | `swift-asn1/LICENSE.txt` |
| [swift-collections](https://github.com/apple/swift-collections) | 1.3.0 | Apache License 2.0 | `swift-collections/LICENSE.txt` |
| [swift-crypto](https://github.com/apple/swift-crypto) | 4.2.0 | Apache License 2.0 | `swift-crypto/LICENSE.txt` |
| [swift-jinja](https://github.com/huggingface/swift-jinja) | 2.3.2 | Apache License 2.0 | `swift-jinja/LICENSE` |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | 1.1.9 | Apache License 2.0 | `swift-transformers/LICENSE` |
| [yyjson](https://github.com/ibireme/yyjson) | 0.12.0 | MIT (Copyright (c) 2020 YaoYuan) | `yyjson/LICENSE` |

As with the direct dependencies above, this table records each component and its license;
redistributors are responsible for including each one's full license text alongside their own
distribution.
