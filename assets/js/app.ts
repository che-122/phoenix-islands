import components from "virtual:components";
import { init } from "./runtime/hydration";
import { hydrate, type Component, unmount } from "svelte";

init<Component<any, Record<string, any>>, Record<string, any>>({
  resolve: async (name) => {
    const importFn = components[name];
    if (!importFn) throw new Error(`Component not found: ${name}`);
    const module = await importFn();
    return module.default;
  },
  hydrate: (Component, { target, props }) => {
    return hydrate(Component, { target, props });
  },
  destroy: (component) => {
    void unmount(component);
  },
});

import "phoenix_html";

// Handle flash close
document.querySelectorAll("[role=alert][data-flash]").forEach((el) => {
  el.addEventListener("click", () => {
    el.setAttribute("hidden", "");
  });
});

const syncDebugPanels = () => {
  const debugEnabled = window.localStorage.getItem("debug") === "true";
  document
    .querySelectorAll<HTMLElement>("[data-debug-panel]")
    .forEach((panel) => {
      panel.classList.toggle("hidden", !debugEnabled);
    });
};

syncDebugPanels();

type ScrollSnapshot = {
  top: number;
  stableKey: string | null;
};

const pendingScrollRestore = new Map<string, ScrollSnapshot>();

const getScrollableContainerState = () => {
  return document.querySelectorAll<HTMLElement>("[data-swup-scroll-container]");
};

const captureScrollableContainers = () => {
  pendingScrollRestore.clear();

  getScrollableContainerState().forEach((container) => {
    if (!container.id) return;

    pendingScrollRestore.set(container.id, {
      top: container.scrollTop,
      stableKey: container.getAttribute("data-scroll-stable-key"),
    });
  });
};

const restoreScrollableContainers = () => {
  getScrollableContainerState().forEach((container) => {
    if (!container.id) return;

    const snapshot = pendingScrollRestore.get(container.id);
    if (!snapshot) return;

    const currentStableKey = container.getAttribute("data-scroll-stable-key");
    if (snapshot.stableKey !== currentStableKey) return;

    container.scrollTop = snapshot.top;
  });
};

const restoreScrollableContainersAfterTransition = () => {
  restoreScrollableContainers();

  window.requestAnimationFrame(() => {
    restoreScrollableContainers();
  });
};

declare global {
  interface Window {
    Swup: any;
    SwupFragmentPlugin: any;
    SwupPreloadPlugin: any;
    SwupFormsPlugin: any;
    SwupScrollPlugin: any;
  }
}

const swup = new window.Swup({
  shouldResetScrollPosition: false,
  plugins: [
    new window.SwupFragmentPlugin({
      rules: [
        {
          name: "feed-modal",
          from: [
            "/list",
            "/list/:feed_id/entries",
            "/list/:feed_id/entries/:entry_id",
            "/feeds/new",
          ],
          to: [
            "/list",
            "/list/:feed_id/entries",
            "/list/:feed_id/entries/:entry_id",
            "/feeds/new",
          ],
          containers: [
            "#feed-modal",
            "#main-content",
            "#sidebar-feeds-content",
            "#sidebar-entries-content",
          ],
        },
      ],
    }),
    new window.SwupPreloadPlugin(),
    new window.SwupFormsPlugin(),
  ],
});

const normalizePath = (url: string) => {
  try {
    return new URL(url, window.location.origin).pathname;
  } catch {
    return null;
  }
};

swup.hooks.on("form:submit", (_visit: unknown, { el }: { el: Element }) => {
  // Make sure we skip cache when submitting the add-feed form
  if (!(el instanceof HTMLFormElement)) return;

  const submittedPath = normalizePath(el.action || window.location.href);
  const currentPath = normalizePath(window.location.href);

  swup.cache.prune((url: string) => {
    const cachedPath = normalizePath(url);
    if (!cachedPath) return false;
    return cachedPath === submittedPath || cachedPath === currentPath;
  });
});

// Caching setup

const ttl = 1 * 60_000;

swup.hooks.on("visit:start", () => {
  captureScrollableContainers();
});

swup.hooks.on("cache:set", (_visit: unknown, { page }: { page: any }) => {
  swup.cache.update(page.url, { created: Date.now(), ttl });
});

swup.hooks.on("page:view", () => {
  swup.cache.prune(
    (_url: string, { created, ttl }: { created: number; ttl: number }) => {
      return Date.now() > (created ?? 0) + (ttl ?? 0);
    },
  );

  syncDebugPanels();
  restoreScrollableContainersAfterTransition();
});

swup.hooks.on("visit:end", () => {
  restoreScrollableContainersAfterTransition();
});
