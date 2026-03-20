# v0.1.0-alpha Release Plan

This is the target plan for the first public alpha release.

## Release Goal

Ship a usable but clearly experimental public build that lets contributors and early adopters:

- run the macOS app locally
- add their own `OpenRouter` key
- try generation and editing flows
- exercise timeline, 3D, and export paths
- report bugs and contribute fixes

## Messaging

The release should be framed as:

- early
- unstable
- under active development
- intended for testers and contributors, not production use

## Must-Have Before Tagging

- no hardcoded credentials in the repository
- working `README.md`, `LICENSE`, `CONTRIBUTING.md`, and `SECURITY.md`
- `.gitignore` covering local artifacts and secrets
- issue templates and PR template present
- CI builds the app successfully
- app builds locally in Xcode

## Alpha Scope

### In scope

- AI-assisted scene generation
- settings flow for BYO `OpenRouter` key
- core timeline editing
- 3D model import/rendering
- export path
- open-source contributor onboarding

### Explicitly not promised

- stability
- consistent generation quality
- polished UX across all flows
- production-ready export reliability
- backwards compatibility between early versions

## Known Risks

- agent or pipeline failures
- malformed or low-quality generations
- rendering and export edge cases
- 3D scene bugs or transform glitches
- integration failures caused by user-provided credentials or third-party service limits

## Suggested Release Notes

### Highlights

- first public alpha release
- bring-your-own-key `OpenRouter` setup
- open-source repo with contribution and security guidance
- contributor-facing issue templates, PR template, and CI

### Warning

This alpha is not stable. Expect bugs, incomplete systems, rough edges, and breaking changes while the project matures.

## Post-Alpha Priorities

- stabilize generation flows
- improve 3D and export reliability
- add tests around critical save/load and rendering paths
- improve onboarding and contributor documentation
- add screenshots, demos, and better release notes for the next public milestone
