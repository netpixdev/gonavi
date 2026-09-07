# Gonavi kullanıcı deneyimi

Gonavi, bir kişinin kendi Mac'inde video üretmesi için tasarlanır. Hesap oluşturma, parola veya abonelik akışı yoktur. İlk hedef, kullanıcıyı boş bir timeline karşısında bırakmadan ilk projesini oluşturabilmesidir.

## Uygulanan akış — 0.6

1. **Başlangıç:** yeni proje, proje aç, son 12 kaydedilen/açılan proje ve arama. Geçmiş yoksa açık bir boş durum metni. Kurtarılabilir oturum varsa kullanıcıya devam seçeneği.
2. **Yeni proje:** ad → sahne oranı → FPS → oluştur. Oranlar küçük sahne çizimleriyle gösterilir; çözünürlük canlı güncellenir. Kapatmak mevcut çalışmayı değiştirmez.
3. **Editör:** solda kaynak medya, ortada önizleme, sağda sahne/klip/altyazı özellikleri, altta timeline. Üstte kaydet, geri al/yinele ve export. Başlangıca dönüş açık projeyi korur.
4. **Çıkış:** kaydedilmemiş değişiklikler için Kaydet/Vazgeç/Kaydetme. Yeni proje mevcut kaydedilmemiş çalışmayı doğrudan silmez.
5. **Export:** ilerleme, iptal ve sonuç dosyasını Finder'da gösterme. Hata mevcut hedef dosyayı silmez.
6. **Sessizlik temizleme:** seçili klip/tüm kurgu → eşik, minimum süre ve kenar payı → ilerlemeli/iptal edilebilir analiz → önerilen kesimleri seçme ve dinleme → seçilenleri uygula → tek undo. Başlangıç değerleri −38 dBFS (ayar aralığı −60…−20), 0,5 saniye minimum sessizlik ve 0,12 saniye kenar payıdır.
7. **Görsel düzenleme:** video/fotoğrafı timeline'da seç → önizlemede sürükleyerek konumlandır, köşelerinden oranlı boyutlandır veya üst tutamaktan döndür. Kırp modunda dört kenar tutamağını sürükle. Hassas konum, döndürme ve kaynak kırpma ayarları sağ Klip panelindedir. Bir sürükleme bir undo işlemidir; `Esc` sürmekte olan hareketi iptal eder.
8. **Fotoğraf:** JPEG/PNG/HEIC/TIFF içe aktar veya sürükle bırak → ana hatta 5 saniyelik görsel klip → Klip panelinde süreyi değiştir → video ile aynı dönüşüm ve MP4 dışa aktarma akışını kullan.

Sessizlik aracı ana video/ses kliplerinin orijinal ses seviyesi ve kısa ses tepeleri üzerinden öneri üretir; konuşmanın anlamını veya varlığını tanımaz. Ek müzik analize dahil değildir. Seçilen kesimler uygulanınca klipler ve altyazılar kaldırılan süreye göre kayar; müzik kesilip birleştirilmeden yeni süreyle sınırlanır. Bu işlem ücretsiz, yerel ve modelsizdir. Düşük sesli sözcükler için dinleme adımı önemlidir; fiziksel Mac kabul testi beklenir.

## Sonraki UX işleri

- Medya thumbnail'leri; çok kanallı dalga için ayrı kanal görünümü.
- Trim tutamakları ve çoklu seçim.
- Çoklu video katmanı seçimi, katman sırası ve keyframe dönüşüm denetimleri; mevcut tek klip taşıma/boyutlandırma akışı korunur.
- Sessizlik temizlemede gerçek kayıtlarla eşik/payı değerlendirme ve konuşma algılama/VAD ekleme; mevcut dinle/seç/uygula akışı korunur.
- Otomatik altyazı: konuşma algılama ve gelişmiş kelime zamanları; mevcut model → önizleme → uygula akışı korunur.
- Şablon önizlemeleri yalnızca çalışan, gerçek şablonları gösterir. Hazır olmayan özellik için çalışıyormuş gibi düğme sunulmaz.
- Proje thumbnail'leri, taşınabilir medya paketi, çoklu sahne varyantları.
- Klavye gezinmesi, VoiceOver, kontrast ve dar MacBook penceresinde fiziksel kullanım testi.

## Görsel yaklaşım

0.4: graphite yüzey katmanları, ortak birincil butonlar, tepe/RMS dalga renkleri ve ayrı ses önizlemesi. Timeline AppKit viewport ile çizilir; cetvel ve hat adları sabit kalır. Gerçek dalgalar, mıknatıs hedef çizgisi ve sürükleme gölgesi eklenmiştir. Kenarda sürüklemek otomatik kaydırır. Klip taşımak içindeki altyazıyı beraber taşır; sınırı aşan metin parçalara ayrılır. Yalnızca ses projesi M4A çıkarır. Otomatik altyazı sonucu uygulanmadan önce incelenir.

0.5 bu çalışma alanını korur; sessizlik önerileri ayrı inceleme akışında sunulur. Analiz, başarısızlık, iptal, kesim bulunamadı ve seçilmiş kesimler durumları açıkça ayrılır. Kesimler kullanıcının uygulama eylemiyle projeye yazılır; hazır olmayan VAD veya çoklu katman desteği gösterilmez.

0.6, önizlemeyi seçili video/fotoğrafın doğrudan düzenlendiği alan yapar. Seçim çerçevesi ve köşe tutamakları konumu ve ölçeği görünür kılar. Kaynak kırpması, timeline süresini kesmekten ayrı bir işlemdir; dört kenar değeri kaynağın görünür bölümünü belirler. Ölçek, döndürme ve konum için sayısal denetimler hassas düzenlemeyi tamamlar. Kaynak yönü, crop ve dönüşüm sırası önizleme/export arasında ortaktır. Düzenleme kaynak dosyayı değiştirmez; dönüşüm klibin tamamında sabittir.

Koyu ve sakin yüzeyler; mint vurgu yalnızca birincil eylem ve seçili öğelerde. Yerel sistem yazıları, gerçek macOS pencere kontrolleri, minimum dekorasyon. Video önizlemesi editörde en büyük alanı alır. 1280×820 varsayılan, 1040×720 minimum çalışma alanı; paneller yeniden boyutlandırılabilir.

CI ekran görüntüleri gerçek SwiftUI/AppKit görünümlerinden alınır; tasarım maketi değildir. Ekran görüntüsü yerleşimi denetler; fiziksel Mac'te fare, klavye, ses ve uzun video akıcılığı testi yine gereklidir.
