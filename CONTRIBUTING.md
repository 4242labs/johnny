# Contributing

**Status: passively maintained.** johnny is used daily at 42labs and gets commits
regularly — but it is not a staffed product. There is no support rota and no SLA. Issues
and pull requests are welcome and genuinely read; expect a reply in weeks rather than
days, and sometimes not at all. That is capacity, not disinterest. Plan accordingly
before you invest a weekend.

## What's welcome

- **Bug reports with a reproduction.** Name the engine, the voice, and whether it was local or over SSH — that trio is usually the whole diagnosis.
- **New engines.** Adding one is dropping a file in `engines/`; that is the shape the project is built around, and such PRs are the most likely to land.
- **Small, focused pull requests.** One logical change.
- **Documentation** — typos, unclear passages, missing setup steps. Always welcome, usually fast.

## What is unlikely to land

- Large refactors, architecture changes, rewrites.
- Features not discussed in an issue first. **Open the issue before you write the code** — one message, potentially a saved weekend.
- Anything that sends audio, rather than text, across the wire. Reverse-speak synthesizes at the far end on purpose.

## If you need it faster

Fork it. The AGPL-3.0 grants you exactly that. A fork that moves faster than this repo is
a good outcome, not a betrayal — this is a real answer, not a brush-off.

## Before you open a PR

There is no automated test suite — johnny is shell plus a small Python playback server, and
what it does is make noise. Exercise what you touched by hand, and say in the PR what you ran:

```bash
voice list                          # engines + availability
voice voices                        # the registry resolves
voice Fenrir "tests are green"      # the path you changed
voice bench "compare the engines"   # every available engine, back to back
```

If you touched routing, playback, or the server, **test it over SSH too**. Reverse-speak is
the part that breaks silently: it fails closed, so a regression there is not a crash — it is
an utterance that simply never arrives, on a machine you are not sitting at.

## Licensing

johnny is dual-licensed: AGPL-3.0 for open source, commercial terms on request — see
[LICENSING.md](LICENSING.md).

**By submitting a pull request you grant 42labs the right to distribute your contribution
under both the AGPL-3.0 and 42labs' commercial license.** You keep the copyright to what
you wrote. Without this grant a single merged patch would make the commercial half
unsellable, and we would have to refuse it.
