# Ücretsiz Türkçe otomatik altyazı — motor kararı

Motor araştırması: 5 Eylül 2026. Uygulama durumu: 0.5, 6 Eylül 2026. Kullanıcı hedefi Intel MacBook, macOS Sonoma 14 veya üzeri; Apple Silicon paketi de korunur.

## Karar

Wispr Flow/WhisperFlow uygulamasına veya ücretli bir transkripsiyon aboneliğine bağımlılık kurulmayacak. Önceki plandaki whisper.cpp, bu ürünlerden bağımsız açık kaynaklı yerel konuşma tanıma motorudur.

Ücretsiz altyazı için değiştirilebilir motor arayüzü kullanılacak:

1. **Intel/Sonoma ana yolu:** whisper.cpp ve çok dilli Whisper modeli. Model ilk kullanımda indirilir, tanıma cihazda yapılır. Türkçe için `.en` modelleri seçilmez. Model lisansı/dağıtım kaynağı sürüm sabitlenirken ayrıca kaydedilir. Hız ve Türkçe doğruluk kullanıcı cihazında ölçülür.
2. **İsteğe bağlı Apple yolu:** uygun macOS sürümü, donanım, Türkçe locale ve yerel model desteği sorgulanır. Destek doğrulanmadan Apple motoru kullanılabilir gösterilmez.
3. Sesin Apple sunucularına otomatik gönderildiği bir fallback olmayacak. Eski Speech API'sinin ağ modu ayrıca eklenirse kullanıcıya hedef ve kısıtlar açıklanır, kullanıcı seçimi gerekir.

0.3 sürümü whisper.cpp tabanlı otomatik Türkçe altyazı hattını uygular. 0.4'te ana kurgu hattındaki yalnızca ses klipleri ve boşluklu klip konumları da desteklenir. Apple motoru ve ortak değiştirilebilir motor arayüzü gelecek kapsamıdır; mevcut arayüzde Apple desteği gösterilmez.

### Uygulanan varsayılan

- Motor: whisper.cpp b4938, commit `371b5a7561823ab2bb32142d2751e35e7534727b`; yardımcı ikili uygulamaya eklenir ve ad-hoc imzalanır. Çalışma zamanında Python/FFmpeg gerekmez.
- Dengeli: çok dilli `ggml-small-q5_1.bin`, 190.085.487 bayt. SHA-256 `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb`.
- Daha yüksek doğruluk: çok dilli `ggml-medium-q5_0.bin`, 539.212.467 bayt. SHA-256 `19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f`.
- Model deposu sürümü: Hugging Face `ggerganov/whisper.cpp` revision `5359861c739e955e79d9a303bcbc70fb988958b1`. Boyut ve özet doğrulanmadan model kullanılmaz. Modeller ilk kullanımda ayrıca indirilir; indirildikten sonra ağ gerekmez.
- Sabit Türkçe transkripsiyon (`-l tr`, çeviri kapalı). Ana kurgu hattındaki video ve ses kliplerinden beş dakikaya kadar kaynak ses parçaları, 16 kHz mono PCM WAV. Trim, gecikmiş ses başlangıcı ve klibin boşluklu timeline konumu korunur. Ayrı müzik hattı ve klip ses seviyesi efektleri tanımaya dahil edilmez.
- CLI kelime sınırlarında kısa segmentler üretir; segment zamanları projeye taşınır. Sonuç önizlenir; bütün mevcut altyazıları değiştirme açık bir eylemdir ve tek adımda geri alınır. Hata ve iptal projeye kısmi sonuç yazmaz.

Small seçimi Intel için boyut/bellek/doğruluk dengesi kararıdır; her Türkçe kayıt için en iyi doğruluğu verdiği iddia edilmez. Medium daha yavaş olabilir. Gerçek Türkçe kullanıcı videolarında WER/CER ve Intel işlem süresi henüz ölçülmemiştir. CI'da gerçek motorla İngilizce ses ve sistemde varsa sentetik Türkçe ses entegrasyon testleri çalışır; bunlar insan konuşması doğruluk karşılaştırması değildir.

0.4'te klip içindeki altyazılar klip taşınırken birlikte taşınır; klip sınırını aşan altyazı bölünür ve aynı metin parçalarda korunur. Ripple silme zamanları yeniden eşler. Bu davranış kalıcı kaynak-zaman bağları veya kelime düzeyinde yeniden bölme değildir; taşıma sonrası sonuç gözden geçirilmelidir.

0.5'te ayrı bir ses seviyesine göre sessizlik temizleme akışı vardır: seçili klip/tüm kurgu → eşik (varsayılan −38 dBFS, −60…−20) → minimum sessizlik (0,5 sn) ve kenar payı (0,12 sn) → ilerleme/iptal → kesimleri dinle ve seç → tek undo ile uygula. Orijinal klip sesi ve kısa ses tepelerini koruyan kontrol kullanılır. Altyazı zamanları kaldırılan aralıklara göre yeniden eşlenir; ek müzik kesilip birleştirilmeden yeni proje süresiyle sınırlanır. Bu analiz ücretsiz ve cihazda çalışır, Whisper modeli gerektirmez. Transkripsiyon akışına otomatik VAD eklendiği anlamına gelmez.

