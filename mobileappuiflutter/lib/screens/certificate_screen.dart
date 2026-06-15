import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:haienglish/services/api_service.dart';
import 'package:haienglish/models/course.dart';
import 'package:haienglish/models/user.dart';

class CertificateScreen extends StatefulWidget {
  final Course course;
  final User user;
  final VoidCallback onBack;

  const CertificateScreen({
    super.key,
    required this.course,
    required this.user,
    required this.onBack,
  });

  @override
  State<CertificateScreen> createState() => _CertificateScreenState();
}

class _CertificateScreenState extends State<CertificateScreen> {
  Map<String, dynamic>? _certificateData;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchCertificate();
  }

  Future<void> _fetchCertificate() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final data = await ApiService.getCertificate(widget.course.id, widget.user.id);
      setState(() {
        _certificateData = data;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator(color: Color(0xFF004AAD)));
    } else if (_errorMessage.isNotEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 15, color: const Color(0xFF374151)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchCertificate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004AAD),
                  foregroundColor: Colors.white,
                ),
                child: Text('Retry', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        ),
      );
    } else if (_certificateData == null) {
      body = const Center(child: Text('No certificate data available.'));
    } else {
      final downloadUrl = _certificateData!['download_url'] as String? ?? '';
      if (downloadUrl.isNotEmpty) {
        final embedUrl = 'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(downloadUrl)}';
        body = WebViewWidget(
          controller: WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..loadRequest(Uri.parse(embedUrl)),
        );
      } else {
        body = _buildLocalCertificateView(_certificateData!);
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF004AAD)),
          onPressed: widget.onBack,
        ),
        title: Text(
          'Certificate',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF111827),
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE5E7EB), height: 1),
        ),
      ),
      body: body,
    );
  }

  Widget _buildLocalCertificateView(Map<String, dynamic> data) {
    final userName = data['user_name'] as String? ?? '';
    final courseTitle = data['course_title'] as String? ?? '';
    final issuedAt = data['issued_at'] as String? ?? '';
    final uuid = data['certificate_uuid'] as String? ?? '';

    String formattedDate = '';
    try {
      final date = DateTime.parse(issuedAt);
      formattedDate = '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      formattedDate = issuedAt.split(' ')[0];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD97706), width: 4),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(6),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1),
          ),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'HAI ENGLISH PLATFORM',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFB45309),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'CERTIFICATE OF COMPLETION',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF78350F),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 150,
                height: 1,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(height: 14),
              Text(
                'This is proudly presented to',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFF78350F),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                userName,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF451A03),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'for outstanding performance and successful completion of',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFF78350F),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                courseTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF78350F),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 150,
                height: 1,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(height: 14),
              Text(
                'Issued On: $formattedDate',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: const Color(0xFF78350F),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Verification ID: $uuid',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: const Color(0xFF78350F),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
