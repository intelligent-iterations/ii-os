{{flutter_js}}
{{flutter_build_config}}

(() => {
  const shell = document.getElementById('ii-os-bootstrap');
  const status = document.getElementById('ii-os-bootstrap-status');
  const retry = document.getElementById('ii-os-bootstrap-retry');
  let finished = false;

  const setStatus = (message) => {
    if (status && !finished) status.textContent = message;
  };

  const finish = () => {
    if (finished) return;
    finished = true;
    window.clearTimeout(slowTimer);
    window.clearTimeout(retryTimer);
    shell?.setAttribute('aria-busy', 'false');
    shell?.classList.add('is-ready');
    window.setTimeout(() => shell?.remove(), 320);
  };

  const fail = (error) => {
    console.error('ii-os failed to start.', error);
    window.clearTimeout(slowTimer);
    window.clearTimeout(retryTimer);
    shell?.classList.add('is-error');
    shell?.classList.remove('is-slow');
    shell?.setAttribute('aria-busy', 'false');
    setStatus('ii-os could not start. Check your connection and try again.');
  };

  retry?.addEventListener('click', () => window.location.reload());
  window.addEventListener('ii-os-first-frame', finish, {once: true});
  window.addEventListener(
    'ii-os-startup-failed',
    () => fail(new Error('Flutter reported a startup failure.')),
    {once: true},
  );

  const slowTimer = window.setTimeout(() => {
    shell?.classList.add('is-slow');
  }, 10000);

  const retryTimer = window.setTimeout(() => {
    if (finished) return;
    shell?.classList.add('is-error');
    setStatus('ii-os is taking longer than expected. You can keep waiting or try again.');
  }, 45000);

  const retireLegacyCache = async () => {
    // Connector routing is deployment-owned. Retire the old SharedPreferences
    // record before Flutter starts so stale per-browser endpoints cannot
    // disconnect a signed-in account. Keep the last-workspace preference.
    try {
      localStorage.removeItem('flutter.ii_os_data_plane_connection_v1');
      localStorage.removeItem('ii_os_data_plane_connection_v1');
    } catch (error) {
      console.warn('Could not retire legacy ii-os connector state.', error);
    }

    // API routing is deployment configuration, so an old Flutter service worker
    // must never pin a user to a stale connector or a removed hosting rewrite.
    if (!('serviceWorker' in navigator)) return;
    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(
        registrations
          .filter((item) => {
            const worker = item.active || item.waiting || item.installing;
            return !worker?.scriptURL.endsWith('/firebase-messaging-sw.js');
          })
          .map((item) => item.unregister()),
      );
      if ('caches' in window) {
        const names = await caches.keys();
        await Promise.all(
          names
            .filter((name) => name.startsWith('flutter-'))
            .map((name) => caches.delete(name)),
        );
      }
    } catch (error) {
      console.warn('Could not retire the previous ii-os app cache.', error);
    }
  };

  const start = async () => {
    setStatus('Checking for updates...');
    await retireLegacyCache();
    setStatus('Loading Flutter...');
    await _flutter.loader.load({
      onEntrypointLoaded: async (engineInitializer) => {
        setStatus('Starting the Flutter engine...');
        const appRunner = await engineInitializer.initializeEngine();
        setStatus('Opening your workspace...');
        await appRunner.runApp();
        setStatus('Restoring your session...');
      },
    });
  };

  start().catch(fail);
})();
