import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { buildSite } from "../scripts/build-site.mjs";
import { fetchGithubData } from "../scripts/github-data.mjs";

const root = join(fileURLToPath(new URL("..", import.meta.url)));
const output = join(root, "dist");
const githubData = {
  schemaVersion: "1.0",
  generatedAt: "2026-11-23T00:00:00.000Z",
  profile: {
    login: "hunter-zen-RU",
    bio: "Software engineer",
    blog: "",
    publicRepos: 39,
    followers: 2
  },
  totalStars: 2,
  repositories: [{
    name: "sample-project",
    description: "A sample project.",
    url: "https://github.com/hunter-zen-RU/sample-project",
    language: "JavaScript",
    stars: 2,
    updatedAt: "2026-11-23T00:00:00.000Z"
  }]
};

test("build publishes the portfolio page, versioned API, and artwork", async () => {
  await buildSite({ githubData });

  const [portfolio, tools, announcements, github] = await Promise.all([
    readFile(join(output, "api/v1/portfolio.json"), "utf8").then(JSON.parse),
    readFile(join(output, "api/v1/tools.json"), "utf8").then(JSON.parse),
    readFile(join(output, "api/v1/announcements.json"), "utf8").then(JSON.parse),
    readFile(join(output, "api/v1/github.json"), "utf8").then(JSON.parse)
  ]);
  assert.equal(portfolio.profile.name, "Hunter Zen RU");
  assert.equal(portfolio.studio.name, "HunruTech");
  assert.ok(tools.tools.length > 0);
  assert.ok(tools.upcoming.length > 0);
  assert.ok(announcements.announcements.length > 0);
  assert.equal(github.profile.publicRepos, 39);
  assert.equal(github.repositories[0].name, "sample-project");

  for (const project of [...tools.tools, ...tools.upcoming]) {
    const artwork = await readFile(join(output, project.image), "utf8");
    assert.match(artwork, /<svg /);
    assert.match(artwork, new RegExp(project.name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    const detailPage = await readFile(join(output, project.page, "index.html"), "utf8");
    assert.match(detailPage, new RegExp(project.name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
  await access(join(output, ".nojekyll"));
  await access(join(output, "scripts/packser/install.sh"));
});

test("GitHub snapshot exposes public profile metrics without private email fields", async () => {
  const fetchImpl = async (url) => {
    const payload = url.endsWith("/repos?per_page=100&sort=updated&type=owner")
      ? [{
          name: "tooling",
          description: "Developer tooling",
          html_url: "https://github.com/hunter-zen-RU/tooling",
          language: "JavaScript",
          stargazers_count: 3,
          updated_at: "2026-11-23T00:00:00.000Z",
          fork: false,
          archived: false
        }, {
          name: "forked-repo",
          description: null,
          html_url: "https://github.com/hunter-zen-RU/forked-repo",
          language: null,
          stargazers_count: 20,
          updated_at: "2026-11-22T00:00:00.000Z",
          fork: true,
          archived: false
        }]
      : {
          login: "hunter-zen-RU",
          bio: "Software engineer",
          blog: "https://example.test",
          public_repos: 39,
          followers: 2,
          email: "private@example.test"
        };
    return {
      ok: true,
      status: 200,
      statusText: "OK",
      json: async () => payload
    };
  };
  const snapshot = await fetchGithubData(fetchImpl);
  assert.equal(snapshot.profile.publicRepos, 39);
  assert.equal(snapshot.totalStars, 3);
  assert.equal(snapshot.repositories.length, 1);
  assert.equal("email" in snapshot.profile, false);
});
