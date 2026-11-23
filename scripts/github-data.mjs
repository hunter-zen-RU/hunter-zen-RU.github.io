const username = "hunter-zen-RU";
const api = "https://api.github.com";

async function getJson(fetchImpl, url) {
  const response = await fetchImpl(url, {
    headers: {
      accept: "application/vnd.github+json",
      "x-github-api-version": "2022-11-28",
      "user-agent": "hunter-zen-ru-portfolio"
    },
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) {
    throw new Error(`GitHub API request failed (${response.status} ${response.statusText}) for ${url}.`);
  }
  return response.json();
}

export async function fetchGithubData(fetchImpl = fetch) {
  const [profile, repos] = await Promise.all([
    getJson(fetchImpl, `${api}/users/${username}`),
    getJson(fetchImpl, `${api}/users/${username}/repos?per_page=100&sort=updated&type=owner`)
  ]);
  if (!Array.isArray(repos)) {
    throw new Error("GitHub API returned an unexpected repository list.");
  }

  const originalRepos = repos.filter((repo) => !repo.fork);
  return {
    schemaVersion: "1.0",
    generatedAt: new Date().toISOString(),
    profile: {
      login: profile.login,
      bio: profile.bio ?? "",
      blog: profile.blog ?? "",
      publicRepos: profile.public_repos,
      followers: profile.followers
    },
    totalStars: originalRepos.reduce((total, repo) => total + repo.stargazers_count, 0),
    repositories: originalRepos
      .filter((repo) => !repo.archived)
      .slice(0, 6)
      .map((repo) => ({
        name: repo.name,
        description: repo.description ?? "",
        url: repo.html_url,
        language: repo.language ?? "",
        stars: repo.stargazers_count,
        updatedAt: repo.updated_at
      }))
  };
}
