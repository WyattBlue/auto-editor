/**
 * Auto-Editor GUI
 * Web-based interface for auto-editor video processing
 */

// ============================================================
// State Management
// ============================================================
const state = {
  currentFile: null,
  currentLang: 'tr',
  currentTheme: 'light',
  isProcessing: false,
  results: {
    transcript: '',
    topics: null,
    summary: null
  },
  video: {
    duration: 0,
    currentTime: 0,
    isPlaying: false,
    volume: 100
  }
};

// ============================================================
// Translations
// ============================================================
const translations = {
  tr: {
    'app.title': 'Auto-Editor',
    'app.subtitle': 'Otomatik Video Düzenleyici',
    'file.select': 'Dosya Seç',
    'file.dragdrop': 'Dosyayı buraya sürükleyin veya tıklayın',
    'file.supported': 'Desteklenen formatlar: MP4, MOV, AVI, MKV, MP3, WAV',
    'edit.method': 'Düzenleme Metodu',
    'edit.threshold': 'Eşik Değeri',
    'edit.margin': 'Marginal (Saniye)',
    'transcribe.title': 'Transkripsiyon',
    'transcribe.provider': 'Sağlayıcı',
    'transcribe.language': 'Dil',
    'transcribe.api_key': 'API Anahtarı',
    'transcribe.transcript': 'Transkript Al',
    'transcribe.detect_topics': 'Konu Tespit Et',
    'transcribe.summarize': 'Özet Çıkar',
    'export.title': 'Dışa Aktarma',
    'export.format': 'Format',
    'export.save': 'Kaydet',
    'action.process': 'İşle',
    'action.cancel': 'İptal',
    'status.ready': 'Hazır',
    'status.processing': 'İşleniyor...',
    'status.done': 'Tamamlandı',
    'preview.play': '▶️',
    'preview.pause': '⏸️',
    'preview.stop': '⏹️',
    'results.transcript': 'Transkript',
    'results.topics': 'Konular',
    'results.summary': 'Özet',
    'results.no_results': 'Henüz sonuç yok',
    'results.select_file': 'Dosya seçin ve işleme başlatın',
    'error.no_file': 'Lütfen bir dosya seçin',
    'error.api_key': 'API anahtarı gerekli',
    'error.processing': 'İşleme sırasında hata oluştu',
    'processing.transcribing': 'Transkripsiyon yapılıyor...',
    'processing.detecting_topics': 'Konular tespit ediliyor...',
    'processing.summarizing': 'Özet çıkarılıyor...',
    'processing.please_wait': 'Lütfen bekleyin'
  },
  en: {
    'app.title': 'Auto-Editor',
    'app.subtitle': 'Automatic Video Editor',
    'file.select': 'Select File',
    'file.dragdrop': 'Drag and drop file here or click',
    'file.supported': 'Supported formats: MP4, MOV, AVI, MKV, MP3, WAV',
    'edit.method': 'Edit Method',
    'edit.threshold': 'Threshold',
    'edit.margin': 'Margin (Seconds)',
    'transcribe.title': 'Transcription',
    'transcribe.provider': 'Provider',
    'transcribe.language': 'Language',
    'transcribe.api_key': 'API Key',
    'transcribe.transcript': 'Get Transcript',
    'transcribe.detect_topics': 'Detect Topics',
    'transcribe.summarize': 'Summarize',
    'export.title': 'Export',
    'export.format': 'Format',
    'export.save': 'Save',
    'action.process': 'Process',
    'action.cancel': 'Cancel',
    'status.ready': 'Ready',
    'status.processing': 'Processing...',
    'status.done': 'Done',
    'preview.play': '▶️',
    'preview.pause': '⏸️',
    'preview.stop': '⏹️',
    'results.transcript': 'Transcript',
    'results.topics': 'Topics',
    'results.summary': 'Summary',
    'results.no_results': 'No results yet',
    'results.select_file': 'Select a file and start processing',
    'error.no_file': 'Please select a file',
    'error.api_key': 'API key is required',
    'error.processing': 'Error occurred during processing',
    'processing.transcribing': 'Transcribing...',
    'processing.detecting_topics': 'Detecting topics...',
    'processing.summarizing': 'Summarizing...',
    'processing.please_wait': 'Please wait'
  }
};

