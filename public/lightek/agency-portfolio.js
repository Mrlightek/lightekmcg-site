(() => {
  if (window.lightekPortfolioFiltersLoaded) return;
  window.lightekPortfolioFiltersLoaded = true;

  function connectPortfolios() {
    document.querySelectorAll("[data-portfolio]").forEach((portfolio) => {
      const filters = portfolio.querySelector("[data-portfolio-filters]");
      if (!filters || !filters.hidden) return;

      const cards = Array.from(portfolio.querySelectorAll("[data-project-category]"));
      const buttons = Array.from(filters.querySelectorAll("button"));
      const status = portfolio.querySelector("[data-portfolio-status]");

      filters.addEventListener("click", (event) => {
        const selected = event.target.closest("button");
        if (!buttons.includes(selected)) return;

        buttons.forEach((button) => button.setAttribute("aria-pressed", String(button === selected)));
        let count = 0;
        cards.forEach((card) => {
          const visible = selected.hasAttribute("data-filter-all") || selected.dataset.filter === card.dataset.projectCategory;
          card.hidden = !visible;
          if (visible) count += 1;
        });
        status.textContent = `${count} ${count === 1 ? "project" : "projects"} shown`;
      });
      filters.hidden = false;
    });
  }

  document.addEventListener("turbo:load", connectPortfolios);
  document.addEventListener("turbo:before-cache", () => {
    document.querySelectorAll("[data-portfolio-filters]").forEach((filters) => { filters.hidden = true; });
    document.querySelectorAll("[data-project-category]").forEach((card) => { card.hidden = false; });
    document.querySelectorAll("[data-filter-all], [data-portfolio-filters] [data-filter]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.hasAttribute("data-filter-all")));
    });
  });
  connectPortfolios();
})();
