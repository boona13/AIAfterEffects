# AIAfterEffects

AI-driven motion design playground for macOS, built with SwiftUI.

> [!WARNING]
> This project is pre-release and currently unstable. Expect bugs, incomplete workflows, visual glitches, failed generations, rough UX, and breaking changes.

## Status

This project is **pre-release software** and still needs more development before it can be considered stable.

If you open issues or submit PRs, please assume the current focus is on:

- stability
- generation reliability
- animation quality
- contributor friendliness

## What It Does

- Generates and edits motion-design scenes with an AI-assisted workflow
- Builds timelines, objects, effects, and procedural animation systems
- Supports 2D elements, shaders, particles, and 3D model animation
- Exports rendered output from the macOS app

## First Public Alpha

The intended first public milestone is `v0.1.0-alpha`.

That release is meant to make the project:

- runnable by outside contributors
- inspectable and trustworthy
- easy to test with bring-your-own credentials
- honest about current instability

See [`ALPHA_RELEASE_PLAN.md`](ALPHA_RELEASE_PLAN.md) for the planned alpha scope and messaging.

## Requirements

- macOS 15.5+
- Xcode 16.4+ recommended
- An `OpenRouter` account and your own API key for AI features
- Optional: a `Sketchfab` API token if you want searchable downloadable 3D models

## Quick Start

1. Clone the repository.
2. Open `AIAfterEffects.xcodeproj` in Xcode.
3. If Xcode asks for signing changes, set your own Development Team and bundle identifier.
4. Build and run the `AIAfterEffects` scheme.
5. Open the app settings and paste your own `OpenRouter` API key.
6. Optionally add a `Sketchfab` token for 3D model search and download.

## Setup Notes

- The app is macOS-only right now.
- The first launch may feel rough in some areas because the project is still evolving quickly.
- Some AI-driven flows can fail or produce low-quality output; this is expected at the current stage.
- If the project stops building because of local signing settings, reset the Team and bundle identifier in Xcode for your machine.

## Secrets And Credentials

- This repository does **not** include a production `OpenRouter` key.
- User-provided API credentials are stored locally in the macOS Keychain.
- Do not commit local debug traffic, generated logs, or personal credentials.

## Integrations

### OpenRouter

The app uses `OpenRouter` for LLM-backed planning and generation. You must bring your own key from [openrouter.ai](https://openrouter.ai/keys).

### Sketchfab

`Sketchfab` support is optional. If you use it:

- use your own token
- respect asset licenses
- verify redistribution rights before publishing exported or bundled content

## Local Debug Proxy

For development builds, there is an optional local debug proxy:

```bash
python3 debug_server.py
```

That proxy writes request/response files into `.debug_llm/`, which is intentionally gitignored and should stay local-only.

## Repository Hygiene

- `.gitignore` is set up to exclude Xcode user data, local debug traffic, app artifacts, and other machine-specific files.
- This repo should stay free of hardcoded production API keys.
- If you notice a secret-like value in the tree or git history, rotate it immediately and report it privately.

## Known Rough Areas

- The app is still unstable under some generation flows
- Prompting and multi-agent behavior are still evolving
- Export and 3D workflows may still have edge-case bugs
- Some UX and contributor ergonomics are incomplete

## Contributing

Contributions are welcome. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a PR.

GitHub contributors can also use:

- issue templates in `.github/ISSUE_TEMPLATE/`
- the PR template in `.github/pull_request_template.md`
- the alpha milestone plan in [`ALPHA_RELEASE_PLAN.md`](ALPHA_RELEASE_PLAN.md)
- the release checklist in [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)

## Security

If you discover a vulnerability or secret-handling issue, please follow [`SECURITY.md`](SECURITY.md).

## License

This project is licensed under the MIT License. See [`LICENSE`](LICENSE).
