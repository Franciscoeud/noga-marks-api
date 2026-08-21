(function () {
  "use strict";

  const root = document.querySelector("[data-aurenzi-header]");

  if (!root) {
    return;
  }

  const config = window.aurenziHeaderConfig || {};
  const accountLabel = root.querySelector("[data-aurenzi-account-label]");
  const cartLink = root.querySelector("[data-aurenzi-cart-link]");
  const cartBadge = root.querySelector("[data-aurenzi-cart-badge]");
  const searchOverlay = root.querySelector("[data-aurenzi-search-overlay]");
  const searchInput = root.querySelector("[data-aurenzi-search-input]");
  const mobileNavigation = root.querySelector("[data-aurenzi-mobile-navigation]");
  let requestController = null;

  function normalizeState(value) {
    const authenticated = value && value.authenticated === true;
    const displayName =
      authenticated && typeof value.display_name === "string"
        ? value.display_name.trim()
        : "";
    const rawCount = Number(value && value.cart_count);

    return {
      authenticated: authenticated,
      displayName: displayName,
      cartCount: Number.isFinite(rawCount) ? Math.max(0, Math.floor(rawCount)) : 0,
    };
  }

  function renderState(state) {
    if (accountLabel) {
      accountLabel.textContent =
        state.authenticated && state.displayName
          ? "HOLA, " + state.displayName.toLocaleUpperCase("es-PE")
          : config.anonymousText || "INICIAR SESIÓN PARA OBTENER RECOMPENSAS";
    }

    if (cartBadge) {
      cartBadge.textContent = state.cartCount > 99 ? "99+" : String(state.cartCount);
      cartBadge.hidden = state.cartCount === 0;
    }

    if (cartLink) {
      cartLink.setAttribute("aria-label", "Carrito, " + state.cartCount + " unidades");
    }
  }

  async function refreshHeaderState() {
    if (!config.endpoint) {
      return;
    }

    if (requestController) {
      requestController.abort();
    }

    requestController = new AbortController();

    try {
      const response = await fetch(config.endpoint, {
        credentials: "include",
        cache: "no-store",
        headers: { Accept: "application/json" },
        signal: requestController.signal,
      });

      if (!response.ok) {
        throw new Error("Header state request failed");
      }

      renderState(normalizeState(await response.json()));
    } catch (error) {
      if (error && error.name === "AbortError") {
        return;
      }
    }
  }

  function openSearch() {
    if (!searchOverlay) {
      return;
    }

    searchOverlay.hidden = false;
    document.documentElement.classList.add("aurenzi-overlay-open");
    window.setTimeout(function () {
      if (searchInput) {
        searchInput.focus();
      }
    }, 0);
  }

  function closeSearch() {
    if (!searchOverlay) {
      return;
    }

    searchOverlay.hidden = true;
    document.documentElement.classList.remove("aurenzi-overlay-open");
  }

  function openMobileNavigation() {
    if (!mobileNavigation) {
      return;
    }

    mobileNavigation.hidden = false;
    document.documentElement.classList.add("aurenzi-overlay-open");
  }

  function closeMobileNavigation() {
    if (!mobileNavigation) {
      return;
    }

    mobileNavigation.hidden = true;
    document.documentElement.classList.remove("aurenzi-overlay-open");
  }

  root.querySelectorAll("[data-aurenzi-search-open]").forEach(function (button) {
    button.addEventListener("click", openSearch);
  });
  root.querySelectorAll("[data-aurenzi-search-close]").forEach(function (button) {
    button.addEventListener("click", closeSearch);
  });
  root.querySelectorAll("[data-aurenzi-mobile-open]").forEach(function (button) {
    button.addEventListener("click", openMobileNavigation);
  });
  root.querySelectorAll("[data-aurenzi-mobile-close]").forEach(function (button) {
    button.addEventListener("click", closeMobileNavigation);
  });

  if (searchOverlay) {
    searchOverlay.addEventListener("click", function (event) {
      if (event.target === searchOverlay) {
        closeSearch();
      }
    });
  }

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") {
      closeSearch();
      closeMobileNavigation();
    }
  });

  window.addEventListener("focus", refreshHeaderState);
  window.addEventListener("pageshow", refreshHeaderState);
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "visible") {
      refreshHeaderState();
    }
  });

  if (window.jQuery) {
    window.jQuery(document.body).on(
      "added_to_cart removed_from_cart updated_wc_div wc_fragments_refreshed",
      refreshHeaderState
    );
  }

  refreshHeaderState();
})();
