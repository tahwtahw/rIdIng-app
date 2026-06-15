import 'package:http/http.dart' as http;

const _timeout = Duration(seconds: 15);

// 每次請求用獨立 Client 並在完成後關閉，避免 Android HTTP/2 keepalive 引發的
// "Software caused connection abort" 錯誤
class ApiClient {
  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final client = http.Client();
    try {
      return await client.get(url, headers: headers).timeout(_timeout);
    } finally {
      client.close();
    }
  }

  static Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body}) async {
    final client = http.Client();
    try {
      return await client.post(url, headers: headers, body: body).timeout(_timeout);
    } finally {
      client.close();
    }
  }

  static Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body}) async {
    final client = http.Client();
    try {
      return await client.put(url, headers: headers, body: body).timeout(_timeout);
    } finally {
      client.close();
    }
  }

  static Future<http.Response> delete(Uri url, {Map<String, String>? headers}) async {
    final client = http.Client();
    try {
      return await client.delete(url, headers: headers).timeout(_timeout);
    } finally {
      client.close();
    }
  }

  static Future<http.Response> patch(Uri url, {Map<String, String>? headers, Object? body}) async {
    final client = http.Client();
    try {
      return await client.patch(url, headers: headers, body: body).timeout(_timeout);
    } finally {
      client.close();
    }
  }
}