Henüz olmayanlar: konuşma algılama/VAD, kelime vurgusu, güven skoru arayüzü, kalıcı kaynak-zaman bağları ve kesintili indirmeye kaldığı yerden devam. Gerçek tepe/RMS dalga formu video, ana ses klibi ve müzikte ses seviyelerini gösterir; konuşma sınıflandırıcısı değildir. Ses eşiği düşük sesli sözcükleri yanlış aday gösterebileceği için kesimler dinlenmelidir; gerçek Intel Mac kabul testi hâlâ gereklidir. Bozuk model arayüzden kaldırılıp yeniden indirilebilir. Beş dakikalık parça sınırlarında konuşma bağlamı kesilebilir.

## Apple Dikte ile API arasındaki fark

Kullanıcının paylaştığı [Apple Dikte kılavuzu](https://support.apple.com/en-gb/guide/mac-help/mh40584/mac), konuşarak bir metin alanına yazmayı anlatır. Apple'ın [özellik kullanılabilirliği listesinde](https://www.apple.com/macos/feature-availability/) Türkçe Dikte vardır. Bu, dosya içe aktarma, kelime zamanları veya SRT üretme garantisi değildir.

| Yol | Sistem şartı | Gonavi açısından anlamı |
| --- | --- | --- |
| Klavye Diktesi | macOS özelliği; dil/cihaz koşulları değişir | Kullanıcı metin yazabilir; video dosyası için zaman kodlu toplu altyazı hattının yerine geçmez. |
| SFSpeechRecognizer + SFSpeechURLRecognitionRequest | macOS 10.15+ | Kayıtlı ses dosyası tanınabilir. Türkçe ve yerel çalışma cihazda sorgulanır; bazı diller ağ ister. Apple eski API için süre ve kota sınırları belgeler. |
| SpeechAnalyzer + SpeechTranscriber | macOS 26+ | Uzun kayıtlar için yeni yerel API; Sonoma'da yok. Donanım ve Türkçe desteği runtime sorgulanır. |
| SpeechAnalyzer + DictationTranscriber | macOS 26+ | Sistem diktesinin yerel modellerini kullanan alternatif modül. Yalnızca ağ üzerinden desteklenen dilleri desteklemez. |

Apple'ın bu API belgelerinde sabit, kapsamlı bir Türkçe destek tablosu yoktur. Klavye Dikte listesinden SpeechTranscriber/DictationTranscriber desteği çıkarılmayacak. İncelenen belgelerden Intel tamamen desteklenmiyor sonucu da çıkarılmadı; donanım için isAvailable/supportedLocales kontrolü esas alınır.

## Mevcut altyapı ve sonraki entegrasyonlar

1. Mevcut whisper.cpp hattını `TranscriptProvider` ortak arayüzüne ayır: kaynak medya kimliği, kaynak zaman aralığı, locale, iptal ve ilerleme. İkinci motor henüz yoktur.
2. Mevcut segment metni/zamanları üzerine kelime düzeyinde zamanlar, varsa güven skoru ve kullanılan motor/model sürümü ekle.
3. Kaynak sesten, müzik miksajından önce PCM çıkarma; beş dakikalık parçalar, geçici dosya temizliği ve güvenli iptal uygulanmıştır. Sonraki adım VAD ve parça sınırlarında bağlamı korumadır.
4. Mevcut kısa segmentleri noktalama/duraklama, okunabilir satır uzunluğu ve süre sınırlarıyla iyileştir. Kullanıcının düzelttiği metni koru.
5. Üretim sırasında trim ve klip başlangıcıyla timeline eşlemesi; sonraki taşıma ve ripple silmede altyazı zamanlarını güncelleme uygulanmıştır. Kalıcı kaynak-zaman bağları, hız değişimi ve çoklu katman eşlemesi ileriki kapsamdır.
6. CI entegrasyonlarına ek olarak gerçek Intel Mac ve insan konuşmasıyla Türkçe test seti: özel isimler, düşük ses, arka plan müziği, 10+ dakikalık kayıt, model eksikliği ve iptal.

## Apple yolunda gerekli kontroller

- Yeni API: `if #available(macOS 26, *)`, `SpeechTranscriber.isAvailable`, `supportedLocale(equivalentTo:)`, model/asset kurulumu.
- Eski API: `supportedLocales()`, `isAvailable`, Speech izni; yerel mod için `supportsOnDeviceRecognition == true` ve `requiresOnDeviceRecognition = true` birlikte zorunlu.
- Kişisel ad-hoc imzalı Gonavi'de izin/tanıma gerçek Mac üzerinde test edilmeden destek tamamlandı sayılmaz. İncelenen kaynaklar macOS için ücretli üyeliğin zorunlu olduğu sonucunu doğrulamıyor.
- CI, kurgu/mapping ve hata yollarını doğrular; CI makinesinde bir dil modelinin bulunmaması kullanıcı Mac'inde destek olmadığı anlamına gelmez.

## Birincil kaynaklar

- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer.md) — macOS 26 metadata.
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber.md) — cihaz/dil sorgulaması.
- [DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber.md) — yerel Dikte modelleri, network-only locale sınırı.
- [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer?changes=_3_1) — kayıtlı ses, süre/kota ve ağ koşulları.
- [supportsOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition).
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) — MIT lisansı, Intel/Arm ve yerel çalıştırma.
