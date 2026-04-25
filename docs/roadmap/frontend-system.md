# Shared frontend system — `@zentory/ui`

Goal: marketing + DApp share the same tokens/primitives so the “blue/steel/glass/space” brand can’t drift across repos.

## What to share (minimum viable)

- **Design tokens**: CSS variables, Tailwind preset, typography choices.
- **Utilities**: `.zent-glass`, `.zent-glass-card`, `.zent-gradient-text`, focus rings, scrollbars.
- **Primitives**: button/badge/input classes (or shadcn wrappers) so CTAs never revert to amber/yellow.
- **Shell**: Nav + Footer components (same layout/spacing/blur behavior).

## Package layout (added in protocol repo for now)

`packages/zentory-ui/` ships:
- `styles.css` — canonical CSS variables + glass utilities
- `tailwind-preset.js` — token → Tailwind mapping
- `src/tokens.ts` — typed token export for app logic if needed

## Consumption model (recommended)

- **Option A (best)**: publish `@zentory/ui` to a private registry (GitHub Packages) and pin versions in:
  - `zentorylabs.com`
  - `zentory-protocol-dapp-v2`
- **Option B (bootstrap)**: consume directly via git dependency:
  - `"@zentory/ui": "github:edgeza/zentory-ui#<tag>"`

## Migration steps (both apps)

- Import `@zentory/ui/styles.css` in `app/globals.css` (or equivalent).
- Add Tailwind preset in `tailwind.config.ts`:
  - `presets: [require("@zentory/ui/tailwind-preset")]`
- Replace remaining bespoke button/link styles with shared classes / components.

## Guard rails to prevent drift

- Add a simple visual regression page in both apps (`/ui-sandbox`) that renders:
  - buttons, badges, inputs, cards, tables, nav/footer
- CI gate: run a build and (optionally) screenshot diff in PRs touching UI.

