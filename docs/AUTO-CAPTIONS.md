# Ücretsiz Türkçe otomatik altyazı — motor kararı

Doğrulama tarihi: 5 Eylül 2026. Kullanıcı hedefi Intel MacBook, macOS Sonoma 14 veya üzeri; Apple Silicon paketi de korunur.

## Karar

Wispr Flow/WhisperFlow uygulamasına veya ücretli bir transkripsiyon aboneliğine bağımlılık kurulmayacak. Önceki plandaki whisper.cpp, bu ürünlerden bağımsız açık kaynaklı yerel konuşma tanıma motorudur.

Ücretsiz altyazı için değiştirilebilir motor arayüzü kullanılacak:

1. **Intel/Sonoma ana yolu:** whisper.cpp ve çok dilli Whisper modeli. Model ilk kullanımda indirilir, tanıma cihazda yapılır. Türkçe için `.en` modelleri seçilmez. Model lisansı/dağıtım kaynağı sürüm sabitlenirken ayrıca kaydedilir. Hız ve Türkçe doğruluk kullanıcı cihazında ölçülür.
2. **İsteğe bağlı Apple yolu:** uygun macOS sürümü, donanım, Türkçe locale ve yerel model desteği sorgulanır. Destek doğrulanmadan Apple motoru kullanılabilir gösterilmez.
3. Sesin Apple sunucularına otomatik gönderildiği bir fallback olmayacak. Eski Speech API'sinin ağ modu ayrıca eklenirse kullanıcıya hedef ve kısıtlar açıklanır, kullanıcı seçimi gerekir.

0.3 sürümü whisper.cpp tabanlı otomatik Türkçe altyazı hattını uygular. Apple motoru gelecek seçenek olarak kalır; mevcut arayüzde destekleniyor gibi gösterilmez.

### Uygulanan varsayılan

- Motor: whisper.cpp b4938, commit `371b5a7561823ab2bb32142d2751e35e7534727b`; yardımcı ikili uygulamaya eklenir ve ad-hoc imzalanır. Çalışma zamanında Python/FFmpeg gerekmez.
- Dengeli: çok dilli `ggml-small-q5_1.bin`, 190.085.487 bayt. SHA-256 `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb`.
- Daha yüksek doğruluk: çok dilli `ggml-medium-q5_0.bin`, 539.212.467 bayt. SHA-256 `19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f`.
- Model deposu sürümü: Hugging Face `ggerganov/whisper.cpp` revision `5359861c739e955e79d9a303bcbc70fb988958b1`. Boyut ve özet doğrulanmadan model kullanılmaz. Modeller ilk kullanımda ayrıca indirilir; indirildikten sonra ağ gerekmez.
- Sabit Türkçe transkripsiyon (`-l tr`, çeviri kapalı). Beş dakikaya kadar kaynak ses parçaları, 16 kHz mono PCM WAV. Trim ve gecikmiş ses başlangıcı korunur. Ek müzik dahil edilmez.
- CLI kelime sınırlarında kısa segmentler üretir; segment zamanları projeye taşınır. Sonuç önizlenir; bütün mevcut altyazıları değiştirme açık bir eylemdir ve tek adımda geri alınır. Hata ve iptal projeye kısmi sonuç yazmaz.

Small seçimi Intel için boyut/bellek/doğruluk dengesi kararıdır; her Türkçe kayıt için en iyi doğruluğu verdiği iddia edilmez. Medium daha yavaş olabilir. Gerçek Türkçe kullanıcı videolarında WER/CER ve Intel işlem süresi henüz ölçülmemiştir. CI'da gerçek motorla İngilizce ses ve sistemde varsa sentetik Türkçe ses entegrasyon testleri çalışır; bunlar insan konuşması doğruluk karşılaştırması değildir.

Henüz olmayanlar: VAD, kelime vurgusu, güven skoru arayüzü, altyazıyı sonraki klip sıralamasıyla birlikte taşıma ve kesintili indirmeye kaldığı yerden devam. Bozuk model arayüzden kaldırılıp yeniden indirilebilir. Beş dakikalık parça sınırlarında konuşma bağlamı kesilebilir.

## Apple Dikte ile API arasındaki fark

Kullanıcının paylaştığı [Apple Dikte kılavuzu](https://support.apple.com/en-gb/guide/mac-help/mh40584/mac), konuşarak bir metin alanına yazmayı anlatır. Apple'ın [özellik kullanılabilirliği listesinde](https://www.apple.com/macos/feature-availability/) Türkçe Dikte vardır. Bu, dosya içe aktarma, kelime zamanları veya SRT üretme garantisi değildir.

| Yol | Sistem şartı | Gonavi açısından anlamı |
| --- | --- | --- |
| Klavye Diktesi | macOS özelliği; dil/cihaz koşulları değişir | Kullanıcı metin yazabilir; video dosyası için zaman kodlu toplu altyazı hattının yerine geçmez. |
| SFSpeechRecognizer + SFSpeechURLRecognitionRequest | macOS 10.15+ | Kayıtlı ses dosyası tanınabilir. Türkçe ve yerel çalışma cihazda sorgulanır; bazı diller ağ ister. Apple eski API için süre ve kota sınırları belgeler. |
| SpeechAnalyzer + SpeechTranscriber | macOS 26+ | Uzun kayıtlar için yeni yerel API; Sonoma'da yok. Donanım ve Türkçe desteği runtime sorgulanır. |
| SpeechAnalyzer + DictationTranscriber | macOS 26+ | Sistem diktesinin yerel modellerini kullanan alternatif modül. Yalnızca ağ üzerinden desteklenen dilleri desteklemez. |

Apple'ın bu API belgelerinde sabit, kapsamlı bir Türkçe destek tablosu yoktur. Klavye Dikte listesinden SpeechTranscriber/DictationTranscriber desteği çıkarılmayacak. İncelenen belgelerden Intel tamamen desteklenmiyor sonucu da çıkarılmadı; donanım için isAvailable/supportedLocales kontrolü esas alınır.

## Entegrasyon sırası

1. TranscriptProvider ortak arayüzü: kaynak medya kimliği, kaynak zaman aralığı, locale, iptal ve ilerleme.
2. Sesten metne sonuç modeli: metin, kelime/segment başlangıç-bitiş zamanları, varsa güven skoru ve kullanılan motor/model sürümü.
3. Ses çıkarma: konuşma kaynağından, müzik miksajından önce. Uzun dosya için sınırlı bellek, geçici dosya temizliği ve kesintide güvenli iptal.
4. Altyazı bölme: noktalama/duraklama, okunabilir satır uzunluğu ve süre sınırları. Kullanıcının düzelttiği metni koru.
5. Kaynak-zaman → timeline-zaman eşlemesi: trim, split ve yeniden sıralama sonrası kayma olmamalı. 0.2'nin timeline'a bağlı manuel altyazı modeli bu aşamada genişletilir.
6. Türkçe fixture'lar ve gerçek Intel Mac testi: özel isimler, düşük ses, arka plan müziği, 10+ dakikalık kayıt, model eksikliği ve iptal.

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
