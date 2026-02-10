# Aidbox Documentation

Documentation for [Aidbox](https://www.health-samurai.io/aidbox) — open-source FHIR platform.

## Prerequisites

- [Bun](https://bun.sh) installed

## Setup

```bash
bun install
```

This installs [docs-tools](https://github.com/HealthSamurai/docs-tools) and sets up a pre-push git hook that runs lint before every push.

## Commands

```bash
bun lint                       # run all doc checks
bun lint:check broken-links    # run a single check
bun images:check               # find unoptimized images
bun images:optimize            # convert to WebP + update refs
bun og:generate                # generate OG preview images
```

## Contributing

1. `bun install` (once, sets up tools + pre-push hook)
2. Edit markdown files in `docs/`
3. Update `SUMMARY.md` if adding new pages
4. `bun lint` to check before pushing
5. Submit a pull request

CI runs lint automatically on PRs. Image optimization and OG generation run on push to main.
