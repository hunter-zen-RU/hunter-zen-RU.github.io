import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { fetchGithubData } from "./github-data.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = resolve(root, "dist");
const data = JSON.parse(await readFile(join(root, "data/portfolio.json"), "utf8"));
const generatedRootPaths = [
  join(root, "api/v1"),
  join(root, "assets/projects"),
  join(root, "projects")
];

async function loadGithubSnapshot() {
  try {
    return await fetchGithubData();
  } catch (refreshError) {
    let cachedSnapshot;
    try {
      cachedSnapshot = JSON.parse(await readFile(join(root, "data/github-cache.json"), "utf8"));
    } catch (cacheError) {
      if (cacheError.code === "ENOENT") throw refreshError;
      throw cacheError;
    }
    console.warn(`GitHub refresh failed: ${refreshError.message} Using cached snapshot from ${cachedSnapshot.generatedAt}.`);
    return cachedSnapshot;
  }
}

const xmlEscape = (value) => String(value)
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&apos;");

function renderProjectPage(project) {
  const bullets = project.details.map((detail) => `<li>${xmlEscape(detail)}</li>`).join("\n");
  const stack = (project.stack || []).map((technology) => `<span>${xmlEscape(technology)}</span>`).join("\n");
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="description" content="${xmlEscape(project.description)}" />
    <meta property="og:title" content="${xmlEscape(project.name)} · Hunter Zen RU" />
    <meta property="og:description" content="${xmlEscape(project.description)}" />
    <title>${xmlEscape(project.name)} · Hunter Zen RU</title>
    <link rel="icon" href="../../assets/profile.svg" type="image/svg+xml" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=DM+Sans:wght@400;500;600;700&family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet" />
    <link rel="stylesheet" href="../../style.css" />
  </head>
  <body class="detail-body">
    <header class="detail-header"><div class="container"><a href="../../index.html#work">← Back to selected work</a><span>HUNTER ZEN RU · PROJECT NOTES</span></div></header>
    <main class="container detail-main">
      <a class="detail-back" href="../../index.html#work">← All projects</a>
      <p class="eyebrow">${xmlEscape(project.category)} · ${xmlEscape(project.status)}</p>
      <h1>${xmlEscape(project.name)}</h1>
      <p class="detail-description">${xmlEscape(project.description)}</p>${stack ? `
      <div class="detail-stack"><strong>Built with</strong>${stack}</div>` : ""}
      <img class="detail-artwork" src="../../${xmlEscape(project.image)}" alt="${xmlEscape(project.name)} project artwork" width="920" height="510" />
      <section class="detail-notes">
        <h2>${project.status === "Available" ? "About this project" : "Current direction"}</h2>
        <ul>${bullets}</ul>
      </section>
      <a class="button button-dark" href="${xmlEscape(project.url)}" target="_blank" rel="noreferrer">${project.status === "Available" ? "View source on GitHub" : "Visit HunruTech on GitHub"} <span aria-hidden="true">↗</span></a>
    </main>
    <footer class="detail-footer"><div class="container"><span>© ${new Date().getFullYear()} Hunter Zen RU</span><a href="../../index.html">Portfolio home ↑</a></div></footer>
  </body>
</html>
`;
}

async function writeGeneratedSite(destination, github) {
  for (const project of [...data.tools, ...data.upcoming]) {
    const imagePath = resolve(destination, project.image);
    if (!imagePath.startsWith(`${resolve(destination, "assets/projects")}/`) || !project.image.endsWith(".svg")) {
      throw new Error(`Invalid project artwork path: ${project.image}`);
    }
    await mkdir(dirname(imagePath), { recursive: true });
    const artwork = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 920 510" role="img" aria-label="${xmlEscape(project.name)} project artwork">
  <rect width="920" height="510" fill="${xmlEscape(project.background)}"/>
  <circle cx="750" cy="135" r="205" fill="${xmlEscape(project.accent)}" opacity=".11"/>
  <circle cx="750" cy="135" r="145" fill="none" stroke="${xmlEscape(project.accent)}" stroke-opacity=".28"/>
  <circle cx="750" cy="135" r="94" fill="none" stroke="${xmlEscape(project.accent)}" stroke-opacity=".35"/>
  <path d="M0 416h920" stroke="#fff" stroke-opacity=".13"/>
  <text x="54" y="79" fill="${xmlEscape(project.accent)}" font-family="monospace" font-size="15" letter-spacing="3">${xmlEscape(project.category.toUpperCase())}</text>
  <text x="54" y="319" fill="${xmlEscape(project.accent)}" font-family="sans-serif" font-size="132" font-weight="700" letter-spacing="-8">${xmlEscape(project.monogram)}</text>
  <text x="56" y="376" fill="#f3f2ed" font-family="sans-serif" font-size="29" font-weight="600">${xmlEscape(project.name)}</text>
  <text x="56" y="464" fill="#c6cbbf" font-family="monospace" font-size="12" letter-spacing="2">HUNTER ZEN RU · HUNRUTECH</text>
</svg>`;
    await writeFile(imagePath, artwork);

    const detailPath = resolve(destination, project.page);
    if (!detailPath.startsWith(`${resolve(destination, "projects")}/`) || !project.page.endsWith("/")) {
      throw new Error(`Invalid project detail path: ${project.page}`);
    }
    await mkdir(detailPath, { recursive: true });
    await writeFile(join(detailPath, "index.html"), renderProjectPage(project));
  }

  const api = join(destination, "api/v1");
  await mkdir(api, { recursive: true });
  await writeFile(join(api, "portfolio.json"), `${JSON.stringify(data, null, 2)}\n`);
  await writeFile(join(api, "tools.json"), `${JSON.stringify({
    schemaVersion: data.schemaVersion,
    tools: data.tools,
    upcoming: data.upcoming
  }, null, 2)}\n`);
  await writeFile(join(api, "announcements.json"), `${JSON.stringify({
    schemaVersion: data.schemaVersion,
    announcements: data.announcements
  }, null, 2)}\n`);
  await writeFile(join(api, "github.json"), `${JSON.stringify(github, null, 2)}\n`);
  await writeFile(join(destination, ".nojekyll"), "");
}

async function copySiteTo(destination, includeGenerated) {
  await mkdir(destination, { recursive: true });
  const files = ["index.html", "style.css", "script.js", "README.md"];
  const directories = ["assets", "scripts", "win", "Konsole", "Konsole-plugins", "Konsole-package"];
  if (includeGenerated) {
    files.push(".nojekyll");
    directories.push("api", "projects");
  }
  for (const file of files) {
    await cp(join(root, file), join(destination, file));
  }
  for (const directory of directories) {
    await cp(join(root, directory), join(destination, directory), { recursive: true });
  }
}

export async function buildSite({ githubData, writeRoot = githubData === undefined } = {}) {
  const github = githubData ?? await loadGithubSnapshot();
  if (output === root || relative(root, output).startsWith("..")) {
    throw new Error("Build output must stay inside the repository.");
  }

  if (writeRoot) {
    for (const path of generatedRootPaths) await rm(path, { recursive: true, force: true });
    await rm(join(root, ".nojekyll"), { force: true });
    await writeGeneratedSite(root, github);
  }
  await rm(output, { recursive: true, force: true });
  await mkdir(output, { recursive: true });
  await copySiteTo(output, writeRoot);
  if (!writeRoot) await writeGeneratedSite(output, github);
  console.log(`Built static portfolio, GitHub snapshot, and ${data.tools.length + data.upcoming.length} project pages in ${writeRoot ? "the repository and dist/" : "dist/"}.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await buildSite();
}
