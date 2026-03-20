# Contributing

Thanks for helping improve `AIAfterEffects`.

## Before You Start

- This project is still **pre-release and unstable**
- expect rough edges, incomplete systems, and breaking changes
- reliability fixes and quality improvements are especially valuable

## Development Setup

1. Open `AIAfterEffects.xcodeproj` in Xcode.
2. Use your own Apple signing setup if Xcode requests one.
3. Add your own `OpenRouter` API key in the in-app settings screen.
4. Optionally add a `Sketchfab` token if you want model search/download support.

## Good First Contributions

- bug fixes
- crash fixes
- generation reliability improvements
- export/rendering fixes
- documentation and onboarding improvements
- tests and reproducible issue reports

## Pull Request Guidelines

- Keep changes focused and easy to review
- Document user-visible behavior changes
- Update docs when setup or behavior changes
- Do not introduce hardcoded credentials, private endpoints, or personal configuration
- Do not commit local debug artifacts such as `.debug_llm/` or Xcode user data

## Reporting Bugs

Please include:

- what you expected
- what actually happened
- clear reproduction steps
- screenshots or recordings if helpful
- whether the issue happens in preview, generation, export, or 3D workflows

## Project Direction

Current priorities:

- stability
- animation quality
- smoother 3D and export behavior
- cleaner contributor onboarding

Thanks for contributing while the project is still maturing.
