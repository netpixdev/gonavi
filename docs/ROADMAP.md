# Gonavi geliştirme planı

## Aşama 0–1: teknik temel — bu teslimat

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

1. Kaynak-zaman ve sahne-zaman eşleme katmanını genişlet.
2. Bağlı ses/video, caption anchor, ripple kapsamı ve kilitli katman davranışını belirle.
3. Çoklu video/audio track, trim tutamakları, snapping, çoklu seçim, boşluklar.
4. AppKit ile görünür alan çizimi; thumbnail ve waveform cache.
5. Proxy üretimi ve preview kalite ayarı. Export her zaman orijinal medya.
6. Taşınabilir `.gonavi` paket, medya toplama, şema migration ve yedekler.

Kabul: 30 dakikalık projede kurgu/kayıt/export senkron kalır; kayıp medya yeniden bağlanır; geri alma toplu komutları tek adımda döndürür.

## Aşama 3: konuşma videoları

Ücretsiz Türkçe altyazı ve Apple Dikte/API uyumluluğu için [motor kararı](AUTO-CAPTIONS.md) esas alınır. Wispr Flow bağımlılığı yoktur. Intel/Sonoma'da whisper.cpp ana yol; uygun cihazda doğrulanmış Türkçe desteğiyle Apple motoru isteğe bağlıdır.

1. PCM çıkarma, RMS analizi, konuşma algılama adaptörü.
2. Minimum sessizlik, başlangıç/son payı ve kesim önizlemesi.
3. Bağlı katmanlarda otomatik kesim; müzik için sürekli tut/kes seçimi.
4. Sabitlenmiş whisper.cpp sürümü ve yerel model yöneticisi.
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
- İlk aşamadaki timeline-anchored altyazılar ve tek track, tam ürün mimarisinin yerine geçmez; migration ile genişletilir.

## İlk Mac kabul testi

- [ ] İndirilen ad-hoc uygulama Applications klasöründen açılıyor.
- [ ] İki video ve bir ses birlikte sürükle bırak ile yükleniyor.
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
