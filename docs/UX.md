# Gonavi kullanıcı deneyimi

Gonavi, bir kişinin kendi Mac'inde video üretmesi için tasarlanır. Hesap oluşturma, parola veya abonelik akışı yoktur. İlk hedef, kullanıcıyı boş bir timeline karşısında bırakmadan ilk projesini oluşturabilmesidir.

## Uygulanan akış — 0.4

1. **Başlangıç:** yeni proje, proje aç, son 12 kaydedilen/açılan proje ve arama. Geçmiş yoksa açık bir boş durum metni. Kurtarılabilir oturum varsa kullanıcıya devam seçeneği.
2. **Yeni proje:** ad → sahne oranı → FPS → oluştur. Oranlar küçük sahne çizimleriyle gösterilir; çözünürlük canlı güncellenir. Kapatmak mevcut çalışmayı değiştirmez.
3. **Editör:** solda kaynak medya, ortada önizleme, sağda sahne/klip/altyazı özellikleri, altta timeline. Üstte kaydet, geri al/yinele ve export. Başlangıca dönüş açık projeyi korur.
4. **Çıkış:** kaydedilmemiş değişiklikler için Kaydet/Vazgeç/Kaydetme. Yeni proje mevcut kaydedilmemiş çalışmayı doğrudan silmez.
5. **Export:** ilerleme, iptal ve sonuç dosyasını Finder'da gösterme. Hata mevcut hedef dosyayı silmez.

## Sonraki UX işleri

- Medya thumbnail'leri; çok kanallı dalga için ayrı kanal görünümü.
- Trim tutamakları ve çoklu seçim.
- Preview üzerinde crop ve zoom tutamakları; sayısal ayarlar sağ panelde kalır.
- Sessizlik temizleme: analiz → önerilen kesimleri dinleme → seçerek uygula → tek undo.
- Otomatik altyazı: konuşma algılama ve gelişmiş kelime zamanları; mevcut model → önizleme → uygula akışı korunur.
- Şablon önizlemeleri yalnızca çalışan, gerçek şablonları gösterir. Hazır olmayan özellik için çalışıyormuş gibi düğme sunulmaz.
- Proje thumbnail'leri, taşınabilir medya paketi, çoklu sahne varyantları.
- Klavye gezinmesi, VoiceOver, kontrast ve dar MacBook penceresinde fiziksel kullanım testi.

## Görsel yaklaşım

0.4: graphite yüzey katmanları, ortak birincil butonlar, tepe/RMS dalga renkleri ve ayrı ses önizlemesi. Timeline AppKit viewport ile çizilir; cetvel ve hat adları sabit kalır. Gerçek dalgalar, mıknatıs hedef çizgisi ve sürükleme gölgesi eklenmiştir. Kenarda sürüklemek otomatik kaydırır. Klip taşımak içindeki altyazıyı beraber taşır; sınırı aşan metin parçalara ayrılır. Yalnızca ses projesi M4A çıkarır. Otomatik altyazı sonucu uygulanmadan önce incelenir.

Koyu ve sakin yüzeyler; mint vurgu yalnızca birincil eylem ve seçili öğelerde. Yerel sistem yazıları, gerçek macOS pencere kontrolleri, minimum dekorasyon. Video önizlemesi editörde en büyük alanı alır. 1280×820 varsayılan, 1040×720 minimum çalışma alanı; paneller yeniden boyutlandırılabilir.

CI ekran görüntüleri gerçek SwiftUI/AppKit görünümlerinden alınır; tasarım maketi değildir. Ekran görüntüsü yerleşimi denetler; fiziksel Mac'te fare, klavye, ses ve uzun video akıcılığı testi yine gereklidir.
