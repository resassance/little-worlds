# Тестовая сборка weather-02

Версия 0.2.6-test.2, Android versionCode 11. Ветка test/weather-02; релиз не опубликован.

[Все файлы](https://github.com/resassance/little-worlds/tree/test/weather-02/test-builds).

- [Android Preview APK](https://github.com/resassance/little-worlds/raw/refs/heads/test/weather-02/test-builds/little-worlds-android-preview.apk)
- [Windows](https://github.com/resassance/little-worlds/raw/refs/heads/test/weather-02/test-builds/little-worlds-windows-test.zip)
- [Linux](https://github.com/resassance/little-worlds/raw/refs/heads/test/weather-02/test-builds/little-worlds-linux-test.zip)
- [Web](https://github.com/resassance/little-worlds/raw/refs/heads/test/weather-02/test-builds/little-worlds-web-test.zip)
- [Исходники](https://github.com/resassance/little-worlds/raw/refs/heads/test/weather-02/test-builds/little-worlds-godot-test.zip)

Если ссылка не скачивается, откройте папку сборки, выберите файл и нажмите Download raw file.

Android Preview — отдельное приложение «Маленькие миры · тест», пакет org.littleworlds.sandbox.preview. Прежний ключ подписи недоступен в восстановленном рабочем окружении, поэтому APK не является обновлением установленной игры. Для проверки не требуется удалять её; сохранения основной игры остаются в ней. У тестового приложения свои миры.

## Что проверить

1. Посмотрите жителей сверху и снизу карты при движении влево и вправо. Голова, инструменты и ноги должны сохранять правильное положение, груз — находиться с соответствующей стороны.
2. В «Мир → Климат» выберите обычные или частые природные события. Они возникают самостоятельно с паузами, зависят от местности и климата и записываются в хронику.
3. Дождь должен тушить огонь и восстанавливать растения в своей области; засуха — замедлять местные поля и уменьшать доступную еду. Проверьте здоровую область вдали от события.
4. При заморозках жители носят тёплую одежду, поля растут медленнее. В море шторм задерживает корабли и может повреждать корпус; сухая гроза может поджечь землю.
5. Сохраните и загрузите мир во время события. Оно должно продолжиться с оставшимся сроком. Переключение камеры и скорости не должно менять исход случайного события.
6. На ×1 и ×5 проверьте кисти, масштаб и меню в населённом мире. Режим «Выключены» отключает самостоятельные события.

Для Web распакуйте архив целиком и запустите start-windows.exe или start-linux.

[Правила природных событий](docs/NATURAL_EVENTS.md).
