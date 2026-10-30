(() => {
  if (!['youtube.com', 'www.youtube.com', 'm.youtube.com'].includes(location.hostname)) return;
  function setup() {
    if (!document.documentElement) return;
    if (!document.getElementById('focus-native-promo-style')) {
      const style = document.createElement('style');
      style.id = 'focus-native-promo-style';
      style.textContent = 'ytm-app-promo-renderer,ytm-app-install-banner-renderer,ytm-app-upsell-renderer,ytm-mealbar-promo-renderer,ytm-statement-banner-renderer:has(a[href^="youtube:"]),a[href^="youtube:"],a[href^="vnd.youtube:"]{display:none!important}';
      document.documentElement.appendChild(style);
    }
    document.querySelectorAll('meta[name="apple-itunes-app"]').forEach(element => element.remove());
  }
  setup();
  new MutationObserver(setup).observe(document, { childList: true, subtree: true });
})();
