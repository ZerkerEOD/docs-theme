#!/usr/bin/env bash
# Local preview of a project's docs exactly as the zerkersec docs Worker serves them.
#
#   scripts/preview.sh <project-repo> <worker-name> <docs-prefix> [port] [old-origin]
#   scripts/preview.sh clean <worker-name>
#
# Example:
#   scripts/preview.sh ~/Programming/passwordCracking/krakenhashes krakenhashes-docs /krakenhashes/docs 8789 https://zerkereod.github.io/krakenhashes
#   scripts/preview.sh ~/Programming/heimdall-listner heimdall-docs /heimdall-listener/docs 8790
#
# What it does: keeps a cache under ~/.cache/zerkersec-docs/<worker-name>/ holding the
# project's published gh-pages tree (fetched once, if the remote has one) or a minimal
# mike tree, rebuilds dev/ from the project checkout with its own virtualenv, copies the
# theme, and runs `wrangler dev` so zerkersec.io's local `wrangler dev` can bind to it.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cache_root="${ZS_DOCS_CACHE:-$HOME/.cache/zerkersec-docs}"

if [ "${1:-}" = "clean" ]; then
  rm -rf "$cache_root/${2:?worker name}"; echo "[docs] removed $cache_root/$2"; exit 0
fi
project="$(cd "${1:?project path}" && pwd)"; worker="${2:?worker name}"; prefix="${3:?docs prefix}"; port="${4:-8789}"; old_origin="${5:-}"
cache="$cache_root/$worker"; site="$cache/site"; wdir="$cache/worker"
name="$(basename "$project")"
venv="${ZS_DOCS_VENV:-$HOME/.local/share/venvs/$name-docs}"

# virtualenv per project, reinstalled only when requirements-docs.txt changes
req="$project/requirements-docs.txt"; stamp="$venv/.requirements.sha256"
if [ ! -x "$venv/bin/mkdocs" ] || [ "$(sha256sum "$req" | cut -c1-64)" != "$(cat "$stamp" 2>/dev/null || true)" ]; then
  echo "[docs] installing docs requirements into $venv"
  python3 -m venv "$venv"; "$venv/bin/pip" install -q -r "$req"; sha256sum "$req" | cut -c1-64 > "$stamp"
fi

# published tree (once) or a minimal mike tree
if [ ! -f "$site/versions.json" ]; then
  mkdir -p "$site"
  if git -C "$project" ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
    echo "[docs] fetching published docs (gh-pages) …"
    git -C "$project" fetch -q origin gh-pages
    git -C "$project" archive FETCH_HEAD | tar -x -C "$site"; rm -rf "$site/.git" "$site/.nojekyll"
  else
    echo "[docs] no gh-pages yet: using a dev-only tree"
    printf '[{"version":"dev","title":"dev","aliases":[]}]\n' > "$site/versions.json"
    printf '<!doctype html><meta charset=utf-8><title>Redirecting</title><meta http-equiv=refresh content="0; url=dev/"><script>location.replace("dev/"+location.search+location.hash)</script>\n' > "$site/index.html"
  fi
fi

echo "[docs] building dev/ from $project …"
rm -rf "$site/dev"; (cd "$project" && "$venv/bin/mkdocs" build --strict -q -d "$site/dev")

mkdir -p "$site/_theme/stylesheets" "$site/_theme/assets/fonts" "$wdir"
cp "$here/theme/stylesheets/zerkersec.css" "$site/_theme/stylesheets/"; cp "$here/theme/assets/fonts/"*.woff2 "$site/_theme/assets/fonts/"
cp "$here/worker/worker.js" "$wdir/worker.js"
sed -e "s|__WORKER_NAME__|$worker|; s|__DOCS_PREFIX__|$prefix|; s|__PROJECT_NAME__|${prefix#/}|; s|__PROJECT_NAME__|$name|; s|__PROJECT_URL__|https://zerkersec.io/${prefix%/docs}/|; s|__OLD_ORIGIN__|$old_origin|; s|__ASSETS_DIR__|../site|" "$here/worker/wrangler.template.jsonc" > "$wdir/wrangler.jsonc"
# PROJECT_NAME is the first path segment of the prefix (e.g. krakenhashes)
proj_name="${prefix#/}"; proj_name="${proj_name%%/*}"; sed -i "s|\"PROJECT_NAME\": \"[^\"]*\"|\"PROJECT_NAME\": \"$proj_name\"|; s|\"PROJECT_URL\": \"[^\"]*\"|\"PROJECT_URL\": \"https://zerkersec.io/$proj_name/\"|" "$wdir/wrangler.jsonc"

echo "[docs] $(find "$site" -type f | wc -l) files; $worker on http://127.0.0.1:$port/ (prefix $prefix)"
cd "$wdir" && exec npx --yes wrangler@4 dev --port "$port"
