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
    body.append(top, title, description);
    if (project.stack?.length) {
      const stack = element("div", "project-stack");
      project.stack.forEach((technology) => stack.append(element("span", "", technology)));
      body.append(stack);
    }
    body.append(link);
    card.append(imageLink, body);
    card.dataset.group = project.group || "Other";
    card.dataset.search = `${project.name} ${project.category} ${project.description} ${(project.stack || []).join(" ")}`.toLowerCase();
    return card;
  };

  const renderSnippets = async () => {
    const grid = document.getElementById("snippet-grid");
    const filtersContainer = document.getElementById("snippet-filters");
    const search = document.getElementById("snippet-search");
    if (!grid || !filtersContainer) return;

    try {
      const response = await fetch("snipets.json");
      if (!response.ok) throw new Error(`snipets.json returned HTTP ${response.status}.`);
      const payload = await response.json();
      if (!Array.isArray(payload.snippets)) throw new Error("The snippets response does not contain a snippets list.");

      const cards = payload.snippets.map((snippet) => {
        const card = element("article", "snippet-card");
        const header = element("div", "snippet-card-header");
        header.append(element("span", "snippet-category", snippet.category));
        header.append(element("span", "snippet-language", snippet.language));
        const title = element("h3", "", snippet.title);
        const description = element("p", "snippet-description", snippet.description);
        const code = element("code", "", snippet.code);
        const codeBlock = element("pre", "snippet-code");
        codeBlock.append(code);
        const footer = element("div", "snippet-card-footer");
        const tags = element("div", "snippet-tags");
        (snippet.tags || []).forEach((tag) => tags.append(element("span", "", tag)));
        const copyButton = element("button", "button button-outline button-small", "Copy snippet");
        copyButton.type = "button";
        copyButton.addEventListener("click", () => {
          copyText(snippet.code, "snippet-feedback", `${snippet.title} copied.`);
        });
        footer.append(tags, copyButton);
        card.append(header, title, description, codeBlock, footer);
        card.dataset.category = snippet.category;
        card.dataset.search = [
          snippet.title,
          snippet.category,
          snippet.language,
          snippet.description,
          ...(snippet.tags || []),
          snippet.code
        ].join(" ").toLowerCase();
        return card;
      });
      grid.replaceChildren(...cards);

      let selectedCategory = "all";
      const categories = [...new Set(payload.snippets.map((snippet) => snippet.category))].sort();
      const buttons = ["all", ...categories].map((category) => {
        const button = element("button", "filter-chip", category === "all" ? "All snippets" : category);
        button.type = "button";
        button.dataset.category = category;
        button.setAttribute("aria-pressed", String(category === "all"));
        button.classList.toggle("is-active", category === "all");
        button.addEventListener("click", () => {
          selectedCategory = category;
          buttons.forEach((filter) => {
            const active = filter.dataset.category === selectedCategory;
            filter.classList.toggle("is-active", active);
            filter.setAttribute("aria-pressed", String(active));
          });
          updateSnippets();
        });
        return button;
      });
      filtersContainer.replaceChildren(...buttons);

      const updateSnippets = () => {
        const query = search?.value.trim().toLowerCase() || "";
        let visibleCount = 0;
        cards.forEach((card) => {
          const visible = (selectedCategory === "all" || card.dataset.category === selectedCategory)
            && card.dataset.search.includes(query);
          card.hidden = !visible;
          if (visible) visibleCount += 1;
        });
        const count = document.getElementById("snippet-count");
        if (count) count.textContent = String(visibleCount).padStart(2, "0");
        const emptyState = document.getElementById("empty-snippets");
        if (emptyState) emptyState.hidden = visibleCount > 0;
      };

      search?.addEventListener("input", updateSnippets);
      updateSnippets();
    } catch (error) {
      grid.replaceChildren(element("p", "loading-note", `Could not load snippets: ${error.message}`));
      const count = document.getElementById("snippet-count");
      if (count) count.textContent = "00";
    }
  };

  const renderPortfolio = async () => {
    const loadEndpoint = async (path) => {
      const response = await fetch(path);
      if (!response.ok) throw new Error(`${path} returned HTTP ${response.status}.`);
      return response.json();
    };
    const [toolsResult, portfolioResult] = await Promise.allSettled([
      loadEndpoint("api/v1/tools.json"),
      loadEndpoint("api/v1/portfolio.json")
    ]);
    const tools = toolsResult.status === "fulfilled" ? toolsResult.value : null;
    const portfolio = portfolioResult.status === "fulfilled" ? portfolioResult.value : null;

    const projectGrid = document.getElementById("project-grid");
    const upcomingGrid = document.getElementById("upcoming-grid");
    if (projectGrid && tools) {
      projectGrid.replaceChildren(...tools.tools.map((project) => renderProject(project)));
    } else if (projectGrid) {
      const reason = toolsResult.status === "rejected" ? toolsResult.reason.message : "The tools response was invalid.";
      projectGrid.replaceChildren(element("p", "loading-note", `Could not load tools: ${reason}`));
    }
    if (upcomingGrid && tools) {
      upcomingGrid.replaceChildren(...tools.upcoming.map((project) => renderProject(project, true)));
    }

    const search = document.getElementById("project-search");
    const filterContainer = document.getElementById("project-filters");
    if (projectGrid && filterContainer && tools) {
      let selectedGroup = "all";
      const groups = [...new Set(tools.tools.map((project) => project.group || "Other"))].sort();
      const filters = ["all", ...groups].map((group) => {
        const button = element("button", "filter-chip", group === "all" ? "All projects" : group);
        button.type = "button";
        button.classList.toggle("is-active", group === "all");
        button.setAttribute("aria-pressed", String(group === "all"));
        button.addEventListener("click", () => {
          selectedGroup = group;
          filters.forEach((filter) => {
            const active = filter.dataset.group === selectedGroup;
            filter.classList.toggle("is-active", active);
            filter.setAttribute("aria-pressed", String(active));
          });
          updateProjectFilters();
        });
        button.dataset.group = group;
        return button;
      });
      filterContainer.replaceChildren(...filters);

      const updateProjectFilters = () => {
        const query = search?.value.trim().toLowerCase() || "";
        let visibleCount = 0;
        projectGrid.querySelectorAll(".project-card").forEach((card) => {
          const matchesGroup = selectedGroup === "all" || card.dataset.group === selectedGroup;
          const matchesQuery = card.dataset.search.includes(query);
          const visible = matchesGroup && matchesQuery;
          card.hidden = !visible;
          if (visible) visibleCount += 1;
        });
        const count = document.getElementById("project-count");
        if (count) count.textContent = String(visibleCount).padStart(2, "0");
        const emptyState = document.getElementById("empty-projects");
        if (emptyState) emptyState.hidden = visibleCount > 0;
      };

      search?.addEventListener("input", updateProjectFilters);
      updateProjectFilters();
    }

    const servicesList = document.getElementById("services-list");
    if (servicesList && portfolio) {
      servicesList.replaceChildren(...portfolio.studio.services.map((service, index) => {
        const row = element("div", "service-item");
        row.append(element("span", "service-index", String(index + 1).padStart(2, "0")));
        row.append(element("h3", "", service));
        row.append(element("span", "", "↗"));
        return row;
      }));
    } else if (servicesList) {
      const reason = portfolioResult.status === "rejected" ? portfolioResult.reason.message : "The portfolio response was invalid.";
      servicesList.replaceChildren(element("p", "loading-note", `Could not load studio details: ${reason}`));
    }

    const craftGrid = document.getElementById("craft-grid");
    if (craftGrid && portfolio) {
      craftGrid.replaceChildren(...portfolio.skills.map((skill, index) => {
        const card = element("article", "craft-card");
        card.append(element("span", "", `0${index + 1} /`));
        card.append(element("h3", "", skill.title));
        card.append(element("p", "", skill.description));
        return card;
      }));
    } else if (craftGrid) {
      const reason = portfolioResult.status === "rejected" ? portfolioResult.reason.message : "The portfolio response was invalid.";
      craftGrid.replaceChildren(element("p", "loading-note", `Could not load profile details: ${reason}`));
    }

    const announcement = portfolio?.announcements[0];
    const announcementCopy = document.getElementById("announcement-copy");
    if (announcementCopy && announcement) announcementCopy.textContent = announcement.message;

    let github;
    try {
      const githubResponse = await fetch("api/v1/github.json");
      if (!githubResponse.ok) throw new Error(`HTTP ${githubResponse.status}`);
      github = await githubResponse.json();
    } catch (error) {
      const repoList = document.getElementById("repo-list");
      if (repoList) {
        repoList.replaceChildren(element("p", "loading-note", `Recent GitHub details are unavailable: ${error.message}`));
      }
      return;
    }

    const repoCount = document.getElementById("github-repo-count");
    const starCount = document.getElementById("github-star-count");
    if (repoCount) repoCount.textContent = Number(github.profile.publicRepos).toLocaleString();
    if (starCount) starCount.textContent = Number(github.totalStars).toLocaleString();
    const snapshotDate = document.getElementById("github-snapshot-date");
    const generatedAt = new Date(github.generatedAt);
    if (snapshotDate && !Number.isNaN(generatedAt.getTime())) {
      snapshotDate.textContent = `Snapshot refreshed ${generatedAt.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" })}.`;
    }

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

  };

  renderPortfolio().catch((error) => {
    const projectGrid = document.getElementById("project-grid");
    if (projectGrid) {
      const message = element("p", "loading-note", error.message);
      projectGrid.replaceChildren(message);
    }
    const repoList = document.getElementById("repo-list");
  });

  const feedback = (id, message, isError = false) => {
    const target = document.getElementById(id);
    if (!target) return;
    target.textContent = message;
    target.classList.toggle("is-error", isError);
  };
  const inputValue = (id) => document.getElementById(id)?.value ?? "";
  const copyText = async (value, feedbackId, successMessage) => {
    try {
      if (!navigator.clipboard) throw new Error("Clipboard access is unavailable in this browser.");
      await navigator.clipboard.writeText(value);
      feedback(feedbackId, successMessage);
    } catch (error) {
      feedback(feedbackId, `Could not copy: ${error.message}`, true);
    }
  };

  renderSnippets();

  document.getElementById("generate-uuid")?.addEventListener("click", () => {
    try {
      const bytes = crypto.getRandomValues(new Uint8Array(16));
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
      const uuid = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
      document.getElementById("uuid-output").value = uuid;
      document.getElementById("copy-uuid").disabled = false;
      feedback("uuid-feedback", "Generated locally with cryptographic randomness.");
    } catch {
      feedback("uuid-feedback", "Secure random number generation is unavailable.", true);
    }
  });
  document.getElementById("copy-uuid")?.addEventListener("click", () => {
    copyText(inputValue("uuid-output"), "uuid-feedback", "UUID copied.");
  });

  document.getElementById("convert-timestamp")?.addEventListener("click", () => {
    const raw = inputValue("timestamp-input").trim();
    const numeric = Number(raw);
    const epoch = raw && Number.isFinite(numeric)
      ? numeric * (Math.abs(numeric) < 100_000_000_000 ? 1000 : 1)
      : Date.parse(raw);
    const date = new Date(epoch);
    const output = document.getElementById("timestamp-output");
    if (!raw || Number.isNaN(date.getTime()) || !output) {
      feedback("timestamp-feedback", "Enter a Unix timestamp or a valid date.", true);
      if (output) output.hidden = true;
      return;
    }
    output.textContent = [
      `ISO (UTC): ${date.toISOString()}`,
      `Unix seconds: ${Math.floor(date.getTime() / 1000)}`,
      `Unix milliseconds: ${date.getTime()}`
    ].join("\n");
    output.hidden = false;
    feedback("timestamp-feedback", "Converted successfully.");
  });

  document.getElementById("hash-text")?.addEventListener("click", async () => {
    try {
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(inputValue("hash-input")));
      const hash = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
      feedback("hash-feedback", hash);
    } catch {
      feedback("hash-feedback", "SHA-256 requires a secure browser context (HTTPS).", true);
    }
  });

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
      if (button.dataset.clear === "timestamp-input") {
        const output = document.getElementById("timestamp-output");
        if (output) output.hidden = true;
      }
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
      document.getElementById("copy-api-response").disabled = false;
      feedback("api-feedback", "Response loaded.");
    } catch (error) {
      output.textContent = `Unable to fetch this endpoint: ${error.message}`;
      document.getElementById("copy-api-response").disabled = true;
      feedback("api-feedback", "Request failed.", true);
    }
  });

  document.getElementById("copy-api-url")?.addEventListener("click", () => {
    const endpoint = document.getElementById("api-endpoint")?.value;
    if (!endpoint) return;
    copyText(new URL(endpoint, window.location.href).href, "api-feedback", "Endpoint URL copied.");
  });

  document.getElementById("copy-api-response")?.addEventListener("click", () => {
    copyText(document.getElementById("api-output")?.textContent ?? "", "api-feedback", "JSON response copied.");
  });

  document.getElementById("copy-inquiry")?.addEventListener("click", () => {
    const service = document.getElementById("inquiry-service")?.value.trim();
    const notes = inputValue("inquiry-notes").trim();
    if (!service || !notes) {
      feedback("inquiry-feedback", "Choose a service and add a short project description.", true);
      return;
    }
    const draft = `Project inquiry: ${service}\n\n${notes}\n\nContact: https://github.com/hunter-zen-RU`;
    copyText(draft, "inquiry-feedback", "Brief copied. Paste it into a GitHub message to get in touch.");
  });
});
