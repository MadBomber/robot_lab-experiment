// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"

document.addEventListener('turbo:load', () => {
  const el = document.getElementById('transcript');
  if (!el) return;

  let shouldAutoScroll = true;

  function updateAtBottomFlag() {
    const threshold = 50; // px
    const distFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    shouldAutoScroll = distFromBottom <= threshold;
  }

  el.addEventListener('scroll', updateAtBottomFlag, true);
  updateAtBottomFlag(); // initial state on page load / first turbo navigation

  const observer = new MutationObserver(() => {
    requestAnimationFrame(() => {
      if (shouldAutoScroll) {
        el.scrollTop = el.scrollHeight;
      }
    });
  });

  observer.observe(el, { childList: true, subtree: true });
});
