# Hunter Zen RU · Portfolio

A responsive personal portfolio and HunruTech studio introduction, published to GitHub Pages. Built with semantic HTML, CSS, browser JavaScript, and a dependency-free Node.js build script.

## Develop

Requires Node.js 20 or newer.

```sh
npm test
npm run build
```

The build writes a deployment copy to `dist/` and refreshes the source-compatible files in `api/v1/`, `assets/projects/`, and `projects/`. Commit these generated files when changing portfolio data so both branch-based Pages deployments and Actions deployments include the latest content. Open `dist/index.html` through a local static web server to try the browser utilities and API explorer; API requests need HTTP rather than a `file://` URL.

## Portfolio content

Edit `data/portfolio.json` to update profile details, HunruTech services, skills, achievements, announcements, available projects, and upcoming concepts. Project artwork is generated from each project's `accent`, `background`, and `monogram` values during the build.

Each build fetches the public GitHub profile and repositories to create a fresh, privacy-filtered `api/v1/github.json` snapshot. If the public API is unavailable or rate-limited, the build reports that it is using the last checked-in `data/github-cache.json` instead. GitHub Actions uses its read-only workflow token to avoid anonymous rate limits.

## Static JSON API

GitHub Pages serves these versioned JSON resources directly:

- `/api/v1/portfolio.json` — profile, studio, skills, projects, and announcements
- `/api/v1/tools.json` — available tools and upcoming concepts
- `/api/v1/announcements.json` — studio announcements
- `/api/v1/github.json` — public profile metrics and recently updated repositories

These are static, read-only endpoints; GitHub Pages does not run a Node.js server or accept API writes.
Each project card also opens a generated detail page under `/projects/`.

## Deployment

The GitHub Actions workflow in `.github/workflows/pages.yml` tests and builds the site on pushes to `main`, then publishes `dist/` to GitHub Pages. In repository settings, choose **GitHub Actions** as the Pages build and deployment source.

HunruTech: [github.com/hunrutech](https://github.com/hunrutech)
