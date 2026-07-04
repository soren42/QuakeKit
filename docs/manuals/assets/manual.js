(function () {
  function addPrintActions() {
    if (window.matchMedia && window.matchMedia("print").matches) return;
    const bar = document.createElement("div");
    bar.className = "print-actions";
    const print = document.createElement("button");
    print.type = "button";
    print.textContent = "Print / Save PDF";
    print.addEventListener("click", () => window.print());
    const top = document.createElement("button");
    top.type = "button";
    top.textContent = "Top";
    top.addEventListener("click", () => window.scrollTo({ top: 0, behavior: "smooth" }));
    bar.append(print, top);
    document.body.prepend(bar);
  }

  function stampVersion() {
    const nodes = document.querySelectorAll("[data-build-date]");
    const date = new Date(document.lastModified || Date.now());
    const value = date.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });
    nodes.forEach((node) => { node.textContent = value; });
  }

  document.addEventListener("DOMContentLoaded", () => {
    addPrintActions();
    stampVersion();
  });
})();
