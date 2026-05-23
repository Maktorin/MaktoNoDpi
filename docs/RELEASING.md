# Релиз MaktoNoDpi (Sparkle auto-update)

Обновления раздаются через Sparkle: приложение читает `appcast.xml` с GitHub
Releases (`SUFeedURL` → `releases/latest/download/appcast.xml`), сверяет версию,
скачивает `.zip`, проверяет EdDSA-подпись и ставит.

## Ключи (один раз, уже сделано)

- EdDSA-ключ сгенерирован через Sparkle `generate_keys`. **Приватный** ключ
  лежит в login Keychain (item `https://sparkle-project.org`), **публичный**
  вписан в `App/project.yml` → `SUPublicEDKey`.
- ⚠️ **Бэкап приватного ключа обязателен.** Потеря = никто не сможет обновиться
  (придётся раздавать новую версию вручную с новым ключом). Экспорт:
  `generate_keys -x sparkle_private_key.txt` → сохрани файл в надёжное место
  (НЕ в репозиторий), потом удали локально.
- Подпись и нотаризация Apple **не используются** (нет Developer ID). EdDSA-подписи
  достаточно для механизма Sparkle; цена - Gatekeeper будет требовать ручное
  «всё равно открыть» на каждой версии (как при первой установке).

## Как нарезать релиз N.M

1. Подними версию в `App/project.yml`:
   - `MARKETING_VERSION` → `N.M` (видимая версия, `CFBundleShortVersionString`).
   - `CURRENT_PROJECT_VERSION` → монотонно растущее целое (`CFBundleVersion`) -
     **именно его Sparkle сравнивает**, обязан увеличиваться каждый релиз.
2. Собери и подпиши:
   ```sh
   scripts/release.sh N.M
   ```
   На выходе в `dist/`: `MaktoNoDpi-N.M.zip` (апдейт), `MaktoNoDpi.dmg` (ручная
   первая установка), `appcast.xml` (EdDSA-подписанный фид). Сборка universal
   (arm64 + x86_64), ad-hoc-подписана (нужно Sparkle для проверки целостности).
3. Опубликуй GitHub Release с тегом `vN.M` и пометь latest:
   ```sh
   gh release create vN.M \
     dist/MaktoNoDpi-N.M.zip dist/appcast.xml dist/MaktoNoDpi.dmg \
     --title "MaktoNoDpi N.M" --notes "что нового"
   ```
   `appcast.xml` ссылается на zip по per-tag URL `releases/download/vN.M/…`, а
   сам фид Sparkle берёт с `releases/latest/download/appcast.xml` - поэтому новый
   релиз обязан быть latest (по умолчанию latest = самый свежий не-draft тег).

## Проверка авто-апдейта

После публикации N.M юзер на N.(M-1) при нажатии «Обновления» (или по таймеру)
увидит предложение обновиться. Для сквозного теста: выпусти 1.1 поверх 1.0 и
проверь, что 1.0 находит апдейт.
