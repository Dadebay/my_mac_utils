# 09 — Production / Dağıtım

> **Not:** Test ve dağıtımı kullanıcı kendisi yapacak (talep üzerine, 2026-08-22).
> Bu dosya artık aktif plana dahil değil, referans olarak duruyor. iOS/CloudKit
> bölümleri de kapsam dışı kaldığı için bu haliyle güncel değil.

## Ön koşul

**Apple Developer Program — $99/yıl.** Şunlar için zorunlu:
- CloudKit (iCloud sync)
- Gerçek iPhone'da test (7 günlük ücretsiz profil dışında)
- TestFlight
- App Store
- macOS notarization

Ücretsiz hesapla sadece: simülatör + kendi Mac'inde 7 günlük imzalı build.

---

## Bölüm A — Apple Developer portal kurulumu

1. **Identifiers → App IDs** oluştur:
   - `com.dadebay.glassdo` (macOS + iOS, Explicit)
   - `com.dadebay.glassdo.widgets`
   - Capabilities: **iCloud (CloudKit)**, **App Groups**, **Push Notifications**
     (CloudKit sync için gerekli)
2. **Identifiers → App Groups**: `group.com.dadebay.glassdo`
3. **Identifiers → iCloud Containers**: `iCloud.com.dadebay.glassdo`
4. App ID'leri bu group ve container'a bağla
5. Xcode → Signing & Capabilities → Automatically manage signing ✓

## Bölüm B — Entitlements

**macOS** (`Config/macOS.entitlements`):
```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.application-groups</key>
<array><string>group.com.dadebay.glassdo</string></array>
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.com.dadebay.glassdo</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
<key>com.apple.developer.aps-environment</key><string>production</string>
```

**iOS** aynısı, `app-sandbox` hariç (iOS'ta zaten sandbox'lı).

> **Not:** App Sandbox açıkken global hotkey için Accessibility izni **gerekmez**
> (`KeyboardShortcuts` Carbon RegisterEventHotKey kullanır, sandbox uyumlu).
> Ama `NSEvent.addGlobalMonitorForEvents` kullanırsan Accessibility izni gerekir.

## Bölüm C — Privacy manifest

`PrivacyInfo.xcprivacy` her target'a (app + widget):

```xml
<dict>
  <key>NSPrivacyTracking</key><false/>
  <key>NSPrivacyCollectedDataTypes</key><array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array><string>CA92.1</string></array>
    </dict>
  </array>
</dict>
```

Veri toplamıyoruz → App Store Connect'te "Data Not Collected" seç.

---

## Bölüm D — CloudKit production'a alma

Development şeması otomatik oluşur, **production'a elle deploy edilir**:

1. [icloud.developer.apple.com](https://icloud.developer.apple.com) → container'ını seç
2. Development'ta uygulamayı çalıştır, tüm model tiplerinden en az bir kayıt oluştur
3. Schema → Record Types'ta `CD_Task`, `CD_Project`, `CD_Tag` göründüğünü doğrula
4. **Deploy Schema to Production** butonuna bas
5. TestFlight/App Store build'leri production şemasını kullanır

> Bu adımı atlarsan: development'ta çalışan uygulama, TestFlight'ta
> "record type not found" ile sessizce sync etmez. **Sık yapılan hata.**

---

## Bölüm E — iOS dağıtımı (tek yol: App Store)

```bash
xcodebuild -scheme GlassDo-iOS \
  -destination 'generic/platform=iOS' \
  -archivePath build/GlassDo-iOS.xcarchive archive
```

```bash
xcodebuild -exportArchive \
  -archivePath build/GlassDo-iOS.xcarchive \
  -exportOptionsPlist Config/ExportOptions-AppStore.plist \
  -exportPath build/ios-export
```

```bash
xcrun altool --upload-app -f build/ios-export/GlassDo.ipa \
  -t ios --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID
```

Sonra App Store Connect → TestFlight → kendi cihazına yükle.
Kendi kullanımın için **App Store'a yayınlamana gerek yok**, TestFlight yeter
(build 90 gün geçerli, yenilemek gerekir).

## Bölüm F — macOS dağıtımı (iki yol)

### Yol 1: Sadece kendin için (en basit)

Developer ID ile imzala, notarize et, doğrudan çalıştır:

```bash
xcodebuild -scheme GlassDo-macOS -configuration Release \
  -archivePath build/GlassDo.xcarchive archive
```

```bash
xcodebuild -exportArchive -archivePath build/GlassDo.xcarchive \
  -exportOptionsPlist Config/ExportOptions-DeveloperID.plist \
  -exportPath build/mac-export
```

Notarize:
```bash
xcrun notarytool store-credentials "GlassDoNotary" \
  --apple-id "seninmail@example.com" --team-id "XXXXXXXXXX"
```

```bash
ditto -c -k --keepParent build/mac-export/GlassDo.app build/GlassDo.zip && xcrun notarytool submit build/GlassDo.zip --keychain-profile "GlassDoNotary" --wait
```

```bash
xcrun stapler staple build/mac-export/GlassDo.app && spctl -a -vvv -t exec build/mac-export/GlassDo.app
```

Son komut `accepted / source=Notarized Developer ID` demeli.

### Yol 2: Mac App Store

iOS ile aynı akış, `-destination 'generic/platform=macOS'` ve
Mac App Store export options. Sandbox zorunlu (zaten açık).

> **Kendin için öneri:** iOS'u TestFlight'tan, macOS'u notarized DMG olarak
> dağıt. App Store review sürecine hiç girme.

## Bölüm G — DMG oluşturma (opsiyonel)

```bash
brew install create-dmg
```

```bash
create-dmg --volname "GlassDo" --window-size 540 380 --icon-size 96 --icon "GlassDo.app" 140 180 --app-drop-link 400 180 build/GlassDo.dmg build/mac-export/
```

DMG'yi de notarize et (yukarıdaki `notarytool submit` aynı şekilde).

---

## Bölüm H — Otomatik güncelleme (App Store dışıysa)

**Sparkle 2** ekle:
- `SUFeedURL` → bir `appcast.xml` (GitHub Releases veya kendi sunucun)
- EdDSA anahtar çifti üret (`generate_keys`), public key'i Info.plist'e koy
- Her release'te `generate_appcast` çalıştır

Tek kullanıcı için bu **gereksiz** — yeni sürümü elle kurmak yeterli.
Başkalarına dağıtacaksan ekle.

---

## Bölüm I — Release öncesi son kontrol

- [ ] Sürüm ve build numarası artırıldı
- [ ] Release konfigürasyonunda derleniyor (Debug değil)
- [ ] Tüm testler geçiyor
- [ ] Uygulama ikonu tüm boyutlarda var (macOS 16→1024, iOS 20→1024)
- [ ] `PrivacyInfo.xcprivacy` her target'ta
- [ ] Hardened Runtime açık (macOS)
- [ ] CloudKit şeması production'a deploy edildi
- [ ] Notarization `accepted` döndü
- [ ] Temiz bir kullanıcı hesabında ilk açılış denendi
- [ ] `~/Library/Containers/com.dadebay.glassdo` silinip sıfırdan açılış denendi

## Maliyet özeti

| Kalem | Tutar |
|---|---|
| Apple Developer Program | $99 / yıl |
| CloudKit (private DB) | Ücretsiz — kullanıcının iCloud kotasından |
| Sunucu | $0 |
| **Toplam** | **$99 / yıl** |
