# Gonavi geliştirme planı

## Aşama 0–1: teknik temel — uygulandı

- [x] Swift Package + SwiftUI macOS uygulaması.
- [x] Referans medya, sahne, klip, müzik, altyazı modeli.
- [x] Rasyonel zaman, bölme, ripple silme ve JSON doğrulama testleri.
- [x] Kaydet/aç, atomik kurtarma kaydı, undo/redo.
- [x] Ortak compositor ile preview/export; gerçek medya smoke testi.
- [x] GitHub Actions, ad-hoc paket ve indirilebilir artifact.
- [x] Intel ve Apple Silicon için ayrı macOS build/test matrisi.
- [x] Başlangıç ekranı, son projeler, yeni proje kurulumu, açık çalışmaya dönüş.
- [ ] Kullanıcının Mac'inde ilk açılış ve etkileşim testi.

## Aşama 2: güvenilir timeline

0.4'te uygulananlar:

- [x] Ana kurgu hattında video ve yalnızca ses klipleri; açık zaman konumları ve klipler arasında boşluklar.
- [x] Görünür alanla sınırlı AppKit timeline; yatay gezinme, yakınlaştırma, sığdırma ve sürüklerken kenarda otomatik kaydırma.
- [x] Finder/medya listesinden bırakma ve klip taşımada mıknatıslanma; klip uçları ve oynatma çizgisi hedefleri, geçici `⌥` devre dışı bırakma.
- [x] Gerçek tepe/RMS dalga formu, kademeli veri ve 256 MB disk önbelleği; video sesi, ses klibi ve müzik hattı.
- [x] Kliple birlikte içindeki altyazıları taşıma; sınırı aşan altyazıyı parçalara ayırma, ripple silme ve tek adımlık undo.
- [x] Yalnızca ses projesi oynatma, otomatik altyazı ve M4A export.
- [x] Eski şema 1 proje konumlarını şema 2'ye geçirme; toplam proje için eski 24 saat sınırını kaldırma.

Timeline'ın çizim alanı proje süresiyle büyümez; bu matematiksel sonsuzluk değildir. Proje başına 10.000 klip/medya, kaynak başına 24 saat, zaman türünün sayısal aralığı ve fiziksel cihaz kaynakları sınırları geçerlidir. Tek ana kurgu ve bağımsız tek müzik hattı korunur; çoklu katman sistemi henüz yoktur.

Kalan işler:

1. Kaynak-zamana bağlı kalıcı altyazı kimliği; hız değişimi ve çoklu katman düzenlemeleri için eşleme katmanını genişlet.
2. Ayrılabilir bağlı ses/video, kilitli katmanlar ve toplu ripple kapsamı.
3. Çoklu video/audio track, kenardan trim tutamakları ve çoklu seçim.
4. Medya thumbnail önbelleği ve stereo kanallar için ayrı dalga görünümü.
5. Proxy üretimi ve preview kalite ayarı. Export her zaman orijinal medya.
6. Medyayı içine alan taşınabilir `.gonavi` paket ve gelişmiş yedek yönetimi.

Kabul: 30 dakikalık projede kurgu/kayıt/export senkron kalır; kayıp medya yeniden bağlanır; geri alma toplu komutları tek adımda döndürür.

## Aşama 3: konuşma videoları

Ücretsiz Türkçe altyazı ve Apple Dikte/API uyumluluğu için [motor kararı](AUTO-CAPTIONS.md) esas alınır. Wispr Flow bağımlılığı yoktur. Intel/Sonoma'da whisper.cpp ana yol; uygun cihazda doğrulanmış Türkçe desteğiyle Apple motoru isteğe bağlıdır.

0.3'te temel otomatik altyazı hattı eklendi: Small/Medium model indirme ve doğrulama, kaynak sesinden Türkçe tanıma, zamanlı önizleme, tek adımda uygulama/geri alma ve SRT/MP4 export. 0.4'te ana hatta yalnızca ses klipleri ve boşluklu yerleşim de desteklenir; üretilen altyazılar klibin timeline konumuna yerleştirilir. Sabit whisper.cpp sürümü, yerel model yönetimi ve temel sessiz-ses kontrolü uygulanmıştır. Görsel dalga formu için tepe/RMS analizi vardır; otomatik konuşma/sessizlik sınıflandırması ve kesim yapmaz. Apple motoru henüz uygulanmadı.

