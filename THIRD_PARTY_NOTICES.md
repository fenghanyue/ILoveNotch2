# Third-party notices

Every dependency added to the project must be listed below with its license and
copyright notice. Allowed licenses: MIT, BSD, Apache-2.0, ISC, and zlib, and
OFL-1.1 for fonts. CI
(`make licenses`) fails when a resolved package or git submodule is missing
from this file.

## mediaremote-adapter (BSD-3-Clause)

https://github.com/ungive/mediaremote-adapter, v0.7.7
(commit e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6), vendored as a git submodule
in `ThirdParty/mediaremote-adapter`. ILoveNotch ships its framework and perl
script and runs them with the system perl to read now-playing information.

```text
BSD 3-Clause License

Copyright (c) 2025, Jonas van den Berg and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Sparkle (MIT)

https://github.com/sparkle-project/Sparkle, 2.10.0 and later 2.x, a Swift
package of the app target. It checks the signed appcast and installs updates in
release builds (docs/updates.md). Its notice follows; the full license, with the
external notices for bsdiff (BSD-2-Clause), sais-lite (MIT), and ed25519
(zlib), is at https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE.

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## OpenUsage (MIT)

https://github.com/robinebers/openusage at commit
4ce788775e0cb3ec779d353b2ac9f9d7e8765bb4, adapted into
`Sources/NotchUsage/OpenUsage`: the provider integrations, usage models, pricing
engine, and services behind the AI Usage tab. Its price supplement ships as
`Sources/NotchUsage/Resources/pricing_supplement.json`. Each adapted file names
its origin in its header. ILoveNotch's changes: its own cache folder and
User-Agent, no reset-credit claiming, no Antigravity token renewal (it embeds
Antigravity's OAuth client secret), and a rebuilt UI. "OpenUsage" and its
logo are Robin Ebers' trademarks. ILoveNotch doesn't use the logo, and isn't
affiliated with or endorsed by OpenUsage.

```text
MIT License

Copyright (c) 2026 Robin Ebers

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

## LiteLLM price list (MIT)

https://github.com/BerriAI/litellm. `Sources/NotchUsage/Resources/pricing_litellm_snapshot.json`
is a compacted copy of its `model_prices_and_context_window.json`, as bundled
by OpenUsage. The app refreshes it from that file.

```text
MIT License

Copyright (c) 2023 Berri AI

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

## models.dev price list (MIT)

https://github.com/sst/models.dev. `Sources/NotchUsage/Resources/pricing_models_dev_snapshot.json`
is a compacted copy of https://models.dev/api.json, as bundled by OpenUsage.
The app refreshes it from that address.

```text
MIT License

Copyright (c) 2025 models.dev

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

## theSVG provider logos (MIT and CC0-1.0)

https://thesvg.org (https://github.com/glincker/thesvg). The logos in
`Sources/NotchUsage/Resources/Logos` are theSVG's mono icons, under the license
theSVG lists for each:

| File | theSVG icon | License |
| --- | --- | --- |
| `claude.svg` | claude | CC0-1.0 |
| `cursor.svg` | cursor | CC0-1.0 |
| `ollama.svg` | ollama | CC0-1.0 |
| `openrouter.svg` | openrouter | CC0-1.0 |
| `antigravity.svg` | antigravity-google | MIT |
| `codex.svg` | codex-openai | MIT |
| `copilot.svg` | github-copilot | MIT |
| `grok.svg` | grok-xai | MIT |
| `opencode.svg` | opencode | MIT |
| `zai.svg` | zhipu | MIT |

Each logo is its owner's trademark. ILoveNotch shows them only to identify each
provider, and doesn't suggest any endorsement.

```text
MIT License

Copyright (c) 2025 thesvg.org

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

## Tabler Icons (MIT)

https://tabler.io/icons (https://github.com/tabler/tabler-icons)
Copyright (c) 2020-2026 Paweł Kuna

The icons in `Sources/NotchTheme/Icons/tabler` are Tabler Icons 3.48.0's
outline and filled SVGs, unchanged but renamed by role (`media.svg`,
`apps-on.svg`, ...); its `set.json` maps each role to its Tabler name (a filled
one ends in `-filled`).

```text
MIT License