// ============================================================
// DOM Elements
// ============================================================
const elements = {
  // File
  fileDropZone: document.getElementById('file-drop-zone'),
  fileInput: document.getElementById('file-input'),
  fileName: document.getElementById('file-name'),
  
  // Video
  videoPlayer: document.getElementById('video-player'),
  videoPlaceholder: document.getElementById('video-placeholder'),
  playBtn: document.getElementById('play-btn'),
  pauseBtn: document.getElementById('pause-btn'),
  stopBtn: document.getElementById('stop-btn'),
  progressBar: document.getElementById('progress-bar'),
  progressFill: document.getElementById('progress-fill'),
  timeDisplay: document.getElementById('time-display'),
  muteBtn: document.getElementById('mute-btn'),
  volumeSlider: document.getElementById('volume-slider'),
  fullscreenBtn: document.getElementById('fullscreen-btn'),
  
  // Waveform
  waveformCanvas: document.getElementById('waveform-canvas'),
  
  // Settings
  editMethod: document.getElementById('edit-method'),
  threshold: document.getElementById('threshold'),
  margin: document.getElementById('margin'),
  provider: document.getElementById('provider'),
  language: document.getElementById('language'),
  apiKey: document.getElementById('api-key'),
  transcribeFormat: document.getElementById('transcribe-format'),
  
  // Actions
  transcribeBtn: document.getElementById('transcribe-btn'),
  detectTopicsBtn: document.getElementById('detect-topics-btn'),
  summarizeBtn: document.getElementById('summarize-btn'),
  processBtn: document.getElementById('process-btn'),
  
  // Export
  exportFormat: document.getElementById('export-format'),
  saveBtn: document.getElementById('save-btn'),
  
  // Results
  resultsTabs: document.querySelectorAll('.results-tab'),
  resultsContent: document.getElementById('results-content'),
  
  // Status
  statusDot: document.getElementById('status-dot'),
  statusText: document.getElementById('status-text'),
  
  // Theme & Language
  themeToggle: document.getElementById('theme-toggle'),
  languageBtns: document.querySelectorAll('.language-btn'),
  
  // Processing
  processingOverlay: document.getElementById('processing-overlay'),
  processingText: document.getElementById('processing-text'),
  processingProgress: document.getElementById('processing-progress')
};

// ============================================================
// Translation Function
// ============================================================
function t(key) {
  return translations[state.currentLang][key] || key;
}

function updateTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    const translation = t(key);
    if (el.tagName === 'INPUT' && el.type !== 'button') {
      el.placeholder = translation;
    } else {
      el.textContent = translation;
    }
  });
  
  document.documentElement.lang = state.currentLang;
  document.getElementById('app-subtitle').textContent = t('app.subtitle');
}

// ============================================================
// Theme Management
// ============================================================
function setTheme(theme) {
  state.currentTheme = theme;
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('auto-editor-theme', theme);
  elements.themeToggle.textContent = theme === 'dark' ? '☀️' : '🌙';
}

function toggleTheme() {
  setTheme(state.currentTheme === 'light' ? 'dark' : 'light');
}

// ============================================================
// Language Management
// ============================================================
function setLanguage(lang) {
  state.currentLang = lang;
  localStorage.setItem('auto-editor-lang', lang);
  
  elements.languageBtns.forEach(btn => {
    btn.classList.toggle('active', btn.dataset.lang === lang);
  });
  
  updateTranslations();
}

// ============================================================
// File Handling
// ============================================================
function handleFileSelect(file) {
  if (!file) return;
  
  state.currentFile = file;
  elements.fileName.textContent = file.name;
  
  // Create video URL
  const url = URL.createObjectURL(file);
  elements.videoPlayer.src = url;
  elements.videoPlaceholder.style.display = 'none';
  elements.videoPlayer.style.display = 'block';
  
  // Generate waveform
  generateWaveform(file);
  
  updateStatus('ready');
}

