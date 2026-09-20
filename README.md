# GlassDo

macOS için sakin bir kontrol merkezi: görevler, notlar, ekran kenarında
duran Edge Rail paneli ve sistem izleme. Her şey cihazda kalıyor.

Kaynak `mac_utils/app` altında. Xcode projesi sürüm denetiminde durmuyor,
`project.yml`den üretiliyor:

```bash
cd mac_utils/app && xcodegen generate && open GlassDo.xcodeproj
```

Komut satırından derlemek:

```bash
cd mac_utils/app && xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug build
```

`main`'e her push'ta GitHub Actions imzasız bir Release derleyip
Releases'e ekliyor (bkz. `.github/workflows/release.yml`). CI runner'ında
sertifika olmadığı için bu derleme ad-hoc imzalı; App Group'a bağlı
widget senkronizasyonu o build'de çalışmaz.

## Diğer depolar

Proje üç ayrı depoya bölündü. Bu depo yalnızca macOS uygulamasını taşıyor.

| Depo | Ne |
| --- | --- |
| [mac_utils_website](https://github.com/Dadebay/mac_utils_website) | Tanıtım sitesi — Astro, mac-utils.web.app |
| [mac_utils_admin_panel](https://github.com/Dadebay/mac_utils_admin_panel) | Yönetim paneli ve Cloud Functions — mac-utils-admin.web.app |

Firebase yapılandırması (hosting, functions, Firestore kuralları) o iki
depoda; burada yok.
