(() => {
  if (window.LittleWorldsPlatform) return;
  let sdk, player, ready = false, playing = false, hidden = document.hidden, paused = false, advertising = false;
  let pending = false;
  const events = [];
  const push = event => { if (events.length < 64) events.push(event); };
  const message = text => push({ kind: 'message', text });
  const suspended = () => hidden || paused || advertising;
  function sync() {
    push({ kind: 'suspend', value: suspended() });
    if (!sdk?.features?.GameplayAPI) return;
    try { if (playing && !suspended()) sdk.features.GameplayAPI.start(); else sdk.features.GameplayAPI.stop(); } catch (_) {}
  }
  document.addEventListener('visibilitychange', () => { hidden = document.hidden; sync(); });
  async function getPlayer() {
    if (!sdk) throw Error('SDK unavailable');
    player ??= await sdk.getPlayer({ scopes: false });
    return player;
  }
  async function operation(action) {
    if (pending) return message('Облачная операция уже выполняется.');
    pending = true;
    try { await action(await getPlayer()); }
    catch (_) { message('Облако недоступно. Мир можно сохранить на этом устройстве.'); }
    finally { pending = false; }
  }
  window.LittleWorldsPlatform = {
    ready() { if (ready) return; ready = true; if (sdk?.features?.LoadingAPI) sdk.features.LoadingAPI.ready(); },
    gameplay(value) { playing = value === 'start'; sync(); },
    poll() { return JSON.stringify(events.splice(0)); },
    save(data) { if (typeof data !== 'string' || data.length > 180000) return;
      return operation(async p => { await p.setData({ littleWorldsV7: data }, true); message('Мир сохранён в облаке Яндекс Игр.'); }); },
    load() { return operation(async p => { const data = await p.getData(['littleWorldsV7']);
      if (typeof data.littleWorldsV7 === 'string') push({kind:'cloud',data:data.littleWorldsV7});
      else message('В облаке пока нет сохранённого мира.'); }); },
    rewarded() {
      if (!sdk || advertising) return;
      advertising = true; sync(); let rewarded = false, closed = false;
      const finish = () => { if (closed) return; closed = true; advertising = false; sync(); };
      try { sdk.adv.showRewardedVideo({callbacks:{
        onOpen: () => { advertising = true; sync(); },
        onRewarded: () => { if (!rewarded) { rewarded = true; push({kind:'reward'}); } },
        onClose: finish, onError: () => { finish(); message('Видео сейчас недоступно.'); }
      }}); } catch (_) { finish(); message('Видео сейчас недоступно.'); }
    }
  };
  async function initialize() {
    try {
      sdk = await window.YaGames.init();
      sdk.on('game_api_pause', () => { paused = true; sync(); });
      sdk.on('game_api_resume', () => { paused = false; sync(); });
      if (ready) sdk.features?.LoadingAPI?.ready();
      push({kind:'available'}); sync();
    } catch (_) { message('Площадка недоступна. Можно играть и сохранять локально.'); }
  }
  if (window.YaGames) initialize();
  else if (/(^|\.)(yandex\.(ru|com)|ya\.ru|yandexgames\.net|yandex\.net)$/.test(location.hostname)) {
    const script = document.createElement('script'); script.src = '/sdk.js'; script.onload = initialize;
    script.onerror = () => message('Не удалось подключиться к площадке. Локальная игра доступна.');
    document.head.append(script);
  }
})();
