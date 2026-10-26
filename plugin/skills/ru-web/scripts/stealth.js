// Only what headless Chrome actually leaks; real values left alone (fake values show up as lies).
if (!window.chrome) window.chrome = {};
if (!window.chrome.runtime) window.chrome.runtime = {};
const q = navigator.permissions && navigator.permissions.query;
if (q) navigator.permissions.query = p => p && p.name === 'notifications'
  ? Promise.resolve({ state: Notification.permission === 'default' ? 'prompt' : Notification.permission })
  : q.call(navigator.permissions, p);