function generateWaveform(file) {
  const canvas = elements.waveformCanvas;
  const ctx = canvas.getContext('2d');
  
  // Set canvas size
  canvas.width = canvas.offsetWidth * window.devicePixelRatio;
  canvas.height = canvas.offsetHeight * window.devicePixelRatio;
  ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
  
  // Clear canvas
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  
  // Draw placeholder waveform
  const bars = 100;
  const barWidth = canvas.offsetWidth / bars;
  const centerY = canvas.offsetHeight / 2;
  
  ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue('--primary-color');
  
  for (let i = 0; i < bars; i++) {
    const height = Math.random() * canvas.offsetHeight * 0.8;
    const x = i * barWidth;
    const y = centerY - height / 2;
    
    ctx.fillRect(x + 1, y, barWidth - 2, height);
  }
}

// ============================================================
// Video Controls
// ============================================================
function playVideo() {
  elements.videoPlayer.play();
  state.video.isPlaying = true;
}

function pauseVideo() {
  elements.videoPlayer.pause();
  state.video.isPlaying = false;
}

function stopVideo() {
  elements.videoPlayer.pause();
  elements.videoPlayer.currentTime = 0;
  state.video.isPlaying = false;
  updateProgressBar(0);
}

function toggleMute() {
  elements.videoPlayer.muted = !elements.videoPlayer.muted;
  elements.muteBtn.textContent = elements.videoPlayer.muted ? '🔇' : '🔊';
}

function setVolume(value) {
  elements.videoPlayer.volume = value / 100;
  state.video.volume = value;
}

function toggleFullscreen() {
  const container = elements.videoPlayer.parentElement;
  if (document.fullscreenElement) {
    document.exitFullscreen();
  } else {
    container.requestFullscreen();
  }
}

function updateProgressBar(percent) {
  elements.progressFill.style.width = `${percent}%`;
}

