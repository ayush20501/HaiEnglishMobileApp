import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haienglish/models/course.dart';
import 'package:haienglish/models/user.dart';

class ApiService {
  static const String defaultBaseUrl = 'https://haienglish.pythonanywhere.com';
  static String _currentBaseUrl = defaultBaseUrl;

  static String get baseUrl => _currentBaseUrl;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    var stored = prefs.getString('backend_url') ?? defaultBaseUrl;
    if (stored.startsWith('https://192.168.') || stored.startsWith('https://127.0.0.1') || stored.startsWith('https://localhost')) {
      stored = stored.replaceAll('https://', 'http://');
      await prefs.setString('backend_url', stored);
    }
    _currentBaseUrl = stored;
  }

  static Future<void> updateBaseUrl(String newUrl) async {
    var cleanedUrl = newUrl.trim();
    if (cleanedUrl.endsWith('/')) {
      cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
    }
    if (!cleanedUrl.startsWith('http://') && !cleanedUrl.startsWith('https://')) {
      final parts = cleanedUrl.split(':');
      final host = parts[0];
      final isIp = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
      if (isIp) {
        if (parts.length > 1) {
          cleanedUrl = 'http://$cleanedUrl';
        } else {
          cleanedUrl = 'http://$cleanedUrl:5000';
        }
      } else {
        cleanedUrl = 'https://$cleanedUrl';
      }
    }
    _currentBaseUrl = cleanedUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', cleanedUrl);
  }

  static String _getApiUrl() {
    return '$_currentBaseUrl/api';
  }

  static Future<String?> getAppLogo() async {
    try {
      final response = await http.get(Uri.parse('${_getApiUrl()}/settings')).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['app_logo'] as String?;
      }
    } catch (_) {}
    return null;
  }

  static Future<User> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('${_getApiUrl()}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return User.fromJson(data['user']);
    } else {
      final data = json.decode(response.body);
      throw Exception(data['error'] ?? 'Invalid credentials');
    }
  }

  static Future<void> register(String email, String password, String name) async {
    final response = await http.post(
      Uri.parse('${_getApiUrl()}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password, 'name': name}),
    );
    if (response.statusCode != 201) {
      final data = json.decode(response.body);
      throw Exception(data['error'] ?? 'Registration failed');
    }
  }

  static Future<void> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('${_getApiUrl()}/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );
    if (response.statusCode != 200) {
      final data = json.decode(response.body);
      throw Exception(data['error'] ?? 'Failed to send OTP');
    }
  }

  static Future<void> resetPassword(String email, String otp, String newPassword) async {
    final response = await http.post(
      Uri.parse('${_getApiUrl()}/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'otp': otp, 'new_password': newPassword}),
    );
    if (response.statusCode != 200) {
      final data = json.decode(response.body);
      throw Exception(data['error'] ?? 'Failed to reset password');
    }
  }

  static Future<List<Course>> getCourses(int userId) async {
    final response = await http.get(Uri.parse('${_getApiUrl()}/courses?user_id=$userId'));
    if (response.statusCode == 200) {
      final List list = json.decode(response.body);
      return list.map((item) => Course.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load courses');
    }
  }

  static Future<Course> getCourseDetail(int courseId, int userId) async {
    final response = await http.get(Uri.parse('${_getApiUrl()}/courses/$courseId?user_id=$userId'));
    if (response.statusCode == 200) {
      return Course.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load course details');
    }
  }

  static Future<Map<String, dynamic>> getCourseProgress(int courseId, int userId) async {
    final response = await http.get(Uri.parse('${_getApiUrl()}/courses/$courseId/progress?user_id=$userId'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load progress');
    }
  }

  static Future<void> enrollDirect(int courseId, int userId) async {
    final response = await http.post(
      Uri.parse('${_getApiUrl()}/courses/$courseId/enroll'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to enroll');
    }
  }

  static Future<String> createPaymentInvoice(int courseId, int userId) async {
    final response = await http.post(
      Uri.parse('${_getApiUrl()}/payment/create-invoice'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId, 'course_id': courseId}),
    );
    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['invoice_url'] != null) {
      return data['invoice_url'] as String;
    } else {
      throw Exception(data['error'] ?? 'Failed to create payment invoice');
    }
  }

  static Future<List<int>> submitPdfRead(int courseId, int userId, int chapterNumber) async {
    final response = await http.post(
      Uri.parse('${_getApiUrl()}/courses/$courseId/progress/pdf'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId, 'chapter_number': chapterNumber}),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<int>.from(data['pdf_completed']);
    } else {
      throw Exception('Failed to update PDF progress');
    }
  }

  static Future<Map<String, int>> submitQuizScore(int courseId, int userId, int chapterNumber, int score) async {
    final response = await http.post(
      Uri.parse('${_getApiUrl()}/courses/$courseId/progress/quiz'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId, 'chapter_number': chapterNumber, 'score': score}),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      Map<String, int> scores = {};
      (data['quiz_score'] as Map).forEach((k, v) {
        scores[k.toString()] = v as int;
      });
      return scores;
    } else {
      throw Exception('Failed to update quiz progress');
    }
  }

  static Future<void> submitEssayProgress(int courseId, int userId, Map<int, String> answers, Map<int, bool> submitted) async {
    Map<String, String> answersStrKeys = {};
    answers.forEach((k, v) {
      answersStrKeys[k.toString()] = v;
    });

    Map<String, bool> submittedStrKeys = {};
    submitted.forEach((k, v) {
      submittedStrKeys[k.toString()] = v;
    });

    final essayContentStr = json.encode({
      'answers': answersStrKeys,
      'submitted': submittedStrKeys,
    });

    final response = await http.post(
      Uri.parse('${_getApiUrl()}/courses/$courseId/progress/essay'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId, 'essay_content': essayContentStr}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to submit essay response');
    }
  }

  static Future<Map<String, dynamic>> getCertificate(int courseId, int userId) async {
    final response = await http.get(Uri.parse('${_getApiUrl()}/courses/$courseId/certificate?user_id=$userId'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      final data = json.decode(response.body);
      throw Exception(data['error'] ?? 'Please complete all chapters first.');
    }
  }
}
