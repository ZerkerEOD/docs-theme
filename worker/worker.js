// zerkersec docs Worker: serves a mike-built MkDocs tree from static assets and
// applies the zerkersec.io theme at serve time, so every published version of a
// project's docs follows the site standard without being rebuilt.
//
// Vars (wrangler.jsonc, filled from wrangler.template.jsonc by the deploy workflow):
//   DOCS_PREFIX   path the site mounts this Worker at, e.g. /krakenhashes/docs
//   PROJECT_NAME  banner link label, e.g. krakenhashes
//   PROJECT_URL   banner link target, e.g. https://zerkersec.io/krakenhashes/
//   OLD_ORIGIN    optional: absolute site_url baked into older builds, rewritten under the prefix
//
// zerkersec.io forwards the original request over a service binding; the prefix
// is stripped here so the mike tree (/<version>/..., /versions.json) maps one to
// one, and redirect targets get the prefix back. Theme files live in /_theme.
const SITE = 'https://zerkersec.io';

function banner(env) {
  return `<div data-md-component="announce"><aside class="md-banner"><div class="md-banner__inner md-grid md-typeset">` +
    `<a href="${SITE}/" class="zs-brand">zerkersec<b>.io</b></a>` +
    (env.PROJECT_NAME ? `<a href="${env.PROJECT_URL || SITE + '/' + env.PROJECT_NAME + '/'}">${env.PROJECT_NAME}</a>` : '') +
    `<a href="${SITE}/projects/">projects</a><a href="${SITE}/blog/">blog</a></div></aside></div>`;
}
const FOOTER = `<div class="zs-footer"><span>&copy; Aaron Sullivan (ZerkerEOD) &middot; free and open source</span>` +
  `<a href="${SITE}/privacy/">privacy</a><a href="${SITE}/terms/">terms</a>` +
  `<a href="https://github.com/ZerkerEOD" rel="me noopener">github</a><a href="https://x.com/ZerkerEOD" rel="me noopener">x</a>` +
  `<a href="https://www.linkedin.com/in/zerkereod/" rel="me noopener">linkedin</a></div>`;

/** Relative path from a page at `pathname` (inside the tree) back to the tree root. */
function rootFrom(pathname) {
  const dirs = pathname.replace(/\/[^/]*$/, '').split('/').filter(Boolean).length;
  return dirs ? '../'.repeat(dirs) : './';
}

/** Theme one HTML document. Idempotent: pages that already carry the theme are left alone. */
export function themeHtml(html, pathname, env) {
  const prefix = env.DOCS_PREFIX || '';
  if (env.OLD_ORIGIN && html.includes(env.OLD_ORIGIN)) html = html.split(env.OLD_ORIGIN).join(SITE + prefix);
  html = html.replace(/<link[^>]*fonts\.googleapis\.com[^>]*>/gi, '');
  if (!/zerkersec\.css/.test(html)) {
    html = html.replace(/<\/head>/i, `<link rel="stylesheet" href="${rootFrom(pathname)}_theme/stylesheets/zerkersec.css"></head>`);
  }
  html = html.replace(/data-md-color-scheme=["']?default["']?/, 'data-md-color-scheme="slate"');
  if (!html.includes('zs-brand')) html = html.replace(/(<body[^>]*>)/i, `$1${banner(env)}`);
  if (!html.includes('zs-footer')) html = html.replace(/<\/body>/i, `${FOOTER}</body>`);
  return html;
}

export default {
  async fetch(request, env) {
    const prefix = env.DOCS_PREFIX || '';
    const url = new URL(request.url);
    const prefixed = prefix && (url.pathname === prefix || url.pathname.startsWith(prefix + '/'));
    if (prefixed) url.pathname = url.pathname.slice(prefix.length) || '/';

    const res = await env.ASSETS.fetch(new Request(url.toString(), request));
    const headers = new Headers(res.headers);

    const loc = headers.get('location');
    if (loc && prefixed && loc.startsWith('/') && !loc.startsWith(prefix)) headers.set('location', prefix + loc);

    if (url.pathname.startsWith('/_theme/')) headers.set('cache-control', 'public, max-age=86400');

    const type = headers.get('content-type') || '';
    if (type.includes('text/html') && request.method !== 'HEAD') {
      headers.set('cache-control', 'public, max-age=300');
      headers.delete('content-length');
      return new Response(themeHtml(await res.text(), url.pathname, env), { status: res.status, headers });
    }
    return new Response(res.body, { status: res.status, headers });
  },
};
