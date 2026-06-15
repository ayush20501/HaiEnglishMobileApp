import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:haienglish/services/api_service.dart';
import 'package:haienglish/models/course.dart';
import 'package:haienglish/models/user.dart';

class DashboardScreen extends StatefulWidget {
  final User user;
  final Function(Course) onEnrollCourse;
  final Function(Course) onViewCertificate;
  final VoidCallback onLogOut;

  const DashboardScreen({
    super.key,
    required this.user,
    required this.onEnrollCourse,
    required this.onViewCertificate,
    required this.onLogOut,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  int _currentTabIndex = 0;
  List<Course> _courses = [];
  bool _isLoading = false;
  String _appLogoUrl = 'https://i.ibb.co/KcpRPJD4/HAI-logo.png';

  bool _showSyllabus = false;
  TabController? _syllabusTabController;
  final Map<String, String> _quizAnswers = {};
  final Map<int, String> _essayAnswers = {};
  final Map<int, bool> _essaySubmittedMap = {};
  int? _lastLeftTab;
  int? _lastLeftChapter;

  @override
  void initState() {
    super.initState();
    _fetchCourses();
    _fetchSettings();
  }

  @override
  void dispose() {
    if (_syllabusTabController != null) {
      _syllabusTabController!.removeListener(_handleSyllabusTabSelection);
      _syllabusTabController!.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchSettings() async {
    final logo = await ApiService.getAppLogo();
    if (logo != null && mounted) {
      setState(() {
        _appLogoUrl = logo;
      });
    }
  }

  Future<void> _fetchCourses() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService.getCourses(widget.user.id);
      setState(() {
        _courses = list;
      });
    } catch (_) {
      _showError('Failed to load courses');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startLearning(Course course) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = widget.user.id;
    final courseId = course.id;

    int initialTab = prefs.getInt('last_left_tab_${userId}_$courseId') ?? -1;
    int? lastChapter = prefs.getInt('last_left_chapter_${userId}_$courseId');

    if (initialTab == -1) {
      final progress = _calculateProgress(course);
      if (progress == 0) {
        initialTab = 0;
      } else if (progress == 100) {
        initialTab = 0;
      } else {
        final totalChapters = course.pdfData.length;
        int firstUncompletedPdf = -1;
        for (int i = 1; i <= totalChapters; i++) {
          if (!course.pdfCompleted.contains(i)) {
            firstUncompletedPdf = i;
            break;
          }
        }
        if (firstUncompletedPdf != -1) {
          initialTab = 0;
          lastChapter = firstUncompletedPdf;
        } else {
          int firstUncompletedQuiz = -1;
          for (int i = 1; i <= totalChapters; i++) {
            if (course.quizScore[i.toString()] == null) {
              firstUncompletedQuiz = i;
              break;
            }
          }
          if (firstUncompletedQuiz != -1) {
            initialTab = 1;
            lastChapter = firstUncompletedQuiz;
          } else if (!course.essaySubmitted) {
            initialTab = 2;
            lastChapter = 1;
          } else {
            initialTab = 0;
          }
        }
      }
    }

    setState(() {
      _showSyllabus = true;
      _lastLeftTab = initialTab;
      _lastLeftChapter = lastChapter;
      _syllabusTabController = TabController(
        length: 3,
        vsync: this,
        initialIndex: initialTab,
      );
      _syllabusTabController!.addListener(_handleSyllabusTabSelection);
    });
    _loadSyllabusProgress(course);
  }

  void _exitLearning() {
    setState(() {
      _showSyllabus = false;
      if (_syllabusTabController != null) {
        _syllabusTabController!.removeListener(_handleSyllabusTabSelection);
        _syllabusTabController!.dispose();
        _syllabusTabController = null;
      }
    });
    _fetchCourses();
  }

  void _handleSyllabusTabSelection() {
    if (_syllabusTabController == null || _courses.isEmpty) return;
    final course = _courses.first;
    if (_syllabusTabController!.index == 1) {
      final allPdfsDone = course.pdfCompleted.length >= course.pdfData.length;
      if (!allPdfsDone) {
        _syllabusTabController!.index = 0;
        _showLockedAlert('Locked', 'Please read all chapter PDFs first to unlock quizzes.');
        return;
      }
    } else if (_syllabusTabController!.index == 2) {
      final allQuizzesDone = course.quizScore.length >= course.pdfData.length;
      if (!allQuizzesDone) {
        _syllabusTabController!.index = course.pdfCompleted.length >= course.pdfData.length ? 1 : 0;
        _showLockedAlert('Locked', 'Please complete all chapter quizzes first to unlock the course essay.');
        return;
      }
    }
    _saveLastLeftTab(_syllabusTabController!.index, course.id);
  }

  Future<void> _saveLastLeftTab(int tabIndex, int courseId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_left_tab_${widget.user.id}_$courseId', tabIndex);
    setState(() {
      _lastLeftTab = tabIndex;
    });
  }

  Future<void> _loadSyllabusProgress(Course course) async {
    setState(() => _isLoading = true);
    try {
      final updatedCourse = await ApiService.getCourseDetail(course.id, widget.user.id);
      final progressData = await ApiService.getCourseProgress(course.id, widget.user.id);
      
      setState(() {
        final index = _courses.indexWhere((c) => c.id == course.id);
        if (index != -1) {
          _courses[index] = updatedCourse;
        }
        _essayAnswers.clear();
        _essaySubmittedMap.clear();

        final essayContentStr = progressData['essay_content'] as String? ?? '';
        if (essayContentStr.isNotEmpty) {
          try {
            final Map<String, dynamic> parsed = jsonDecode(essayContentStr);
            final answersObj = parsed['answers'] as Map<String, dynamic>? ?? {};
            answersObj.forEach((k, v) {
              _essayAnswers[int.parse(k)] = v.toString();
            });
            final submittedObj = parsed['submitted'] as Map<String, dynamic>? ?? {};
            submittedObj.forEach((k, v) {
              _essaySubmittedMap[int.parse(k)] = v == true;
            });
          } catch (_) {}
        }
      });
    } catch (_) {}
    finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePdfClick(Chapter chapter, Course course) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_left_tab_${widget.user.id}_${course.id}', 0);
    await prefs.setInt('last_left_chapter_${widget.user.id}_${course.id}', chapter.chapterNumber);
    setState(() {
      _lastLeftTab = 0;
      _lastLeftChapter = chapter.chapterNumber;
    });

    if (chapter.pdfUrl.isEmpty) {
      _showLockedAlert('Error', 'PDF URL not found');
      return;
    }

    final embedUrl = 'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(chapter.pdfUrl)}';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close, color: Color(0xFF4B5563)),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              chapter.title,
              style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF111827), fontWeight: FontWeight.w600),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
          ),
          body: WebViewWidget(
            controller: WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..loadRequest(Uri.parse(embedUrl)),
          ),
        ),
      ),
    );

    if (!mounted) return;

    if (!course.pdfCompleted.contains(chapter.chapterNumber)) {
      try {
        final updatedCompletedList = await ApiService.submitPdfRead(course.id, widget.user.id, chapter.chapterNumber);
        setState(() {
          final index = _courses.indexWhere((c) => c.id == course.id);
          if (index != -1) {
            _courses[index] = Course(
              id: course.id,
              title: course.title,
              description: course.description,
              price: course.price,
              coursePosterUrl: course.coursePosterUrl,
              pdfData: course.pdfData,
              quizData: course.quizData,
              essayPrompt: course.essayPrompt,
              isEnrolled: course.isEnrolled,
              pdfCompleted: updatedCompletedList,
              quizScore: course.quizScore,
              essaySubmitted: course.essaySubmitted,
            );
          }
        });

        if (updatedCompletedList.length >= course.pdfData.length) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Section Unlocked', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                content: Text('Congratulations! You have completed all PDF chapters. The Quizzes section is now unlocked.', style: GoogleFonts.poppins()),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (_syllabusTabController != null) {
                        _syllabusTabController!.animateTo(1);
                      }
                    },
                    child: Text('Go to Quizzes', style: GoogleFonts.poppins(color: const Color(0xFF004AAD), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _handleSubmitAllQuizzes(Course course) async {
    int totalQuestions = 0;
    int totalCorrect = 0;

    for (final qc in course.quizData) {
      int score = 0;
      for (int i = 0; i < qc.quizzes.length; i++) {
        totalQuestions++;
        final q = qc.quizzes[i];
        final key = '${qc.chapterNumber}_$i';
        if (_quizAnswers[key] == q.answer) {
          score++;
          totalCorrect++;
        }
      }
      try {
        await ApiService.submitQuizScore(course.id, widget.user.id, qc.chapterNumber, score);
      } catch (_) {}
    }

    await _loadSyllabusProgress(course);

    if (!mounted) return;

    final updatedCourse = _courses.firstWhere((c) => c.id == course.id, orElse: () => course);
    final allQuizzesDone = updatedCourse.quizScore.length >= updatedCourse.pdfData.length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quiz Submitted', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          allQuizzesDone
              ? 'You scored $totalCorrect out of $totalQuestions across all chapters. The Final Essay section is now unlocked!'
              : 'You scored $totalCorrect out of $totalQuestions across all chapters.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (allQuizzesDone && _syllabusTabController != null) {
                _syllabusTabController!.animateTo(2);
              }
            },
            child: Text(
              allQuizzesDone ? 'Go to Essay' : 'OK',
              style: GoogleFonts.poppins(color: const Color(0xFF004AAD), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmitEssay(int index, Course course) async {
    final response = _essayAnswers[index] ?? '';
    if (response.trim().isEmpty) {
      _showLockedAlert('Error', 'Please write your response first');
      return;
    }

    setState(() => _isLoading = true);
    try {
      _essaySubmittedMap[index] = true;
      await ApiService.submitEssayProgress(course.id, widget.user.id, _essayAnswers, _essaySubmittedMap);
      _showLockedAlert('Saved', 'Your response has been saved.');
      await _loadSyllabusProgress(course);
    } catch (_) {
      setState(() => _essaySubmittedMap[index] = false);
      _showLockedAlert('Error', 'Failed to submit response');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showLockedAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(message, style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.poppins(color: const Color(0xFF004AAD), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  int _calculateProgress(Course course) {
    final totalChapters = course.pdfData.length;
    if (totalChapters == 0) return 0;

    double completedCount = 0.0;
    for (int i = 1; i <= totalChapters; i++) {
      if (course.pdfCompleted.contains(i)) {
        completedCount += 0.5;
      }
      if (course.quizScore[i.toString()] != null) {
        completedCount += 0.5;
      }
    }
    if (course.essaySubmitted) {
      completedCount += 1.0;
    }

    final totalItems = totalChapters + 1;
    final pct = (completedCount / totalItems) * 100;
    return pct.clamp(0.0, 100.0).round();
  }

  @override
  Widget build(BuildContext context) {
    final course = _courses.isNotEmpty ? _courses.first : null;
    final allPdfsDone = course != null && course.pdfCompleted.length >= course.pdfData.length;
    final allQuizzesDone = course != null && course.quizScore.length >= course.pdfData.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: (_showSyllabus && _currentTabIndex == 0 && course != null)
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF004AAD)),
                onPressed: _exitLearning,
              ),
              title: Text(
                'Course Syllabus',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF111827),
                  fontSize: 16,
                ),
              ),
              backgroundColor: Colors.white,
              elevation: 0,
              bottom: TabBar(
                controller: _syllabusTabController,
                labelColor: const Color(0xFF004AAD),
                unselectedLabelColor: const Color(0xFF6B7280),
                indicatorColor: const Color(0xFF004AAD),
                labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: [
                  const Tab(text: 'PDFs'),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!allPdfsDone) const Icon(Icons.lock, size: 12, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 4),
                        const Text('Quizzes'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!allQuizzesDone) const Icon(Icons.lock, size: 12, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 4),
                        const Text('Essay'),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : AppBar(
              title: Row(
                children: [
                  Image.network(
                    _appLogoUrl,
                    height: 28,
                    width: 28,
                    errorBuilder: (context, error, stackTrace) => Image.asset(
                      'assets/images/logo.png',
                      height: 28,
                      width: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'HaiEnglish',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF004AAD),
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.white,
              elevation: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(color: const Color(0xFFE5E7EB), height: 1),
              ),
            ),
      body: _isLoading && _courses.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF004AAD)))
          : RefreshIndicator(
              onRefresh: _fetchCourses,
              color: const Color(0xFF004AAD),
              child: _buildTabContent(),
            ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) => setState(() => _currentTabIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF004AAD),
          unselectedItemColor: const Color(0xFF6B7280),
          selectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 11),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.verified), label: 'Certificate'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_currentTabIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildCertificatesTab();
      case 2:
        return _buildProfileTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHomeTab() {
    if (_courses.isEmpty) {
      return const Center(child: Text('No courses available.'));
    }
    final course = _courses.first;

    if (_showSyllabus) {
      return _buildSyllabusView(course);
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Image.network(
            course.coursePosterUrl,
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
            alignment: const Alignment(0.0, -0.8),
            errorBuilder: (context, error, stackTrace) => Container(
              height: 220,
              color: const Color(0xFFF3F4F6),
              child: const Icon(Icons.book, size: 64, color: Color(0xFF9CA3AF)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Best Seller',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF004AAD),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  course.title,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  course.description,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF4B5563),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'What you will get:',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                _buildHighlightItem(Icons.menu_book, 'Comprehensive Chapters'),
                _buildHighlightItem(Icons.quiz, 'Interactive Quizzes'),
                _buildHighlightItem(Icons.assignment, 'Final Essay Assignment'),
                _buildHighlightItem(Icons.workspace_premium, 'Professional Digital Certificate'),
                const SizedBox(height: 24),
                if (!course.isEnrolled)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Price',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                          Text(
                            '₱${course.price.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: () => widget.onEnrollCourse(course),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          'Enroll Now',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Builder(
                    builder: (context) {
                      final progress = _calculateProgress(course);
                      final String buttonText;
                      final IconData buttonIcon;
                      final Color buttonColor;
                      if (progress == 0) {
                        buttonText = 'Start Course';
                        buttonIcon = Icons.play_arrow;
                        buttonColor = const Color(0xFF004AAD);
                      } else if (progress == 100) {
                        buttonText = 'Completed';
                        buttonIcon = Icons.check_circle;
                        buttonColor = const Color(0xFF10B981);
                      } else {
                        buttonText = 'In Progress';
                        buttonIcon = Icons.trending_up;
                        buttonColor = const Color(0xFFD97706);
                      }

                      return SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => _startLearning(course),
                          icon: Icon(buttonIcon, color: Colors.white),
                          label: Text(
                            buttonText,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 2,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF004AAD)),
          const SizedBox(width: 12),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificatesTab() {
    final enrolled = _courses.where((c) => c.isEnrolled).toList();
    if (enrolled.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Enroll in Tesol Prime to start earning certificates!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF6B7280)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => setState(() => _currentTabIndex = 0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004AAD),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Go to Home', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: enrolled.length,
      itemBuilder: (context, index) {
        final course = enrolled[index];
        final progress = _calculateProgress(course);
        return Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Progress: $progress%',
                  style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF4B5563)),
                ),
                const SizedBox(height: 12),
                if (progress == 100) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => widget.onViewCertificate(course),
                      icon: const Icon(Icons.badge, color: Colors.white, size: 18),
                      label: Text('View Certificate', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004AAD),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        final url = Uri.parse(
                          '${ApiService.baseUrl}/api/courses/${course.id}/certificate/download?user_id=${widget.user.id}',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } else {
                          _showError('Could not open download link');
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        'Download Certificate',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF374151),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock, color: Color(0xFF6B7280), size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Locked (Complete course to unlock)',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: const Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileTab() {
    final enrolledCount = _courses.where((c) => c.isEnrolled).length;
    final completedCount = _courses.where((c) => c.isEnrolled && _calculateProgress(c) == 100).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF004AAD),
                    child: Text(
                      widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : 'U',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.name,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.user.email,
                            maxLines: 1,
                            softWrap: false,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: const Color(0xFFE5E7EB)),
              const SizedBox(height: 16),
              Text(
                'Learning Progress',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            enrolledCount.toString(),
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF004AAD),
                            ),
                          ),
                          Text(
                            'Enrolled',
                            style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            completedCount.toString(),
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                          Text(
                            'Completed',
                            style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: widget.onLogOut,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'Log Out',
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyllabusView(Course course) {
    final progress = _calculateProgress(course);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Overall Completion',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress / 100.0,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$progress% Completed',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF4B5563),
                    ),
                  ),
                  if (progress == 100) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: () => widget.onViewCertificate(course),
                        icon: const Icon(Icons.verified, color: Colors.white, size: 16),
                        label: Text('Claim Completion Certificate', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD97706),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _syllabusTabController,
            children: [
              _buildPdfsTab(course),
              _buildQuizzesTab(course),
              _buildEssayTab(course),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPdfsTab(Course course) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: course.pdfData.length,
      itemBuilder: (context, index) {
        final chapter = course.pdfData[index];
        final isDone = course.pdfCompleted.contains(chapter.chapterNumber);

        return Card(
          color: isDone ? const Color(0xFFF0FDF4) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDone ? const Color(0xFFA7F3D0) : const Color(0xFFE5E7EB)),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            onTap: () => _handlePdfClick(chapter, course),
            leading: Icon(
              Icons.article,
              color: isDone ? const Color(0xFF10B981) : const Color(0xFF6B7280),
            ),
            title: Text(
              'Chapter ${chapter.chapterNumber}',
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111827),
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDone ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isDone ? 'Completed' : 'Pending',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDone ? const Color(0xFF047857) : const Color(0xFFD97706),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuizzesTab(Course course) {
    List<Widget> children = [];
    int globalIndex = 0;

    for (final qc in course.quizData) {
      for (int i = 0; i < qc.quizzes.length; i++) {
        final q = qc.quizzes[i];
        final key = '${qc.chapterNumber}_$i';
        final selectedVal = _quizAnswers[key];
        globalIndex++;

        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QUESTION $globalIndex:',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF004AAD),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  q.question,
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                ...q.options.map((opt) {
                  final isSelected = selectedVal == opt;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: InkWell(
                      onTap: () async {
                        setState(() {
                          _quizAnswers[key] = opt;
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt('last_left_tab_${widget.user.id}_${course.id}', 1);
                        await prefs.setInt('last_left_chapter_${widget.user.id}_${course.id}', qc.chapterNumber);
                        setState(() {
                          _lastLeftTab = 1;
                          _lastLeftChapter = qc.chapterNumber;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF60A5FA) : const Color(0xFFE5E7EB),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF004AAD) : const Color(0xFF9CA3AF),
                                  width: 2,
                                ),
                                color: isSelected ? const Color(0xFF004AAD) : Colors.transparent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                opt,
                                style: GoogleFonts.poppins(
                                  fontSize: 13.5,
                                  color: isSelected ? const Color(0xFF004AAD) : const Color(0xFF374151),
                                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      }
    }

    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 10.0, bottom: 20.0),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => _handleSubmitAllQuizzes(course),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004AAD),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              'Submit All Answers',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  Widget _buildEssayTab(Course course) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: course.essayPrompt.length,
      itemBuilder: (context, index) {
        final prompt = course.essayPrompt[index];
        final isSubmitted = _essaySubmittedMap[index] == true;

        return Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'QUESTION ${index + 1}:',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF004AAD),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(
                    prompt,
                    style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF4B5563), height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _essayAnswers[index] ?? '',
                  maxLines: 6,
                  enabled: !isSubmitted,
                  onChanged: (text) async {
                    _essayAnswers[index] = text;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('last_left_tab_${widget.user.id}_${course.id}', 2);
                    await prefs.setInt('last_left_chapter_${widget.user.id}_${course.id}', index + 1);
                    setState(() {
                      _lastLeftTab = 2;
                      _lastLeftChapter = index + 1;
                    });
                  },
                  textAlignVertical: TextAlignVertical.top,
                  style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF111827)),
                  decoration: InputDecoration(
                    hintText: 'Type your response here...',
                    hintStyle: GoogleFonts.poppins(color: const Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    contentPadding: const EdgeInsets.all(12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF004AAD)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (isSubmitted) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF065F46), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Submitted',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF065F46),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => _handleSubmitEssay(index, course),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004AAD),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        'Submit Response',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
