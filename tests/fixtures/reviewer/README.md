# Recorded reviewer artifacts

Verbatim comment bodies fetched from real pull requests on this repository with
`gh pr view <n> --json comments --jq '.comments[0].body'`. They are **evidence, not
samples** — do not tidy, shorten, or re-wrap them. `tests/review-clearance.test.sh`
drives the classifier against exactly what the reviewer published.

| File | Source | The shape it pins |
|---|---|---|
| `clean-review.pr29.md` | PR #29, head `8f40f2e` | a real review — "No actionable comments were generated in the recent review" |
| `rate-limit-refusal.pr30.md` | PR #30, head `88c106a` | a REFUSAL published behind a green status check — "Review limit reached. Next included review available in 44 minutes" |
| `ack-invocation.pr227.md` | PR #227, 2026-09-14T11:03:30Z | an ACKNOWLEDGEMENT — the auto-generated reply to `@coderabbitai review`, "✅ Action performed / Review finished", posted whether or not a review follows |
| `pr227.api.json`, `pr228.api.json` | PRs #227 and #228, recorded 2026-09-14 | a whole PR as the host served it: `pulls/<n>` facts, `pulls/<n>/reviews` and `issues/<n>/comments`, so the classifier runs over the real payload offline |
| `pr399.api.json` | PR #399, recorded 2026-10-19 | the same three endpoints plus `created_at`/`updated_at` and the head's `committedDate`: a clean `full review` at the head left no review object, only the summary marker edited after the request — it clears although an older review object exists |
| `skip-notice.pr229.md` | PR #229, 2026-09-15T00:03Z | a SKIP NOTICE — "Review skipped / Auto reviews are disabled on this repository … To trigger a single review, invoke the `@coderabbitai review` command". Not a quota refusal: nobody ever asked, and it never reopens by itself (exit 8) |
| `skip-beside-review.pr215.md` | PR #215, head `3e83817` | the SAME skip marker in the SAME body as a completed review's walkthrough — the vendor edits one summary comment in place. #215 carries it beside 2 CodeRabbit review objects, #213 beside 1. A PR that HAS been reviewed must never answer exit 8 |
| `ack-prose.quoted-in-a-review.md` | derived from `ack-invocation.pr227.md` | the acknowledgement's VISIBLE prose with neither machine marker — what lands inside a review body that quotes an ack. The one DERIVED file here: appended to `clean-review.pr29.md` it is a review that reads like an ack, and it must still clear |

The third shape the tests cover — **no reviewer signal at all** — needs no fixture:
it is the absence of these files, and the test constructs it as an empty artifact list.

## Why the refusal fixture is the important one

Both files contain the line

> Reviewing files that changed from the base of the PR and between `<base>` and `<head>`.

and in **both** the `<head>` is the PR's real head SHA. So the commit range is
identical in shape between a review and a refusal, and a detector that keys on it
reads "Review limit reached" as clearance. On #30 that is exactly what happened: it
merged unreviewed and shipped a shell script at mode `100644`. Only the refusal
*language* separates the two files, which is why the classifier tests language first
and the head second.

## Why #227 and #228 are recorded whole

They are the false MERGE-CLEAR. Both cleared at **exit 0** on the reviewer's own
review marker in a comment, while the only CodeRabbit review object on either sits at an
**older** commit and the two review objects at the head are the PR author's own. Nothing
short of the whole payload shows that: the clearance, the stale object and the author's
objects are on three different endpoints.

One field in each is **not** recorded — `mergeable`/`mergeStateStatus`, which the host
reports as `null` once a PR is merged. Both are set to the pre-merge values (`MERGEABLE`,
`CLEAN`), which is what they were: both PRs merged.

## Two properties of these files that the tests assert before relying on them

Both are the kind of thing that goes quietly untrue when a vendor rewords, at which point
every assertion built on them passes vacuously. So they are asserted, not assumed.

1. **The refusal carries the machine-readable `rate limited by coderabbit.ai` sentinel
   and NO review-evidence marker** — no walkthrough, no actionable-comment count. That
   matters because the refusal quotes the PR head: if review evidence could outrank the
   sentinel, this exact file would clear.
2. **Neither file contains a code fence.** So every fence case in the tests is
   constructed — including the one-character bypass they exist for, which is this refusal
   with a single ` ``` ` prepended.

A third shape is deliberately *not* a fixture here, because it is a count rather than a
body: on this repository **18 of 37 pull requests carry a CodeRabbit review object and
exactly one of them was made at that PR's final head**, since `.coderabbit.yaml` sets
`auto_incremental_review: false`. Those are **stale** reviews (exit 4), not refusals —
and 10 of them additionally carry a `Review skipped — Auto incremental reviews are
disabled` notice *inside a real review comment*, which is why refusal prose is outranked
by review evidence found in the same body.

## `host-rendering.txt` — the renderer as the oracle

The two other files here are *bodies*. This one is an **answer**: for each of 154 bodies it
records what **github.com itself** does with it, fetched from the `/markdown` endpoint by
`record-host-rendering.sh`, which is checked in beside it.

It exists because the block reader in `plugin/scripts/review-clearance.sh` models GitHub's
Markdown renderer, and for five rounds it was checked against properties of *itself* — most
recently that one of its two readings is a subset of the other, which an intersection and a
union satisfy by construction. **Only the thing being modelled can contradict a model.**

Three families, and the verdict column is the host's:

| family | verdict | what the suite asserts |
|---|---|---|
| `refusal` | `prose` | the host shows the refusal as readable text ⇒ the gate **must** refuse |
| `refusal` | `quoted` / `hidden` | nothing — a quoted refusal is read as a *discussion* of one |
| `marker` | `visible` | the host shows the marker's characters ⇒ the gate **must not** clear |
| `marker` | `hidden` | nothing — that is the vendor's genuine machine marker |
| `content` | `blank` | the page draws nothing ⇒ the body is **not a claim** |
| `content` | `glyph` | nothing — reading it as blank is the safe direction |

Only one direction of each is asserted, so the battery could pass by refusing everything or
by clearing nothing. Three counters assert that it does not.

**Recorded, not called.** The suite runs offline. Re-record when you add a case, or pass
`--check` to confirm the host still answers the same way:

```bash
tests/fixtures/reviewer/record-host-rendering.sh          # rewrite
tests/fixtures/reviewer/record-host-rendering.sh --check   # 0 if current
```
