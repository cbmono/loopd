# NOTICE — modern-web

The files under `guides/` are **condensed derivatives** of Google Chrome's "Modern Web
Guidance" skill, rewritten for size: every rule, API name and compatibility note that
changes what code an engineer writes was kept; explanatory prose, repeated preambles,
duplicate examples and whole categories a product web-app engineer rarely applies were
dropped. They are not the upstream text and must not be quoted as it.

| | |
|---|---|
| Upstream | https://github.com/GoogleChrome/modern-web-guidance |
| Upstream path | `skills/modern-web-guidance/` — `SKILL.md` and `guides/<category>/<guide>.md` |
| Pinned commit | `4f2b13e25c5815b3f080ca0d983e828d96561a0f` (upstream plugin version 0.0.196) |
| Licence | Apache License, Version 2.0 (SPDX `Apache-2.0`) — full text in `LICENSE` beside this file |
| Copyright | Google LLC and the modern-web-guidance contributors |
| Upstream attribution, retained | "Portions of the documentation in this project are derived from MDN Web Docs by Mozilla Contributors and W3C, WHATWG, and IETF specifications." |
| Modifications | Condensed and merged per category by the loopd maintainers (2026-10-29). Each guide's first two lines name its upstream directory and the pinned commit. Dropped at the category level: `built-in-ai`, `wasm`, `pwa`, `webmcp`; `ui-atoms` is merged into `ui-components.md`. Dropped guides inside a kept category are listed in the pull request that introduced the file. |

Licensed under the Apache License, Version 2.0 (the "License"); you may not use these
files except in compliance with the License. Unless required by applicable law or agreed
to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License
for the specific language governing permissions and limitations under the License.

## Re-sync

The guides are condensed by hand, so a re-sync is a diff of the **upstream** between the
pinned commit and a newer one, read per category, and folded into the matching guide — never
a regeneration. From a scratch directory:

```sh
git clone https://github.com/GoogleChrome/modern-web-guidance mwg && cd mwg
OLD=4f2b13e25c5815b3f080ca0d983e828d96561a0f; NEW=$(git rev-parse HEAD)
git diff --stat "$OLD" "$NEW" -- skills/modern-web-guidance/guides          # what moved, per category
git diff "$OLD" "$NEW" -- skills/modern-web-guidance/guides/<category>      # one category at a time
git diff "$OLD" "$NEW" -- skills/modern-web-guidance/SKILL.md               # router and framework notes
git log --oneline "$OLD..$NEW" -- skills/modern-web-guidance                # the commits in between
```

Then, for each changed category: fold the new or changed rules into `guides/<category>.md`,
drop what upstream removed, update the sha on line 2 of every guide and the `Pinned commit`
row above to `$NEW`, keep each guide under 250 lines and the directory under 120 KB, and run
`tests/modern-web-skill.test.sh`, which checks that every guide carries the sha this file
names.

## Condensation record (2026-10-29, upstream 4f2b13e2)

| Category | Guides | Upstream bytes | Condensed | Lines | Bytes |
|---|---|---|---|---|---|
| accessibility | 4 | 67,311 | accessibility.md | 85 | 8,832 |
| css | 18 | 113,660 | css.md | 96 | 10,991 |
| forms | 19 | 146,642 | forms.md | 99 | 11,058 |
| html | 8 | 60,115 | html.md | 89 | 8,890 |
| js | 5 | 35,061 | js.md | 67 | 6,662 |
| performance | 26 | 149,257 | performance.md | 102 | 11,464 |
| privacy | 1 | 11,213 | privacy.md | 67 | 3,874 |
| security | 17 | 199,977 | security.md | 98 | 17,491 |
| ui-components + ui-atoms | 14 + 12 | 164,341 + 86,519 | ui-components.md | 103 | 19,838 |
| ui-behaviors | 37 | 262,950 | ui-behaviors.md | 68 | 11,882 |
| visual-design | 22 | 171,030 | visual-design.md | 66 | 10,062 |
| dropped: built-in-ai, wasm, pwa, webmcp | 10 | 90,260 | — | — | 0 |
| SKILL.md + NOTICE.md + LICENSE | — | — | — | — | ~3.5 KB + ~2.9 KB + 11,358 |
| **total** | 193 | 1,558,336 | 11 guides | 940 | ceiling 131,072 on loadable bytes; measured 128,436 |