Kalan işler:

1. Mevcut PCM çıkarma ve temel ses kontrolü üzerine konuşma algılama/VAD adaptörü.
2. Minimum sessizlik, başlangıç/son payı ve kesim önizlemesi.
3. Bağlı katmanlarda otomatik kesim; müzik için sürekli tut/kes seçimi.
4. Model indirmesine kesintiden devam ve Türkçe kayıtlarla model karşılaştırması.
5. Türkçe/İngilizce test seti, cümle/kelime zamanları, elle düzeltmeyi koruma.
6. Kaynak-zamana bağlı altyazı; kesim ve hızla birlikte yeniden eşleme.
7. Sürümlü özel altyazı şablonları, VTT, kelime vurgusu.

Kabul: 10 dakikalık konuşma videosunu sessizlik temizle → düzelt → altyazı → dikey export akışıyla bitirmek. Tahmin edilen transkripsiyon hataları elle düzeltilebilir olmalı.

## Aşama 4: yaratıcı araçlar

Keyframe/easing, crop tutamakları, hız, freeze frame, geçişler, renk ayarı, EQ/compressor/limiter, ducking. Daha sonra LUT, maske/chroma key ve gelişmiş denoise.

## Aşama 5: sağlamlaştırma

4K, HDR/SDR davranışı, VFR ve döndürülmüş telefon videoları, HEVC/ProRes, uzun export, disk dolması, ani kapanma, iptal, eksik font, bellek bütçesi ve erişilebilirlik.

## Mimari kararlar

- Kaynak dosyalar değişmez; proje düzenleme talimatlarını saklar.
- Export sabit snapshot kullanır. UI ve renderer aynı proje modelini tüketir.
- Yapay zekâ/analiz UI'dan bağımsızdır; ilerleme/iptal zorunludur.
- Intel ve Apple Silicon ayrı paketlerdir; minimum macOS 14 Sonoma. İki mimaride bağımsız CI doğrulaması yapılır.
- Her aşama başarılı CI ve fiziksel Mac kabul testiyle kapanır.
- Şema 2'de boşluklu klip konumları ve taşıma/ripple sırasında altyazı eşlemesi vardır. Altyazılar hâlâ timeline'a bağlıdır; kalıcı kaynak bağları ve çoklu katman için model genişletilir.

## İlk Mac kabul testi

- [ ] İndirilen ad-hoc uygulama Applications klasöründen açılıyor.
- [ ] İki video ve bir ses birlikte sürükle bırak ile yükleniyor.
- [ ] Video/ses dalgasında sessiz, düşük ve güçlü bölümler ayırt ediliyor; müzik dalgası da görünüyor.
- [ ] Boşluğa taşıma, yakın kenara mıknatıslanma, `⌥` ile geçici kapatma ve tek undo çalışıyor.
- [ ] Uzun projede kaydırma, sığdırma ve sürüklerken otomatik kaydırma akıcı.
- [ ] Yalnızca ses dosyasıyla oynatma, Türkçe altyazı ve M4A export çalışıyor.
- [ ] Play/pause, kare ilerleme ve zaman cetvelinde seek çalışıyor.
- [ ] Böl/sil/undo/redo sonrası süre ve görüntü beklenen şekilde.
- [ ] Dikey sahne, crop, zoom ve altyazı preview/export tutarlı.
- [ ] Kaydet, kapat, aç ve medyayı yeniden bağla akışı çalışıyor.
- [ ] Export iptali eski hedef dosyayı koruyor.
- [ ] Türkçe karakter ve uzun dosya adları düzgün görünüyor.

## Kaynaklar

- [AVVideoCompositing](https://developer.apple.com/documentation/avfoundation/avvideocompositing?language=objc)
- [Apple: bilinmeyen geliştiriciden uygulama açma](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)
- [GitHub macOS runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
