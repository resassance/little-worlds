# Проверка проекта

Автоматические сценарии находятся в `tests/`. Они проверяют правила симуляции, ресурсные балансы, сохранения, продолжение мира, интерфейс и интеграцию платформы.

Ядро запускается через Godot, например:

```sh
godot --headless --path . --script res://tests/simulation_test.gd
godot --headless --path . --script res://tests/population_test.gd
godot --headless --path . --script res://tests/mobile_simulation_test.gd
```

Сценарии браузера используют Python, Playwright, Chromium и Pillow. После экспорта Web запустите HTTP-сервер на порту 8000 и выполните `python3 tests/web_smoke.py`. Контракт платформенного слоя проверяется командой `node tests/platform_test.cjs`.

`tests/web_sdk_smoke.py` использует макет SDK. Перед запуском выполните `tests/population_test.gd`, который создаёт мир для браузерного сценария.
