# Auto-Editor GUI

Web tabanlı grafik arayüz (GUI) desteği. Hem Türkçe hem İngilizce arayüz desteği sunar.

## Özellikler

- **Dosya Seçimi**: Drag & drop veya dialog ile video/ses dosyası seçme
- **Video Önizleme**: HTML5 video player ile doğrudan önizleme
- **Dalga Formu**: Ses dalga formu görselleştirme
- **Düzenleme Paneli**: Ses, hareket ve siyah ekran algılama ayarları
- **Transkript**: Groq, OpenAI, Gemini ile bulut transkripsiyon
- **Konu Tespiti**: Otomatik konu sınırları tespiti
- **Özet Çıkarma**: İçerik özetleme
- **Export**: SRT, JSON, TXT formatlarında kaydetme
- **Dil Desteği**: Türkçe ve İngilizce arayüz
- **Tema Desteği**: Açık ve koyu tema

## Kullanım

### Web Tabanlı

```bash
# GUI'yi başlat
auto-editor --gui

# Tarayıcıda aç
# http://localhost:8080
```

### Doğrudan Erişim

```bash
# web/ dizinindeki dosyaları doğrudan açabilirsiniz
open web/index.html
```

## Kurulum

### Gereksinimler

- Nim 2.0+
- FFmpeg (zaten kurulu olmalı)

### Bağımlılıklar

```bash
nimble install webui
```

### Derleme

```bash
# GUI dahil derle
nim c -d:release src/main.nim

# veya
nimble build
```

## Mimari

```
src/gui/
├── app.nim              # Ana uygulama
├── components/          # UI bileşenleri
├── i18n/                # Dil dosyaları
│   ├── strings_tr.json  # Türkçe
│   └── strings_en.json  # İngilizce
└── styles/
    └── theme.css        # Temastillleri

web/
├── index.html           # Ana HTML
├── app.js               # JavaScript köprüsü
└── styles/
    └── theme.css        # CSS stilleri
```

## Dil Desteği

### Türkçe
- Tam arayüz çevirisi
- Türkçe transkript promptları
- Türkçe konu tespiti

### English
- Full interface translation
- English transcription prompts
- English topic detection

## API Entegrasyonu

### Groq
```javascript
// Hızlı transkripsiyon
await transcribe('groq', 'whisper-large-v3', apiKey, audioFile);
```

### OpenAI
```javascript
// Yüksek kaliteli transkripsiyon
await transcribe('openai', 'whisper-1', apiKey, audioFile);
```

### Gemini
```javascript
// Google Gemini ile transkripsiyon
await transcribe('gemini', 'gemini-1.5-flash', apiKey, audioFile);
```

## Katkıda Bulunma

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Lisans

This project is licensed under the Public Domain - see the [LICENSE](LICENSE) file for details.
