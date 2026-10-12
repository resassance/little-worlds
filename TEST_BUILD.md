# Тестовая сборка touch-camera-01

**0.2.4-test.1**, исправления исчезающей суши при отдалении и зависания сенсорных меню. Это сборка для проверки перед следующим релизом.

- [Android APK](https://github.com/resassance/little-worlds/raw/refs/heads/test/touch-camera-01/test-builds/little-worlds-android-test.apk)
- [Windows ZIP](https://github.com/resassance/little-worlds/raw/refs/heads/test/touch-camera-01/test-builds/little-worlds-windows-test.zip)
- [Linux ZIP](https://github.com/resassance/little-worlds/raw/refs/heads/test/touch-camera-01/test-builds/little-worlds-linux-test.zip)
- [Web ZIP](https://github.com/resassance/little-worlds/raw/refs/heads/test/touch-camera-01/test-builds/little-worlds-web-test.zip)
- [Проект Godot](https://github.com/resassance/little-worlds/raw/refs/heads/test/touch-camera-01/test-builds/little-worlds-godot-test.zip)

APK устанавливается поверх прежней игры. Не удаляйте приложение: сохранения остаются на устройстве. Формат миров не менялся.

Проверьте отдаление на существующем сохранении и переключение категорий в «Кисти». После выбора или закрытия выпадающего списка должны работать пауза, скорость, масштаб и панели. Нажатие снаружи списка должно закрывать его без выбора клетки под ним. Для проверки возврата из фона оставьте список открытым, сверните игру и откройте её снова.

Для Web распакуйте архив целиком и запустите `start-windows.exe` или `start-linux`.

[Подробности изменений и проверок](docs/TEST_BUILDS.md).
