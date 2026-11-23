document.addEventListener("DOMContentLoaded", () => {
  const year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());
  const heroYear = document.getElementById("hero-year");
  if (heroYear) heroYear.textContent = String(new Date().getFullYear());

  const menuToggle = document.querySelector(".menu-toggle");
  const navigation = document.getElementById("primary-nav");
  if (menuToggle && navigation) {
    menuToggle.addEventListener("click", () => {
      const isOpen = menuToggle.getAttribute("aria-expanded") !== "true";
      menuToggle.setAttribute("aria-expanded", String(isOpen));
      navigation.classList.toggle("is-open", isOpen);
    });
    navigation.addEventListener("click", (event) => {
      if (event.target instanceof HTMLAnchorElement) {
        menuToggle.setAttribute("aria-expanded", "false");
        navigation.classList.remove("is-open");
      }
    });
  }

  document.querySelectorAll(".profile-image").forEach((image) => {
    image.addEventListener("error", () => {
      const fallback = image.dataset.fallback;
      if (fallback && image.getAttribute("src") !== fallback) image.setAttribute("src", fallback);
    });
  });

  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };

  const renderProject = (project, planned = false) => {
    const card = element("article", "project-card");
    const imageLink = element("a", "project-image-link");
    const imageUrl = project.page || project.url;
    imageLink.href = imageUrl;
    imageLink.setAttribute("aria-label", `View ${project.name}`);
    if (imageUrl.startsWith("http")) {
      imageLink.target = "_blank";
      imageLink.rel = "noreferrer";
    }

    const image = element("img", "project-image");
    image.src = project.image;
    image.alt = `${project.name} project artwork`;
    image.loading = "lazy";
    image.width = 920;
    image.height = 510;
    imageLink.append(image);

    const body = element("div", "project-card-body");
    const top = element("div", "project-card-top");
    top.append(element("span", "project-category", project.category));
    top.append(element("span", `project-status${planned ? " is-planned" : ""}`, project.status));
    const title = element("h3", "", project.name);
    const description = element("p", "", project.description);
    const link = element("a", "project-link", planned ? "Explore the studio ↗" : "Explore project ↗");
    link.href = project.url;
    if (project.url.startsWith("http")) {
      link.target = "_blank";
      link.rel = "noreferrer";
    }
    body.append(top, title, description, link);
    card.append(imageLink, body);
    card.dataset.search = `${project.name} ${project.category} ${project.description}`.toLowerCase();
    return card;
  };

  const renderPortfolio = async () => {
    const [toolsResponse, portfolioResponse, githubResponse] = await Promise.all([
      fetch("api/v1/tools.json"),
      fetch("api/v1/portfolio.json"),
      fetch("api/v1/github.json")
    ]);
    if (!toolsResponse.ok || !portfolioResponse.ok || !githubResponse.ok) {
      throw new Error("The portfolio data endpoint could not be loaded.");
    }
    const tools = await toolsResponse.json();
    const portfolio = await portfolioResponse.json();
    const github = await githubResponse.json();

    const projectGrid = document.getElementById("project-grid");
    const upcomingGrid = document.getElementById("upcoming-grid");
    if (projectGrid) {
      projectGrid.replaceChildren(...tools.tools.map((project) => renderProject(project)));
      const count = document.getElementById("project-count");
      if (count) count.textContent = String(tools.tools.length).padStart(2, "0");
    }
    if (upcomingGrid) {
      upcomingGrid.replaceChildren(...tools.upcoming.map((project) => renderProject(project, true)));
    }

    const servicesList = document.getElementById("services-list");
    if (servicesList) {
      servicesList.replaceChildren(...portfolio.studio.services.map((service, index) => {
        const row = element("div", "service-item");
        row.append(element("span", "service-index", String(index + 1).padStart(2, "0")));
        row.append(element("h3", "", service));
        row.append(element("span", "", "↗"));
        return row;
      }));
    }

    const craftGrid = document.getElementById("craft-grid");
    if (craftGrid) {
      craftGrid.replaceChildren(...portfolio.skills.map((skill, index) => {
        const card = element("article", "craft-card");
        card.append(element("span", "", `0${index + 1} /`));
        card.append(element("h3", "", skill.title));
        card.append(element("p", "", skill.description));
        return card;
      }));
    }

    const announcement = portfolio.announcements[0];
    const announcementCopy = document.getElementById("announcement-copy");
    if (announcementCopy && announcement) announcementCopy.textContent = announcement.message;

    const repoCount = document.getElementById("github-repo-count");
    const starCount = document.getElementById("github-star-count");
    if (repoCount) repoCount.textContent = Number(github.profile.publicRepos).toLocaleString();
    if (starCount) starCount.textContent = Number(github.totalStars).toLocaleString();

    const githubBio = document.getElementById("github-bio");
    if (githubBio && github.profile.bio) githubBio.textContent = github.profile.bio;

    const repoList = document.getElementById("repo-list");
    if (repoList) {
      const repoCards = github.repositories.map((repo) => {
        const link = element("a", "repo-row");
        link.href = repo.url;
        link.target = "_blank";
        link.rel = "noreferrer";
        link.setAttribute("aria-label", `${repo.name} on GitHub`);

        const summary = element("div", "repo-summary");
        summary.append(element("strong", "", repo.name));
        summary.append(element("p", "", repo.description || "Open-source project on GitHub."));
        const metadata = element("div", "repo-metadata");
        metadata.append(element("span", "", repo.language || "Open source"));
        const updated = new Date(repo.updatedAt);
        const time = element("time", "", Number.isNaN(updated.getTime())
          ? "Recently updated"
          : `Updated ${updated.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" })}`);
        if (!Number.isNaN(updated.getTime())) time.dateTime = updated.toISOString();
        metadata.append(time, element("span", "repo-stars", `★ ${repo.stars}`));
        link.append(summary, metadata);
        return link;
      });
      repoList.replaceChildren(...repoCards);
    }

    const blogLink = document.getElementById("github-blog-link");
    if (blogLink && github.profile.blog) {
      try {
        const blogUrl = new URL(github.profile.blog);
        if (blogUrl.protocol === "https:" || blogUrl.protocol === "http:") {
          blogLink.href = blogUrl.href;
          blogLink.hidden = false;
        }
      } catch {
        blogLink.hidden = true;
      }
    }

    const search = document.getElementById("project-search");
    if (search && projectGrid) {
      search.addEventListener("input", () => {
        const query = search.value.trim().toLowerCase();
        let visibleCount = 0;
        projectGrid.querySelectorAll(".project-card").forEach((card) => {
          const matches = card.dataset.search.includes(query);
          card.hidden = !matches;
          if (matches) visibleCount += 1;
        });
        const emptyState = document.getElementById("empty-projects");
        if (emptyState) emptyState.hidden = visibleCount > 0;
      });
    }
  };

  renderPortfolio().catch((error) => {
    const projectGrid = document.getElementById("project-grid");
    if (projectGrid) {
      const message = element("p", "loading-note", error.message);
      projectGrid.replaceChildren(message);
    }
    const repoList = document.getElementById("repo-list");
    if (repoList) {
      repoList.replaceChildren(element("p", "loading-note", `Could not load live GitHub details: ${error.message}`));
    }
  });

  const feedback = (id, message, isError = false) => {
    const target = document.getElementById(id);
    if (!target) return;
    target.textContent = message;
    target.classList.toggle("is-error", isError);
  };
  const inputValue = (id) => document.getElementById(id)?.value ?? "";

  document.getElementById("format-json")?.addEventListener("click", () => {
    try {
      const formatted = JSON.stringify(JSON.parse(inputValue("json-input")), null, 2);
      document.getElementById("json-input").value = formatted;
      feedback("json-feedback", "Valid JSON · formatted.");
    } catch (error) {
      feedback("json-feedback", `Invalid JSON: ${error.message}`, true);
    }
  });

  document.querySelectorAll("[data-codec]").forEach((button) => {
    button.addEventListener("click", () => {
      try {
        const input = inputValue("codec-input");
        const bytesToBase64 = (bytes) => {
          let binary = "";
          bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
          return btoa(binary);
        };
        if (button.dataset.codec === "encode") {
          document.getElementById("codec-input").value = bytesToBase64(new TextEncoder().encode(input));
          feedback("codec-feedback", "Encoded as UTF-8 Base64.");
        } else {
          const binary = atob(input);
          const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
          document.getElementById("codec-input").value = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
          feedback("codec-feedback", "Decoded from UTF-8 Base64.");
        }
      } catch {
        feedback("codec-feedback", "That value could not be decoded as UTF-8 Base64.", true);
      }
    });
  });

  document.querySelectorAll("[data-url]").forEach((button) => {
    button.addEventListener("click", () => {
      try {
        const input = inputValue("url-input");
        document.getElementById("url-input").value = button.dataset.url === "encode"
          ? encodeURIComponent(input)
          : decodeURIComponent(input);
        feedback("url-feedback", button.dataset.url === "encode" ? "URL component encoded." : "URL component decoded.");
      } catch {
        feedback("url-feedback", "That value is not a valid encoded URL component.", true);
      }
    });
  });

  document.querySelectorAll("[data-clear]").forEach((button) => {
    button.addEventListener("click", () => {
      const input = document.getElementById(button.dataset.clear);
      if (input) input.value = "";
      const feedbackId = `${button.dataset.clear.replace("-input", "")}-feedback`;
      feedback(feedbackId, "");
    });
  });

  document.getElementById("fetch-api")?.addEventListener("click", async () => {
    const endpoint = document.getElementById("api-endpoint")?.value;
    const output = document.getElementById("api-output");
    if (!endpoint || !output) return;
    output.textContent = "Fetching…";
    try {
      const response = await fetch(endpoint);
      if (!response.ok) throw new Error(`Request failed (${response.status}).`);
      output.textContent = JSON.stringify(await response.json(), null, 2);
    } catch (error) {
      output.textContent = `Unable to fetch this endpoint: ${error.message}`;
    }
  });
});