Copyright (c) 2020-2026 Paweł Kuna

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

## Iconoir (MIT)

https://iconoir.com (https://github.com/iconoir-icons/iconoir)
Copyright (c) 2021 Luca Burgio

The icons in `Sources/NotchTheme/Icons/iconoir` are Iconoir 7.12.2's regular
SVGs (solid for `pin-on`), unchanged but renamed by role; `set.json` maps each
role to its Iconoir name.

```text
MIT License

Copyright (c) 2021 Luca Burgio

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

## Fonts (OFL-1.1)

The themes' fonts sit in `Sources/NotchTheme/Fonts/<Family>`, unchanged from
upstream, each with its own `OFL.txt`. Each family's copyright notice, then the
license they share:

- **Doto**, https://github.com/oliverlalan/Doto, Version 1.000, from google/fonts `ofl/doto`
  (commit cc5661d43cd4f9aad5567033a8e15ca28dc35c86): `Doto[ROND,wght].ttf`. Copyright 2024 The
  Doto Project Authors (https://github.com/oliverlalan/Doto).
- **JetBrains Mono**, https://github.com/JetBrains/JetBrainsMono, Version 2.211, from google/fonts
  `ofl/jetbrainsmono` (commit cc5661d43cd4f9aad5567033a8e15ca28dc35c86): `JetBrainsMono[wght].ttf`.
  Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono).
- **Inter**, https://github.com/rsms/inter, Version 4.001, from google/fonts
  `ofl/inter` (commit cc5661d43cd4f9aad5567033a8e15ca28dc35c86):
  `Inter[opsz,wght].ttf`. Copyright 2020 The Inter Project Authors
  (https://github.com/rsms/inter).
- **Newsreader**, https://github.com/productiontype/Newsreader, Version 1.003,
  from google/fonts `ofl/newsreader` (commit
  cc5661d43cd4f9aad5567033a8e15ca28dc35c86): `Newsreader[opsz,wght].ttf`.
  Copyright 2020 The Newsreader Project Authors
  (http://github.com/productiontype/Newsreader).

```text
This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
https://scripts.sil.org/OFL


-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```

## Quick Share protocol definitions (Apache-2.0)

https://github.com/google/nearby and https://github.com/google/ukey2
Copyright 2020–2023 Google LLC

The messages in `Sources/NotchTransfer/QuickShare` (`Frames.swift` and
`Crypto.swift`) follow the field numbers and values of Nearby Connections'
`offline_wire_formats.proto`, Quick Share's `wire_format.proto`, and UKEY2's
`ukey.proto`, `securemessage.proto`, and `securegcm.proto`, so ILoveNotch can
talk to Android phones. No Google code is included: ILoveNotch encodes these
messages itself.

```text
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

## Textream (MIT)

https://github.com/f/textream at commit
2c02f3eee2d8eac238c10a20d3d0e4b021465656
Copyright (c) 2026 Fatih Kadir Akin

The Prompter tab adapts Textream's teleprompter logic into
`Sources/NotchFeatures/Prompter`: following speech (`SpeechListener.swift`, from
`SpeechRecognizer` and `VoiceActivityDetector`), matching what's heard to the
script (`ScriptAlignment.swift`, from `SpeechRecognizer`'s word match and
`SpeechTextAlignment`), and reading a PowerPoint deck's speaker notes
(`PresentationNotes.swift`, from `PresentationNotesExtractor`). Each adapted
file names its origin in its header. ILoveNotch's changes: positions counted in
words rather than characters, recognition kept on this Mac, the system's own
microphone, and its own notch view. ILoveNotch isn't affiliated with or
endorsed by Textream.

```text
MIT License

Copyright (c) 2026 Fatih Kadir Akin

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

<!-- Entry format:
## Name (License)
https://github.com/owner/repo
Copyright (c) YEAR Holder
-->
