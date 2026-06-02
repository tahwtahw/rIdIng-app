class Config {
  // ── 填入你的 Render 後端網址 ────────────────────────────────
  static const String _prodUrl = 'https://riding-backend.onrender.com/api';

  // ── 本機開發用（同 WiFi 測試）──────────────────────────────
  static const String serverIp   = '192.168.1.106';
  static const int    serverPort = 3000;
  static const String _devUrl    = 'http://$serverIp:$serverPort/api';

  // true = 用雲端後端，false = 用本機
  static const bool useCloud = true;

  static String get baseUrl => useCloud ? _prodUrl : _devUrl;
}