function formatTime(seconds) {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

// ============================================================
// Processing Functions
// ============================================================
function showProcessing(message, progress = '') {
  state.isProcessing = true;
  elements.processingOverlay.classList.add('active');
  elements.processingText.textContent = message;
  elements.processingProgress.textContent = progress;
  elements.statusDot.classList.add('processing');
  updateStatus('processing');
}

function hideProcessing() {
  state.isProcessing = false;
  elements.processingOverlay.classList.remove('active');
  elements.statusDot.classList.remove('processing');
  updateStatus('done');
}

function updateStatus(status) {
  elements.statusText.textContent = t(`status.${status}`);
}

function updateResults(type, content) {
  state.results[type] = content;
  
  // Update active tab content
  const activeTab = document.querySelector('.results-tab.active');
  if (activeTab) {
    showResults(activeTab.dataset.tab);
  }
}

function showResults(tab) {
  let content = '';
  
  switch (tab) {
    case 'transcript':
      content = state.results.transcript || createEmptyState('results.no_results', 'results.select_file');
      break;
    case 'topics':
      content = state.results.topics ? formatTopics(state.results.topics) : createEmptyState('results.no_results', 'results.select_file');
      break;
    case 'summary':
      content = state.results.summary ? formatSummary(state.results.summary) : createEmptyState('results.no_results', 'results.select_file');
      break;
  }
  
  elements.resultsContent.innerHTML = content;
}

function createEmptyState(titleKey, hintKey) {
  return `
    <div style="text-align: center; padding: 40px; color: var(--text-secondary);">
      <div style="font-size: 2rem; margin-bottom: 16px;">📝</div>
      <div>${t(titleKey)}</div>
      <div style="font-size: 0.75rem; margin-top: 8px;">${t(hintKey)}</div>
    </div>
  `;
}

function formatTopics(topics) {
  if (!topics.topics || topics.topics.length === 0) {
    return createEmptyState('results.no_results', 'results.select_file');
  }
  
  return topics.topics.map((topic, index) => `
    <div class="topic-card">
      <div class="topic-time">${topic.start} → ${topic.end}</div>
      <div class="topic-title">${topic.title}</div>
    </div>
  `).join('');
}

function formatSummary(summary) {
  if (!summary) return createEmptyState('results.no_results', 'results.select_file');
  
  let html = '';
  
  if (summary.summary) {
    html += `<div style="margin-bottom: 16px;"><strong>Özet:</strong><br>${summary.summary}</div>`;
  }
  
  if (summary.key_points && summary.key_points.length > 0) {
    html += `<div style="margin-bottom: 16px;"><strong>Ana Noktalar:</strong><ul>${summary.key_points.map(p => `<li>${p}</li>`).join('')}</ul></div>`;
  }
  
  if (summary.speaker_intent) {
    html += `<div style="margin-bottom: 16px;"><strong>Konuşmacının Mesajı:</strong><br>${summary.speaker_intent}</div>`;
  }
  
  if (summary.conclusion) {
    html += `<div><strong>Sonuç:</strong><br>${summary.conclusion}</div>`;
  }
  
  return html;
}

// ============================================================
// API Functions (Mock - Will be replaced with WASM calls)
// ============================================================
async function transcribeAudio() {
  if (!state.currentFile) {
    alert(t('error.no_file'));
    return;
  }
  
  const apiKey = elements.apiKey.value;
  if (!apiKey) {
    alert(t('error.api_key'));
    return;
  }
  
  showProcessing(t('processing.transcribing'), t('processing.please_wait'));
  
  // Mock API call - will be replaced with actual WASM call
  setTimeout(() => {
    const mockTranscript = `Bu bir test transkriptidir. Auto-Editor'ın yeni GUI'sini test ediyoruz.

İlk konu: Giriş ve genel bakış.
İkinci konu: Teknik özellikler.
Üçüncü konu: Kullanım örnekleri.

Sonuç olarak, bu araç otomatik video düzenleme için oldukça kullanışlıdır.`;
    
    updateResults('transcript', mockTranscript);
    hideProcessing();
  }, 2000);
}

async function detectTopics() {
  if (!state.currentFile) {
    alert(t('error.no_file'));
    return;
  }
  
  showProcessing(t('processing.detecting_topics'), t('processing.please_wait'));
  
  // Mock API call
  setTimeout(() => {
    const mockTopics = {
      topics: [
        { start: '00:00:00', end: '00:05:00', title: 'Giriş ve Genel Bakış' },
        { start: '00:05:00', end: '00:15:00', title: 'Teknik Özellikler' },
        { start: '00:15:00', end: '00:23:00', title: 'Sonuç ve Değerlendirme' }
      ]
    };
    
    updateResults('topics', mockTopics);
    hideProcessing();
  }, 2000);
}

async function summarizeContent() {
  if (!state.currentFile) {
    alert(t('error.no_file'));
    return;
  }
  
  showProcessing(t('processing.summarizing'), t('processing.please_wait'));
  
  // Mock API call
  setTimeout(() => {
    const mockSummary = {
      summary: 'Bu video, Auto-Editor aracının özelliklerini ve kullanımını anlatmaktadır.',
      key_points: [
        'Auto-Editor otomatik video düzenleme aracıdır',
        'Ses, hareket ve siyah ekran tespiti yapabilir',
        'Groq, OpenAI ve Gemini desteği vardır',
        'Türkçe ve İngilizce dil desteği mevcuttur'
      ],
      speaker_intent: 'İzleyicilere Auto-Editor\'ı tanıtmak ve nasıl kullanılacağını göstermek',
      conclusion: 'Auto-Editor, video düzenleme sürecini önemli ölçüde hızlandırabilir'
    };
    
    updateResults('summary', mockSummary);
    hideProcessing();
  }, 2000);
}

function processVideo() {
  if (!state.currentFile) {
    alert(t('error.no_file'));
    return;
  }
  
  // Run all processing
  transcribeAudio().then(() => {
    detectTopics().then(() => {
      summarizeContent();
    });
  });
}

function saveResults() {
  const format = elements.exportFormat.value;
  let content = '';
  let filename = '';
  let mimeType = 'text/plain';
  
  switch (format) {
    case 'srt':
      content = generateSRT();
      filename = 'output.srt';
      mimeType = 'text/plain';
      break;
    case 'json':
      content = JSON.stringify(state.results, null, 2);
      filename = 'output.json';
      mimeType = 'application/json';
      break;
    case 'txt':
      content = state.results.transcript || '';
      filename = 'output.txt';
      mimeType = 'text/plain';
      break;
    default:
      content = JSON.stringify(state.results, null, 2);
      filename = 'output.json';
      mimeType = 'application/json';
  }
  
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function generateSRT() {
  if (!state.results.topics || !state.results.topics.topics) {
    return '';
  }
  
  return state.results.topics.topics.map((topic, index) => {
    return `${index + 1}\n${topic.start.replace('.', ',')} --> ${topic.end.replace('.', ',')}\n${topic.title}\n`;
  }).join('\n');
}

// ============================================================
// Event Listeners
// ============================================================
function initEventListeners() {
  // File handling
  elements.fileDropZone.addEventListener('click', () => elements.fileInput.click());
  elements.fileInput.addEventListener('change', (e) => handleFileSelect(e.target.files[0]));
  
  // Drag and drop
  elements.fileDropZone.addEventListener('dragover', (e) => {
    e.preventDefault();
    elements.fileDropZone.classList.add('dragover');
  });
  
  elements.fileDropZone.addEventListener('dragleave', () => {
    elements.fileDropZone.classList.remove('dragover');
  });
  
  elements.fileDropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    elements.fileDropZone.classList.remove('dragover');
    handleFileSelect(e.dataTransfer.files[0]);
  });
  
  // Video controls
  elements.playBtn.addEventListener('click', playVideo);
  elements.pauseBtn.addEventListener('click', pauseVideo);
  elements.stopBtn.addEventListener('click', stopVideo);
  elements.muteBtn.addEventListener('click', toggleMute);
  elements.volumeSlider.addEventListener('input', (e) => setVolume(e.target.value));
  elements.fullscreenBtn.addEventListener('click', toggleFullscreen);
  
  // Video progress
  elements.videoPlayer.addEventListener('timeupdate', () => {
    const percent = (elements.videoPlayer.currentTime / elements.videoPlayer.duration) * 100;
    updateProgressBar(percent);
    elements.timeDisplay.textContent = `${formatTime(elements.videoPlayer.currentTime)} / ${formatTime(elements.videoPlayer.duration)}`;
  });
  
  // Progress bar click
  elements.progressBar.addEventListener('click', (e) => {
    const rect = elements.progressBar.getBoundingClientRect();
    const percent = (e.clientX - rect.left) / rect.width;
    elements.videoPlayer.currentTime = percent * elements.videoPlayer.duration;
  });
  
  // Results tabs
  elements.resultsTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      elements.resultsTabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      showResults(tab.dataset.tab);
    });
  });
  
  // Action buttons
  elements.transcribeBtn.addEventListener('click', transcribeAudio);
  elements.detectTopicsBtn.addEventListener('click', detectTopics);
  elements.summarizeBtn.addEventListener('click', summarizeContent);
  elements.processBtn.addEventListener('click', processVideo);
  elements.saveBtn.addEventListener('click', saveResults);
  
  // Theme & Language
  elements.themeToggle.addEventListener('click', toggleTheme);
  elements.languageBtns.forEach(btn => {
    btn.addEventListener('click', () => setLanguage(btn.dataset.lang));
  });
  
  // Window resize
  window.addEventListener('resize', () => {
    if (state.currentFile) {
      generateWaveform(state.currentFile);
    }
  });
}

// ============================================================
// Initialization
// ============================================================
function init() {
  // Load saved preferences
  const savedTheme = localStorage.getItem('auto-editor-theme') || 'light';
  const savedLang = localStorage.getItem('auto-editor-lang') || 'tr';
  
  setTheme(savedTheme);
  setLanguage(savedLang);
  
  // Initialize event listeners
  initEventListeners();
  
  // Show initial results state
  showResults('transcript');
  
  console.log('Auto-Editor GUI initialized');
}

// Start the app
document.addEventListener('DOMContentLoaded', init);
