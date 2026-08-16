# Teams alpha-review submission template

`submission-template.json` is a deliberately failing checklist for the supervised Microsoft Teams
alpha review. Copy it outside the repository for each real test and change a boolean to `true` only
after the operator observes the condition.

The zero Git SHA, placeholder audio session ID, and false attestations are not evidence. A valid
submission must identify the exact 40-character commit under test and the same session ID emitted by
`audio-capture-verify`. Its `startedAt` and `endedAt` values must also match the strict audio report.
Never commit raw audio, private transcripts, participant names, meeting links, tenant identifiers,
or unredacted screenshots.

Issue severities are `critical`, `high`, `medium`, or `low`. Dispositions are `open`, `fixed`, or
`backlogged`; fixed and backlogged issues require a `resolutionNote`. For example:

```json
{
  "id": "ALPHA-1",
  "severity": "medium",
  "title": "Source window opened slowly",
  "detail": "The synthetic source took four seconds to appear.",
  "disposition": "backlogged",
  "resolutionNote": "Accepted for the supervised alpha and tracked for source-navigation tuning."
}
```

Follow [`docs/supervised-teams-alpha-review.md`](../../docs/supervised-teams-alpha-review.md) for
the complete protocol and decision rules.
