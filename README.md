# Gonavi

SwiftUI tabanlı, yerel çalışan macOS video editörü. **0.2 teknik önizleme**; CapCut kapsamındaki tam ürün henüz tamamlanmadı.

## İndir ve çalıştır

1. [Actions](https://github.com/netpixdev/gonavi/actions/workflows/macos.yml) sayfasında **başarılı** son çalışmayı aç.
2. Intel Mac için `Gonavi-macOS-x86_64`, M serisi Mac için `Gonavi-macOS-arm64` artifact'ını indir. Artifact içindeki aynı adlı ZIP dosyasını aç.
3. `Gonavi.app` dosyasını Applications klasörüne taşı ve aç.
4. macOS geliştiriciyi doğrulayamadığını söylerse, bu uygulama için Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç yolunu kullan.

**Gereksinim:** macOS 14 Sonoma veya üzeri. Intel (`x86_64`) ve Apple Silicon (`arm64`) için ayrı paketler üretilir ve her biri kendi mimarisindeki macOS runner'da test edilir. Ücretli Apple Developer hesabı gerekmez; uygulama ad-hoc imzalıdır, Developer ID imzası veya notarization yoktur. Gatekeeper'ın genel ayarlarını değiştirmek gerekmez.

## Bu sürümde çalışan akış

- Hesap gerektirmeyen başlangıç ekranı, son 12 proje, arama ve açık projeye dönüş.
- Proje adı, oran ve FPS seçimiyle yeni proje oluşturma penceresi.
- Kurtarılabilir oturumu açılışta gösterme; kullanıcı seçince devam etme.
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

Başlangıçta **Yeni proje** seç; ad, sahne oranı ve FPS belirleyip **Projeyi oluştur** de. `⌘I` ile iki video ekle. Timeline'da bir klibe tıkla. Zaman cetvelinde istediğin yere tıklayıp **Böl** de; istenmeyen parçayı seçip sil. Klip sekmesinden zoom/crop ayarla. Altyazı sekmesinde `+` ile metin ekle, **Metni Uygula** de; zamanlarını saniye olarak düzenle. `⌘S` ile projeyi kaydet, `⌘E` ile video dışa aktar.

Editörün sol üstündeki çalışma alanı düğmesi başlangıca döner; açık proje korunur. Son projelerde sağ tık → **Geçmişten Kaldır**, yalnızca geçmiş kaydını kaldırır. Kaynak dosyayı silmez. Bir proje taşınırsa **Proje aç** ile yeni konumunu seçebilirsin.

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
- Aktif oturumun otomatik kaydı `~/Library/Application Support/Gonavi/recovery.json` içindedir. Kurtarmadan başka proje açılırsa önceki oturum `Recovered Projects` altında ayrı bir `.gonavi` dosyası olarak korunur ve son projelere eklenir. Önceki kurtarmaların üzerine yazılmaz. Son projeler `recents.json` içinde tutulur. İçe aktarılan medya kopyalanmaz. Proje/medya ağ üzerinden gönderilmez.

## Geliştirme

Bağımlılıksız Swift Package; macOS üzerinde Xcode 16.4 / Swift 6.1, Swift 5 dil modu.

```sh
swift test
bash scripts/build-app.sh
open dist/Gonavi.app
dist/Gonavi.app/Contents/MacOS/Gonavi --smoke-test dist/smoke
```

SwiftUI/AVFoundation uygulaması Windows'ta derlenmez. Windows'tan kaynak değiştirip GitHub'a push yap; macOS Actions derler. Projeyi bir Mac'te `Package.swift` üzerinden Xcode ile de açabilirsin.

CI, Intel ve ARM üzerinde çekirdek kurgu testlerini çalıştırır; Release `.app` üretir; ikili dosyanın mimarisini ve ad-hoc imzayı doğrular; kırmızı/yeşil video ve ses fixture'ları üretip gerçek MP4 export testi yapar. Test; süre, çözünürlük, klip sırası, ses enerjisi, altyazının görünmesi ve doğru zamanda kaybolmasını kontrol eder. Ayrıca başlangıç/yeni proje/geçmiş/kurtarma durum geçişlerini doğrular. `Gonavi-media-test-arm64` ve `Gonavi-media-test-x86_64` artifact'ları örnek video, yerel SwiftUI ekran görüntüleri ve rapor içerir.

## Yapı

| Yol | Sorumluluk |
| --- | --- |
| `Sources/GonaviCore` | Saf kurgu/proje modeli, rasyonel zaman, kodlama ve SRT |
| `Sources/Gonavi/EditorStore.swift` | Komutlar, undo/redo, kayıt, iş durumu |
| `Sources/Gonavi/MediaEngine.swift` | AVFoundation kompozisyon ve ortak Core Image compositor |
| `Sources/Gonavi/EditorView.swift` | Yerel editör panelleri ve ilk timeline |
| `Sources/Gonavi/WelcomeView.swift` | Başlangıç, son projeler ve proje oluşturma |
| `Sources/Gonavi/SmokeTest.swift` | Üretilmiş medya ile gerçek export doğrulaması |
| `.github/workflows/macos.yml` | macOS build ve test |

İlk timeline SwiftUI ile kurulmuştur; geniş projelerde sanallaştırılmış AppKit çizimiyle değiştirilecek. Core Image, uygun cihazda GPU kullanabilir; özel Metal shader pipeline'ı henüz yoktur.
