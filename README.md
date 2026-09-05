# Gonavi

SwiftUI tabanlı, yerel çalışan macOS video editörü. **0.1 teknik temel**; CapCut kapsamındaki tam ürün henüz tamamlanmadı.

## İndir ve çalıştır

1. [Actions](https://github.com/netpixdev/gonavi/actions/workflows/macos.yml) sayfasında **başarılı** son çalışmayı aç.
2. `Gonavi-macOS-arm64` artifact'ını indir. Artifact içindeki `Gonavi-macOS-arm64.zip` dosyasını aç.
3. `Gonavi.app` dosyasını Applications klasörüne taşı ve aç.
4. macOS geliştiriciyi doğrulayamadığını söylerse, bu uygulama için Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç yolunu kullan.

**Gereksinim:** Apple Silicon (M serisi), macOS 14+. Intel build bu aşamada yok. Ücretli Apple Developer hesabı gerekmez; uygulama ad-hoc imzalıdır, Developer ID imzası veya notarization yoktur. Gatekeeper'ın genel ayarlarını değiştirmek gerekmez.

## Bu sürümde çalışan akış

- Video/ses dosyası içe aktarma ve Finder'dan toplu sürükle bırak.
- Bir ana video hattında ardışık klipler; klibi bölme, ripple silme, sürükleyerek yeniden sıralama.
- 9:16, 16:9, 1:1, 4:5 sahneleri; 24/25/30/60 fps.
- Fit/fill (crop), zoom, yatay/dikey konum ve klip ses seviyesi.
- Bağımsız bir müzik hattı ve ses seviyesi; müzik döngüye alınmaz.
- Elle altyazı oluşturma/düzenleme; Sade, Vurgu, Kutu stilleri; SRT export.
- Aynı compositor ile video önizleme ve MP4 export; altyazılar videoya gömülür.
- JSON `.gonavi` proje kaydı, son oturum kurtarma, 100 adımlık geri alma/yineleme.
- Medya sağ tık menüsünden eksik dosyayı yeniden bağlama.
- Export ilerlemesi, iptal; başarısız export mevcut hedef dosyayı silmez.

### Hızlı kullanım

`⌘I` ile iki video ekle. Timeline'da bir klibe tıkla. Zaman cetvelinde istediğin yere tıklayıp **Böl** de; istenmeyen parçayı seçip sil. Klip sekmesinden zoom/crop ayarla. Altyazı sekmesinde `+` ile metin ekle; zamanlarını saniye olarak düzenle. `⌘S` ile projeyi kaydet, `⌘E` ile video dışa aktar.

Timeline yakınlaştırma sağ üstteki kaydırıcıyla değişir. Klipler diğer klibin üzerine bırakılınca onun önüne taşınır. Bir klibi sona taşımak için son klibi onun önüne taşıyabilirsin; doğrudan boş alana bırakma henüz desteklenmez.

## Sınırlar

- Otomatik sessizlik temizleme, Whisper transkripsiyonu, kelime vurgulu animasyon, özel şablon içe aktarma, çoklu video katmanları, keyframe ve proxy henüz uygulanmadı. [Yol haritası](docs/ROADMAP.md).
- Kırpma bu aşamada böl + sil ile yapılır; kenardan sürükleyerek trim henüz yok.
- `.gonavi` şu anda bir JSON dosyasıdır; medya dosyalarını içine kopyalayan taşınabilir paket henüz yok. Kaynak medya dosyalarını sakla.
- Altyazılar timeline zamanına bağlıdır. Klip silme altyazıları kaydırır; klip sıralama altyazıları beraber taşımaz. Kaynak zamana bağlı altyazı modeli sonraki aşamadır.
- Proje zamanlarında 60.000 tick/sn kullanılır. Render süreleri çıktı FPS'ine oturtulur; VFR/telefon/HDR uyumluluğu fiziksel Mac testleriyle genişletilecek.
- Render SDR/Rec.709 hedefler; HDR koruma ve profesyonel renk doğruluğu iddiası yoktur.
- Yerel font ve bitmap altyazı; mevcut ilk tasarım uzun metin için en fazla 500 karakter kabul eder. Kısa altyazı blokları kullan.
- Arayüz ve gerçek cihaz performansı Windows üzerinden doğrulanamaz. Başarılı CI, fiziksel Mac kabul testinin yerine geçmez.
- Otomatik kurtarma tek oturum içindir; `~/Library/Application Support/Gonavi/recovery.json`. İçe aktarılan medya kopyalanmaz. Proje/medya ağ üzerinden gönderilmez.

## Geliştirme

Bağımlılıksız Swift Package; macOS üzerinde Xcode 16.4 / Swift 6.1, Swift 5 dil modu.

```sh
swift test
bash scripts/build-app.sh
open dist/Gonavi.app
dist/Gonavi.app/Contents/MacOS/Gonavi --smoke-test dist/smoke
```

SwiftUI/AVFoundation uygulaması Windows'ta derlenmez. Windows'tan kaynak değiştirip GitHub'a push yap; macOS Actions derler. Projeyi bir Mac'te `Package.swift` üzerinden Xcode ile de açabilirsin.

CI, çekirdek kurgu testlerini çalıştırır; Release `.app` üretir; ad-hoc imzayı doğrular; kırmızı/yeşil video ve ses fixture'ları üretip gerçek MP4 export testi yapar. Test; süre, çözünürlük, klip sırası, ses hattı, altyazının görünmesi ve doğru zamanda kaybolmasını kontrol eder. `Gonavi-media-test` artifact'ı örnek video, kare ve rapor içerir.

## Yapı

| Yol | Sorumluluk |
| --- | --- |
| `Sources/GonaviCore` | Saf kurgu/proje modeli, rasyonel zaman, kodlama ve SRT |
| `Sources/Gonavi/EditorStore.swift` | Komutlar, undo/redo, kayıt, iş durumu |
| `Sources/Gonavi/MediaEngine.swift` | AVFoundation kompozisyon ve ortak Core Image compositor |
| `Sources/Gonavi/EditorView.swift` | Yerel editör panelleri ve ilk timeline |
| `Sources/Gonavi/SmokeTest.swift` | Üretilmiş medya ile gerçek export doğrulaması |
| `.github/workflows/macos.yml` | macOS build ve test |

İlk timeline SwiftUI ile kurulmuştur; geniş projelerde sanallaştırılmış AppKit çizimiyle değiştirilecek. Core Image, uygun cihazda GPU kullanabilir; özel Metal shader pipeline'ı henüz yoktur.
