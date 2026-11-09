# docs-theme

The one place the zerkersec.io documentation look lives. Every project's docs (KrakenHashes,
Heimdall Listener, …) are plain MkDocs Material sites versioned with `mike`; a small Cloudflare
Worker serves each project's published tree and applies this theme on the way out. Project
repos keep no theme files at all.

```
theme/      zerkersec.css + self-hosted fonts (injected into every page as /_theme/…)
worker/     worker.js (serve-time theming, prefix handling) + wrangler.template.jsonc
scripts/    preview.sh: run a project's docs locally exactly as the Worker serves them
.github/workflows/   reusable workflows a project calls
```

## Adopting it in a project

1. `mkdocs.yml`: Material theme, `font: false`, `palette: { scheme: slate }`,
   `extra: { version: { provider: mike } }`, `site_url: https://zerkersec.io/<project>/docs/`.
   No `custom_dir`, no extra CSS.
2. `requirements-docs.txt` with `mkdocs`, `mkdocs-material`, `mike` and any plugins you use.
3. Three caller workflows (all need `permissions: contents: write` for mike's pushes):

```yaml
# .github/workflows/docs-dev.yml
name: Docs (dev)
on:
  push:
    branches: [main]
    paths: [docs/**, README.md, mkdocs.yml, requirements-docs.txt]
permissions: { contents: write }
jobs:
  dev:
    uses: ZerkerEOD/docs-theme/.github/workflows/mkdocs-dev.yml@main

# .github/workflows/docs-version.yml
name: Docs (version)
on:
  push: { tags: ["v*"] }
  workflow_dispatch:
    inputs:
      version: { description: "Version (e.g. 2.0.0)", required: true, type: string }
      set_as_latest: { description: "Point latest at it", type: boolean, default: true }
permissions: { contents: write }
jobs:
  version:
    uses: ZerkerEOD/docs-theme/.github/workflows/mkdocs-version.yml@main
    with:
      version: ${{ github.event.inputs.version || github.ref_name }}
      set_as_latest: ${{ github.event.inputs.set_as_latest != 'false' }}

# .github/workflows/docs-deploy.yml
name: Docs (deploy)
on:
  workflow_run:
    workflows: ["Docs (dev)", "Docs (version)"]
    types: [completed]
  workflow_dispatch:
jobs:
  deploy:
    if: ${{ github.event_name == 'workflow_dispatch' || github.event.workflow_run.conclusion == 'success' }}
    uses: ZerkerEOD/docs-theme/.github/workflows/deploy-worker.yml@main
    with:
      worker_name: <project>-docs
      docs_prefix: /<project>/docs
      project_name: <project>
      project_url: https://zerkersec.io/<project>/
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

4. In zerkersec.io, add a service binding to `<project>-docs` and the project to its docs map.

`mike` pushes with the Actions token, which never triggers `on: push`; that is why the deploy
workflow listens to `workflow_run` instead.

## Local preview

```sh
scripts/preview.sh <project-repo> <worker-name> <docs-prefix> [port] [old-origin]
```

Run zerkersec.io's `wrangler dev` alongside; its service binding finds the preview through
wrangler's local dev registry, so the docs appear under `http://localhost:8788<docs-prefix>/`.

## Licence

MIT for everything in this repository except the fonts: Inter and JetBrains Mono are
redistributed under the SIL Open Font License 1.1 (see `theme/assets/fonts/LICENSE-*.txt`).
