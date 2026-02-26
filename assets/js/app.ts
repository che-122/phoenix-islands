import components from 'virtual:components'
import { init } from "./runtime/hydration"
import { hydrate } from "svelte"

init({
  resolve: async (name) => {
    const importFn = components[name];
    if (!importFn) throw new Error(`Component not found: ${name}`);
    const module = await importFn();
    return module.default;
  },
  hydrate: (Component, { target, props }) => {
    hydrate(Component, { target, props })
  }
})

import "phoenix_html"

// Handle flash close
document.querySelectorAll("[role=alert][data-flash]").forEach((el) => {
  el.addEventListener("click", () => {
    el.setAttribute("hidden", "")
  })
})