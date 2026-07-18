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

(function startHeartbeatPolling() {
  const statusEl = document.getElementById('agent-status');
  if (!statusEl) return;

  // Check if agent is currently running (spinner present)
  const hasSpinner = statusEl.querySelector('.animate-spin') !== null;
  if (!hasSpinner) return;

  const heartbeatUrl = statusEl.dataset.heartbeatUrl;
  if (!heartbeatUrl) return;

  let lastMessageCount = null;

  function formatElapsed(seconds) {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
  }

  async function poll() {
    if (!document.getElementById('agent-status')) return; // page navigated away

    try {
      const res = await fetch(heartbeatUrl);
      if (!res.ok) return;
      const data = await res.json();

      if (!data.started_at) return;  // no active conversation

      const elapsedSecs = Math.floor((Date.now() - new Date(data.started_at).getTime()) / 1000);

      const elapsedSpan = statusEl.querySelector('[data-elapsed]');
      const msgCountSpan = statusEl.querySelector('[data-msg-count]');

      if (msgCountSpan !== null && data.message_count !== lastMessageCount) {
        lastMessageCount = data.message_count;
        msgCountSpan.textContent = data.message_count;
        elapsedSpan.textContent = formatElapsed(elapsedSecs);

        // Trigger pulse animation on message count change
        const icon = statusEl.querySelector('.heartbeat-icon');
        if (icon) {
          // Remove class to allow re-adding it triggers a fresh animation
          icon.classList.remove('heartbeat-pulse-active');
          void icon.offsetWidth;  // force reflow
          icon.classList.add('heartbeat-pulse-active');
          // Clean up after animation completes so re-adding works next time
          setTimeout(() => icon.classList.remove('heartbeat-pulse-active'), 1500);
        }
      } else if (elapsedSpan) {
        elapsedSpan.textContent = formatElapsed(elapsedSecs);
      }
    } catch (e) {
      // Silently fail — don't break the page
    }
  }

  // Initial call then poll every 2 seconds
  poll();
  const intervalId = setInterval(poll, 2000);

  // Stop polling on Turbo navigation
  document.addEventListener('turbo:before-cache', () => {
    clearInterval(intervalId);
  });
})();
