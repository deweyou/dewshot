(() => {
  const root = document.documentElement;
  const system = window.matchMedia("(prefers-color-scheme: dark)");
  const key = "dewshot-theme";
  let preference;
  try {
    preference = localStorage.getItem(key);
  } catch {
    // The switch still works when browser storage is unavailable.
  }

  function refresh() {
    const dark =
      preference === "dark" || (preference !== "light" && system.matches);
    root.dataset.theme = dark ? "dark" : "light";
    const button = document.querySelector(".theme-toggle");
    if (!button) return;
    const english = root.lang === "en";
    const label = dark
      ? english
        ? "Switch to light mode"
        : "切换到浅色主题"
      : english
        ? "Switch to dark mode"
        : "切换到深色主题";
    button.title = label;
    button.setAttribute("aria-label", label);
    button
      .querySelector("use")
      .setAttribute(
        "href",
        "/assets/preferences.svg#" + (dark ? "sun" : "moon"),
      );
    button.hidden = false;
  }

  refresh();
  system.addEventListener("change", refresh);
  document.addEventListener("DOMContentLoaded", () => {
    refresh();
    document.querySelector(".theme-toggle").addEventListener("click", () => {
      preference = root.dataset.theme === "dark" ? "light" : "dark";
      refresh();
      try {
        localStorage.setItem(key, preference);
      } catch {
        // Keep the preference for this page.
      }
    });
  });
})();
