# Gonavi

SwiftUI tabanlı, yerel çalışan macOS video editörü. **0.6 teknik önizleme**; CapCut kapsamındaki tam ürün henüz tamamlanmadı.

## İndir ve çalıştır

1. [GitHub Releases](https://github.com/netpixdev/gonavi/releases) üzerinden sürüm paketini indir veya [Actions](https://github.com/netpixdev/gonavi/actions/workflows/macos.yml) sayfasında **başarılı** son çalışmayı aç.
2. Intel Mac için `Gonavi-macOS-x86_64`, M serisi Mac için `Gonavi-macOS-arm64` artifact'ını indir. Artifact içindeki aynı adlı ZIP dosyasını aç.
3. `Gonavi.app` dosyasını Applications klasörüne taşı ve aç.
4. macOS geliştiriciyi doğrulayamadığını söylerse, bu uygulama için Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç yolunu kullan.

**Gereksinim:** macOS 14 Sonoma veya üzeri. Intel (`x86_64`) ve Apple Silicon (`arm64`) için ayrı paketler üretilir ve her biri kendi mimarisindeki macOS runner'da test edilir. Ücretli Apple Developer hesabı gerekmez; uygulama ad-hoc imzalıdır, Developer ID imzası veya notarization yoktur. Gatekeeper'ın genel ayarlarını değiştirmek gerekmez.

## Bu sürümde çalışan akış

- Hesap gerektirmeyen başlangıç ekranı, son 12 proje, arama ve açık projeye dönüş.
- Proje adı, oran ve FPS seçimiyle yeni proje oluşturma penceresi.
- Kurtarılabilir oturumu açılışta gösterme; kullanıcı seçince devam etme.
- Video, ses ve fotoğraf dosyası içe aktarma; Finder'dan toplu sürükle bırak. JPEG, PNG, HEIC ve TIFF fotoğrafları ana hatta eklenir.
- Bir ana kurgu hattında video, fotoğraf ve ses klipleri; bölme, ripple silme, boşluk bırakarak taşıma ve yakın kenarlara mıknatıslanma.
- Video ve yalnızca ses dosyalarında gerçek tepe/RMS dalga formu; sessizlik, düşük ses ve güçlü ses bölgeleri aynı ölçekte görünür.
- Ses seviyesine göre otomatik sessizlik önerileri; seçili klip veya tüm kurgu analizi, kesimleri dinleme/seçme ve tek işlemde uygulama/geri alma.
- Görünen bölümü çizen AppKit timeline; yatay kaydırma, yakınlaştırma, sığdırma ve sürükleme sırasında kenarda otomatik kaydırma.
- Yalnızca ses dosyasıyla kurgu, oynatma, otomatik altyazı ve M4A dışa aktarma.
- 9:16, 16:9, 1:1, 4:5 sahneleri; 24/25/30/60 fps.
- Seçili video/fotoğrafı önizleme üzerinde taşıma ve köşelerinden ölçekleme; döndürme, dört kenardan kaynak kırpma ve sayısal konum ayarları.
- Fit/fill, %5–800 ölçek, −180°…180° döndürme; fotoğraf süresi ve klip ses seviyesi ayarı.
- Bağımsız bir müzik hattı ve ses seviyesi; müzik döngüye alınmaz.
- Elle altyazı oluşturma/düzenleme; Sade, Vurgu, Kutu stilleri; SRT export.
- Aynı compositor ile video önizleme ve MP4 export; altyazılar videoya gömülür.
- JSON `.gonavi` proje kaydı, son oturum kurtarma, 100 adımlık geri alma/yineleme.
- Medya sağ tık menüsünden eksik dosyayı yeniden bağlama.
- Export ilerlemesi, iptal; başarısız export mevcut hedef dosyayı silmez.

### Hızlı kullanım

Başlangıçta **Yeni proje** seç; ad, sahne oranı ve FPS belirleyip **Projeyi oluştur** de. `⌘I` ile video, fotoğraf veya ses ekle. Timeline'da bir klibe tıkla. Zaman cetvelinde istediğin yere tıklayıp **Böl** de; istenmeyen parçayı seçip sil. Görsel klibi önizlemede taşı; köşelerinden boyutlandır. Klip sekmesinden döndürme ve kaynak kırpma ayarlarını yap. Altyazı sekmesinde `+` ile metin ekle, **Metni Uygula** de; zamanlarını saniye olarak düzenle. `⌘S` ile projeyi kaydet, `⌘E` ile video dışa aktar.

Editörün sol üstündeki çalışma alanı düğmesi başlangıca döner; açık proje korunur. Son projelerde sağ tık → **Geçmişten Kaldır**, yalnızca geçmiş kaydını kaldırır. Kaynak dosyayı silmez. Bir proje taşınırsa **Proje aç** ile yeni konumunu seçebilirsin.

Timeline üzerinde iki parmak veya fare tekerleğiyle yatay gezin. `⌘` ile kaydırmak imleç çevresinde yakınlaştırır; **Sığdır** bütün projeyi gösterir. Sağ/sol ok düğmeleri bir görünüm kadar kaydırır. Oynatma sırasında çizgi görünür tutulur. Boş zamana klip bırakarak projeyi uzatabilirsin; tuvalin genişliği proje süresiyle büyümez. Eski 24 saatlik toplam proje sınırı kaldırıldı. Matematiksel sonsuzluk iddiası yoktur: en fazla 10.000 klip/medya, kaynak başına 24 saat ve fiziksel cihaz kaynakları sınırları geçerlidir.

**Mıknatıs** açıkken klibin başı veya sonu, 8 ekran pikseli yakınındaki klip uçlarına ve oynatma çizgisine hizalanır. Sarı çizgi hedefi, kesikli dikdörtgen bırakılacak konumu gösterir. Timeline odaktayken `S` açıp kapatır; `⌥` sürükleme sırasında geçici olarak kapatır. Çakışan kliplerin üzerine yazılmaz; en yakın yeterli boşluk seçilir. Taşıma önceki yerde boşluk bırakır. **Sil**, klip süresini kaldırıp sonraki klipleri ve altyazıları kaydırır. Her taşıma tek undo işlemidir.

Finder'dan timeline'a veya medya listesine dosya bırakılabilir. Medya listesindeki öğe timeline'a sürüklenince yeni kopyası eklenir. Fotoğraflar başlangıçta 5 saniyedir; seçili fotoğrafın süresi Klip panelinden değiştirilebilir. Ses dosyası ana hatta kendi klibi olarak eklenir; ayrıca müzik için medyada sağ tık → **Müzik Olarak Ekle** kullanılabilir.

Dalga formunun dış kısmı tepeyi, iç kısmı RMS seviyesini gösterir. Ortak karekök gösterim ölçeği düşük sesleri görünür kılar; dosyalar ayrı ayrı normalize edilmez. Sıfıra yakın ses düz çizgi olur, yüksek tepe genişler; tam ölçeğe yaklaşan tepe turuncudur. Bu bir LUFS veya konuşma/sessizlik sınıflandırıcısı değildir. Stereo kanallar birbirini söndürmez: tepe kanalların maksimumu, RMS kanal enerjilerinin ortalamasıdır. Kaynakta ses hattı yoksa **Ses hattı yok**, analiz sürüyorsa ayrı yükleme durumu gösterilir. Önbellek `~/Library/Caches/Gonavi/Waveforms` içindedir (disk bütçesi 256 MB); dosya değişince veya **Dalga Formunu Yeniden Oku** ile yenilenir.

## Önizlemede taşıma, dönüşüm ve kırpma

Timeline'da video veya fotoğraf klibini seç ve oynatma çizgisini o klibin üzerine getir. Önizlemedeki seçili görseli sürükleyerek sahne üzerinde konumlandır; köşe tutamaklarıyla oranını koruyarak büyüt veya küçült. Bir sürükleme tek geri alma işlemidir. Sürükleme sırasında `Esc`, o hareketin taslağını iptal eder; `⌘Z` tamamlanan hareketi geri alır.

Önizlemedeki görünüm yüzdesi %5–100 arasında sahneyi uzaklaştırır; büyük veya sahne dışına taşmış görselin tutamaklarına erişmeyi sağlar ve çıktıyı değiştirmez. Üst tutamak döndürür; ⇧ basılıyken 15° adımlarına hizalanır. Önizlemenin **Kırp** modunda dört kenar tutamağı kaynak kırpmasını değiştirir. Taşıma sahne merkezine mıknatıslanır; ⌥ bunu geçici kapatır. Ok tuşları 1 piksel, ⇧ ile 10 piksel taşır. Klip panelindeki sayısal ayarlar hassas yerleştirme içindir. Ölçek %5–800, döndürme −180°…180° aralığındadır; pozitif açı saat yönünün tersidir. Konum, sahne merkezine göre ayarlanır; görsel sahne sınırlarının dışına da taşınabilir. Sol, üst, sağ ve alt kırpma değerleri kaynak görselin kenarlarını keser; her eksende en az %5 içerik korunur. Bu kaynak kırpması, klibin timeline süresinden bağımsızdır. Fit/fill yerleşimi, kırpma, ölçek, döndürme ve konum önizleme ile dışa aktarmada aynı geometriyi kullanır; fotoğraf ve video yön bilgisi hesaba katılır.

Bu sürümde dönüşüm klibin tamamı boyunca sabittir. Birden fazla görseli aynı anda üst üste koyan video katmanları ve zaman içinde değişen keyframe animasyonu henüz yoktur. İçe aktarılan fotoğrafın veya videonun orijinal dosyası değiştirilmez.

## Ücretsiz sessizlik temizleme

**Sessizlik temizleme** penceresinde **Seçili klip** veya **Tüm kurgu** kapsamını seç. Varsayılan eşik **−38 dBFS**; **−60 ile −20 dBFS** arasında ayarlanabilir. Minimum sessiz süre **0,5 saniye**, konuşma kenarlarında bırakılan pay **0,12 saniye** ile başlar. Daha yüksek eşik, daha fazla düşük sesli bölgenin aday olmasına yol açabilir; kesimleri dinleyerek karar ver.

Analiz, ana kurgu hattındaki video/ses kliplerinin orijinal ses seviyesini ve kısa ses tepelerini koruyan ek kontrolü kullanır. Klip ses seviyesi ayarı ve ayrı müzik hattı analize dahil edilmez. Bütün işlem bu Mac'te yapılır; ücret, hesap, model indirme veya internet gerekmez. İlerleme gösterilir ve analiz iptal edilebilir.

Önerilen kesimler önce listelenir: her birini dinleyebilir, seçimini kaldırabilir ve yalnızca seçtiklerini uygulayabilirsin. Uygulama sonraki klip ve altyazı zamanlarını kaldırılan süreye göre kaydırır; tek `⌘Z` bütün işlemi geri alır. Ek müzik kesilip birleştirilmez; yeni proje süresiyle sınırlı olarak kesintisiz çalar ve döngüye alınmaz. Kaynak dosyalar değiştirilmez.

Bu araç **ses seviyesine dayalıdır; konuşma algılama/VAD değildir**. Fısıltı, düşük sesli sözcük veya ortam sesi eşik altında kalabilir; gerçek kayıtlarında önerileri kontrol et. Fiziksel Mac üzerinde dinleme ve etkileşim kabul testi hâlâ gereklidir.

## Ücretsiz otomatik Türkçe altyazı

Editörde **Altyazı → Otomatik Altyazı** seç. Varsayılan **Dengeli** model (çok dilli Whisper Small Q5_1, 190 MB), Intel Mac için başlangıç seçimidir. **Daha yüksek doğruluk** (Medium Q5_0, 539 MB) zor konuşmalarda yardımcı olabilir; daha çok bellek ve işlem süresi ister. Bu seçim bir Türkçe doğruluk karşılaştırması sonucu değildir; fiziksel cihaz ve kendi videolarınla değerlendirilmelidir.

İlk kullanımda **Modeli İndir ve Oluştur**, sonraki kullanımlarda **Altyazı Oluştur** de. Hesap, API anahtarı ve ücret gerekmez. Model bir kez Hugging Face üzerinden indirilir ve SHA-256 ile doğrulanır; videonun sesi cihazdan çıkmaz. Sonraki işlemler çevrimdışı çalışır. Modeller `~/Library/Application Support/Gonavi/Models` içinde tutulur; uygulama ZIP'ine dahil değildir.

Ana kurgu hattındaki video ve ses kliplerinin orijinal sesi kullanılır; ek müzik ve ses seviyesi efektleri dahil edilmez. İşlem ilerlemesi ve iptal vardır. Sonuç önce önizlenir, **Altyazıları Ekle / Mevcut Altyazıları Değiştir** ile uygulanır; tek `⌘Z` ile geri alınabilir. Altyazılar düzenlenebilir, SRT veya videoya gömülü olarak dışa aktarılabilir. [Motor ve model ayrıntıları](docs/AUTO-CAPTIONS.md).

## Sınırlar

- Kelime vurgulu animasyon, özel şablon içe aktarma, çoklu video katmanları, keyframe ve proxy henüz uygulanmadı. Ses seviyesine göre sessizlik temizleme vardır; gerçek konuşma algılama/VAD henüz yoktur. [Yol haritası](docs/ROADMAP.md).
- Otomatik altyazının yazım ve zaman kodları kontrol edilmelidir. Müzik, gürültü ve uzun sessizliklerde yanlış metin üretilebilir. Temel sessiz-ses kontrolü vardır; tam konuşma algılama/VAD henüz yoktur. Uzun klipler 5 dakikalık parçalara ayrılır; parça sınırındaki sözcükler düzeltme gerektirebilir. Apple Speech motoru henüz eklenmedi.
- Klip süresini kesme bu aşamada böl + sil ile yapılır; timeline kenarından sürükleyerek trim henüz yok. Görselin kaynak kenarlarını kırpma desteklenir.
- `.gonavi` şu anda bir JSON dosyasıdır; medya dosyalarını içine kopyalayan taşınabilir paket henüz yok. Kaynak medya dosyalarını sakla.
- Klip içindeki altyazılar taşımayı takip eder. Klip sınırını aşan altyazı bölünür; aynı metin parçaların her birinde kalır. Sonucu gözden geçir. Şema 1 ve 2 projeleri açılır; yeni kayıtlar fotoğraf ve dönüşüm verileri için şema 3 kullanır. Yeni kaydı eski Gonavi sürümleri açamaz.
- Proje zamanlarında 60.000 tick/sn kullanılır. Render süreleri çıktı FPS'ine oturtulur; VFR/telefon/HDR uyumluluğu fiziksel Mac testleriyle genişletilecek.
- Render SDR/Rec.709 hedefler; HDR koruma ve profesyonel renk doğruluğu iddiası yoktur.
- Yerel font ve bitmap altyazı; mevcut ilk tasarım uzun metin için en fazla 500 karakter kabul eder. Kısa altyazı blokları kullan.
- Arayüz ve gerçek cihaz performansı Windows üzerinden doğrulanamaz. Başarılı CI, fiziksel Mac kabul testinin yerine geçmez.
- Aktif oturumun otomatik kaydı `~/Library/Application Support/Gonavi/recovery.json` içindedir. Kurtarmadan başka proje açılırsa önceki oturum `Recovered Projects` altında ayrı bir `.gonavi` dosyası olarak korunur ve son projelere eklenir. Önceki kurtarmaların üzerine yazılmaz. Son projeler `recents.json` içinde tutulur. İçe aktarılan medya kopyalanmaz. Proje/medya ağ üzerinden gönderilmez.

## Geliştirme

Swift Package; macOS üzerinde Xcode 16.4 / Swift 6.1, Swift 5 dil modu. Paketleme CMake ile sabitlenmiş whisper.cpp kaynağını derler; Intel CPU/Accelerate, Apple Silicon Metal/Accelerate kullanır. Python, Homebrew veya FFmpeg çalışma zamanı bağımlılığı yoktur. CMake yalnızca derleme sırasında gerekir.

```sh
swift test
bash scripts/build-app.sh
open dist/Gonavi.app
dist/Gonavi.app/Contents/MacOS/Gonavi --smoke-test dist/smoke
bash scripts/test-captions.sh
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

Timeline, yalnızca görünür bölgeyi çizen AppKit görünümüdür. Dalga özeti kademeli tepe/RMS verisinden çizilir; ham PCM bütünü bellekte tutulmaz. Core Image, uygun cihazda GPU kullanabilir; özel Metal shader pipeline'ı henüz yoktur.
