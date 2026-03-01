import components from 'virtual:components'
import { init } from "./runtime/hydration"
import { hydrate, Component, unmount } from "svelte"

init<Component>({
  resolve: async (name) => {
    const importFn = components[name];
    if (!importFn) throw new Error(`Component not found: ${name}`);
    const module = await importFn();
    return module.default;
  },
  hydrate: (Component, { target, props }) => {
    hydrate(Component, { target, props })
  },
  destroy: (component) => {
    unmount(component)
  }
})

import "phoenix_html"

// Handle flash close
document.querySelectorAll("[role=alert][data-flash]").forEach((el) => {
  el.addEventListener("click", () => {
    el.setAttribute("hidden", "")
  })
})