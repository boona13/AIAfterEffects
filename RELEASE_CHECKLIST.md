# Release Checklist

Use this before tagging or announcing a public release.

## Safety

- [ ] Re-scan the repo for hardcoded API keys, tokens, and secrets
- [ ] Confirm `.debug_llm/` and other local artifacts are not included
- [ ] Confirm no personal `xcuserdata/` files are included
- [ ] Rotate any credential that was ever committed by mistake

## Product Readiness

- [ ] Build the app successfully in Xcode
- [ ] Smoke test generation, timeline editing, 3D rendering, and export
- [ ] Verify settings flow for adding an `OpenRouter` key
- [ ] Verify optional `Sketchfab` flow still works

## Documentation

- [ ] `README.md` reflects current setup and known limitations
- [ ] `CONTRIBUTING.md` reflects current contributor workflow
- [ ] `SECURITY.md` reflects current reporting guidance
- [ ] Instability warning is still clear and accurate

## GitHub

- [ ] CI workflow passes
- [ ] Issue templates look correct
- [ ] PR template still matches the project workflow
- [ ] License is present

## Release Notes

- [ ] Summarize major changes
- [ ] Call out known regressions or unstable areas
- [ ] Remind users to expect issues while the project is still maturing
