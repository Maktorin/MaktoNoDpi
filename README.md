# MaktoNoDpi

Нативное приложение для macOS (Swift/SwiftUI), обходящее DPI-блокировки
интернета. Автоподбор стратегии обхода, статус-иконка в меню-баре, SOCKS5-прокси
через встроенный бинарник `tpws`, подмена DNS, блок QUIC через `pfctl`,
автозапуск и авто-обновления на базе Sparkle. Приложение живёт целиком в
меню-баре (без иконки в доке).

Движок обхода DPI - [zapret](https://github.com/bol-van/zapret) (bol-van).
Приложение использует его утилиту `tpws`, собранную из исходников и встроенную
в бандл; стратегии обхода и host-листы портированы из darwin-ветки zapret.

## Архитектура

```
Core/                   Swift-пакет (SPM) - чистая логика, тестируется через swift test
  Sources/MaktoNoDpiCore/
    ProxyEngine.swift       цикл перебора стратегий
    SystemConfig.swift      вкл/выкл прокси, DNS через networksetup
    BinaryManager.swift     распаковка / chmod встроенного tpws
    PrivilegedHelper.swift  генерация root-helper'а + sudoers (авторизация один раз)
    ...

App/                    Xcode SwiftUI-приложение - тонкая оболочка над Core
  MaktoNoDpi/
    MaktoNoDpiApp.swift          @main, сцена MenuBarExtra, AppDelegate, EmergencyCleanup
    ProxyController.swift        @MainActor-мост Core → UI
    ContentView.swift            поповер меню-бара (сервисы, статус, подробности, футер)
    SettingsView.swift           автозапуск / автоподключение / стратегия / свои домены
    PrivilegedHelperInstaller.swift установка root-helper'а, вызовы sudo -n
    UpdaterController.swift      обёртка над Sparkle
    LoginItem.swift              обёртка над SMAppService.mainApp

scripts/
  build-tpws.sh        собрать universal tpws (arm64+x86_64) из исходников zapret
  package.sh           собрать Release .app → dist/MaktoNoDpi.dmg
  release.sh           собрать + подписать релиз для Sparkle (zip + dmg + appcast.xml)
```

## Требования

- macOS 13.0 или новее
- Xcode 15+ с тулчейном Swift 6
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Сборка

```bash
# Перегенерировать Xcode-проект (после правок project.yml или добавления файлов)
cd App && xcodegen generate

# Сборка (Debug)
xcodebuild \
  -project App/MaktoNoDpi.xcodeproj \
  -scheme MaktoNoDpi \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

# Юнит-тесты Core (Xcode не нужен)
cd Core && swift test
```

## Релиз и упаковка

```bash
bash scripts/release.sh 1.0
# На выходе в dist/: MaktoNoDpi-1.0.zip (апдейт Sparkle), MaktoNoDpi.dmg
# (ручная установка), appcast.xml (EdDSA-подписанный фид)
```

Полный процесс нарезки релиза, подписи и публикации на GitHub Releases - в
[docs/RELEASING.md](docs/RELEASING.md).

## Установка

1. Открыть `MaktoNoDpi.dmg`, перетащить `MaktoNoDpi.app` в `/Applications`.
2. Приложение **не подписано** Apple (нет Developer ID), поэтому Gatekeeper
   блокирует первый запуск. Обойти - правый клик по приложению → **«Открыть»**
   (один раз), либо снять карантин:
   ```bash
   xattr -cr /Applications/MaktoNoDpi.app
   ```
3. Запустить - приложение появится в меню-баре.

## Заметки

- **Авторизация root один раз.** Привилегированные операции (блок QUIC через
  pfctl, правка `/etc/hosts`) идут через root-owned helper с scoped NOPASSWD
  sudoers-правилом: при первом подключении - один промпт пароля на установку
  helper'а, дальше всё через `sudo -n` без пароля. Подробности - в
  `Core/Sources/MaktoNoDpiCore/PrivilegedHelper.swift`.
- **Авто-обновления** работают на EdDSA-подписях Sparkle (без Apple Developer
  ID). Цена отсутствия подписи Apple - Gatekeeper требует ручное «Открыть» на
  каждой новой версии.
- Встроенный `tpws` - universal-сборка (arm64 + x86_64) из исходников
  [zapret](https://github.com/bol-van/zapret). Пересобрать: `bash scripts/build-tpws.sh`.
