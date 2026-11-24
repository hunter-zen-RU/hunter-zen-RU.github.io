# Hunter Zen RU


**Software engineer · Website developer · Digital maker**

I build practical software, scripts, developer tools, and web experiences. I enjoy working across the stack: exploring an idea, shaping the interface, and turning it into something useful. My public work also spans Android projects, automation, and graphic design.

**[Visit my portfolio](https://hunter-zen-ru.github.io)** ·
**[GitHub profile](https://github.com/hunter-zen-RU)** ·
**[HunruTech](https://github.com/hunrutech)** ·
**[Personal site](https://tress9trojan.pythonanywhere.com/)**
**[next repo](https://github.com/hunterzen-RU/hunterzen-RU.github.io)**

## What I do

Through **HunruTech**, I work on software and creative digital services:

- Software, websites, and web applications
- Scripts, automation, and developer utilities
- Android and CLI experiments
- Games and interactive concepts
- Graphic design and digital product work

My approach is hands-on and iterative: understand the problem, make a clear first version, then improve it through use and feedback.

## Selected work

| Project | Focus |
| --- | --- |
| [Packser](https://github.com/hunter-zen-RU/packser) | Linux package-management workflows and terminal tooling |
| [Pynx](https://github.com/hunter-zen-RU/pynx) | Shell-based Python package and project-runner experiment |
| [Konsole-OS](https://github.com/hunter-zen-RU/Konsole-OS) | Android terminal emulator, launcher, and system-management project |
| [LANtern Code](https://github.com/hunter-zen-RU/LANtern-Code) | Mobile coding and project-management experience |
| [Gadian](https://github.com/hunter-zen-RU/Gadian) | APK analysis and reverse-engineering project |
| [Montra](https://github.com/hunter-zen-RU/montra) | WhatsApp and Telegram automation bridge |
| [mpesa-pay](https://github.com/hunter-zen-RU/mpesa-pay) | Node.js M-Pesa payment experiment |
| [kenten-llm](https://github.com/hunter-zen-RU/kenten-llm) | Android offline-chat project |

These are a selection of public projects at different stages. Visit the [repository list](https://github.com/hunter-zen-RU?tab=repositories) for more.

## Developer tools

The portfolio includes browser-based utilities for JSON formatting, UTF-8 Base64, URL encoding, UUID v4 generation, Unix timestamp conversion, and SHA-256 hashing. They run locally in your browser; the project-brief helper only copies your draft and does not send or store it.

The developer lab also includes a searchable, filterable snippet library. Its entries are stored in [`snipets.json`](snipets.json), which is copied into the built site as a static JSON file.

### Public portfolio API

The portfolio publishes read-only JSON endpoints through GitHub Pages:

- [`/api/v1/portfolio.json`](https://hunter-zen-ru.github.io/api/v1/portfolio.json) — profile, studio, skills, projects, and announcements
- [`/api/v1/tools.json`](https://hunter-zen-ru.github.io/api/v1/tools.json) — available tools and upcoming concepts
- [`/api/v1/announcements.json`](https://hunter-zen-ru.github.io/api/v1/announcements.json) — studio announcements
- [`/api/v1/github.json`](https://hunter-zen-ru.github.io/api/v1/github.json) — public GitHub profile snapshot and recent repositories

Fetch the tool catalog from a browser or Node.js:

```js
const response = await fetch("https://hunter-zen-ru.github.io/api/v1/tools.json");
if (!response.ok) {
  throw new Error(`Portfolio API returned ${response.status}`);
}

const { tools, upcoming } = await response.json();
console.log("Available tools:", tools.map((tool) => tool.name));
console.log("Upcoming concepts:", upcoming.map((tool) => tool.name));
```

Or inspect the API with `curl` and `jq`:

```sh
curl --fail --silent --show-error \
  https://hunter-zen-ru.github.io/api/v1/portfolio.json \
  | jq '.profile, .studio'
```

### Run Packser

Clone the [Packser repository](https://github.com/hunter-zen-RU/packser) and start the CLI:

```sh
git clone https://github.com/hunter-zen-RU/packser.git
cd packser
./packser
```

See the [Packser documentation](https://github.com/hunter-zen-RU/packser#readme) for requirements, installation options, and supported package managers.

## Working together

HunruTech is open to thoughtful projects involving software, websites, scripts, tools, games, and design. You can [get in touch through GitHub](https://github.com/hunter-zen-RU) or visit the [HunruTech profile](https://github.com/hunrutech).

## About this portfolio

This site is built with HTML, CSS, browser JavaScript, and a dependency-free Node.js build. Project data lives in [`data/portfolio.json`](data/portfolio.json); the browser API is static and read-only, with no server-side form submission.

To run the checks and build the site locally, use Node.js 20 or newer:

```sh
npm test
npm run build
```

The build refreshes the API files, project artwork, and project detail pages. The GitHub Actions workflow builds and publishes the site on updates to `main`.
# scripts

Pasker _>
```
curl -fsSL https://hunter-zen-ru.github.io/scripts/packser.sh | bash
```



