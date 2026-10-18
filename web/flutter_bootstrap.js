{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
      document.getElementById('loading')?.remove();
    } catch (error) {
      const message = document.querySelector('#loading p');
      if (message) message.textContent = 'The studio could not start. Please refresh to try again.';
      console.error('Thread could not start', error);
    }
  }
});
