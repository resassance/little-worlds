# Подпись Android

С версии 0.3.2 APK использует постоянный сертификат `Little Worlds Release`, RSA 3072. Приложение не является отладочным. Имя пакета остаётся `org.littleworlds.sandbox.preview`, чтобы обновлять существующую установку.

Android 9 и новее получают новый сертификат через SigningCertificateLineage, подписанную прежним ключом. История сертификатов сохраняет право на данные установленного приложения. Android 7–8.1 проверяют v2-подпись прежним ключом. Поэтому обе пары ключей требуются для последующих совместимых сборок.

## Публичные файлы

- `platform/android/release-certificate.pem` — публичный сертификат постоянного ключа.
- `platform/android/signing-lineage.bin` — публичное доказательство смены сертификата. Закрытых ключей в нём нет.

SHA-256 постоянного сертификата: `4d103d6da54e8ecab663f72c90361d9307c5bb9a76e1ffb38119ef891d51e61e`.

SHA-256 прежнего сертификата: `f637bc2dca1a51e808522b78cd4b5fa90817aa9692e9c4f4e772d97489901b3f`.

## Закрытые файлы

Закрытые ключи и пароль находятся вне репозитория, в приватном каталоге рабочего окружения. Отдельный приватный архив с обеими парами ключей, паролем и историей смены предназначен для резервного копирования владельцем. Его нельзя прикладывать к публичным релизам или коммитить.

Публичный сертификат не позволяет восстановить закрытый ключ. Для сборки вне этого окружения владелец должен сохранить приватный архив в собственном хранилище.

## Повторная подпись

Экспортируйте неотладочный APK без подписи. Скрипт `tools/sign_android.py` выравнивает его и подписывает обоими ключами с историей смены сертификата. Пароль прежнего ключа передаётся через `LW_ANDROID_LEGACY_PASSWORD`, пароль постоянного ключа — отдельным файлом.

```sh
python3 tools/sign_android.py --input unsigned.apk --output little-worlds.apk --build-tools /path/to/android-sdk/build-tools/35.0.1 --legacy-keystore /private/legacy-preview.keystore --release-keystore /private/android-release.keystore --release-password-file /private/android-release.password --lineage platform/android/signing-lineage.bin
```

`apksigner verify --min-sdk-version 24 --max-sdk-version 27 --verbose --print-certs little-worlds.apk` проверяет прежнюю подпись для Android 7–8.1. Диапазоны 28–32 и 33–36 проверяют постоянную подпись. История сертификатов просматривается командой `apksigner lineage --in little-worlds.apk --print-certs`.
