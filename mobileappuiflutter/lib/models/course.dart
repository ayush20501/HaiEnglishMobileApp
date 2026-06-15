class Chapter {
  final int chapterNumber;
  final String title;
  final String pdfUrl;

  Chapter({
    required this.chapterNumber,
    required this.title,
    required this.pdfUrl,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      chapterNumber: json['chapter_number'] as int,
      title: json['title'] as String,
      pdfUrl: json['pdf_url'] as String,
    );
  }
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final String answer;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.answer,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      question: json['question'] as String,
      options: List<String>.from(json['options']),
      answer: json['answer'] as String,
    );
  }
}

class QuizChapter {
  final int chapterNumber;
  final List<QuizQuestion> quizzes;

  QuizChapter({
    required this.chapterNumber,
    required this.quizzes,
  });

  factory QuizChapter.fromJson(Map<String, dynamic> json) {
    var list = json['quizzes'] as List? ?? [];
    return QuizChapter(
      chapterNumber: json['chapter_number'] as int,
      quizzes: list.map((item) => QuizQuestion.fromJson(item)).toList(),
    );
  }
}

class Course {
  final int id;
  final String title;
  final String description;
  final double price;
  final String coursePosterUrl;
  final List<Chapter> pdfData;
  final List<QuizChapter> quizData;
  final List<String> essayPrompt;
  final bool isEnrolled;
  final List<int> pdfCompleted;
  final Map<String, int> quizScore;
  final bool essaySubmitted;

  Course({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.coursePosterUrl,
    required this.pdfData,
    required this.quizData,
    required this.essayPrompt,
    required this.isEnrolled,
    required this.pdfCompleted,
    required this.quizScore,
    required this.essaySubmitted,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    var pdfList = json['pdf_data'] as List? ?? [];
    var quizList = json['quiz_data'] as List? ?? [];
    var essayList = json['essay_prompt'] as List? ?? [];
    var completedList = json['pdf_completed'] as List? ?? [];

    Map<String, int> scores = {};
    if (json['quiz_score'] is Map) {
      (json['quiz_score'] as Map).forEach((key, value) {
        scores[key.toString()] = value as int;
      });
    }

    return Course(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      coursePosterUrl: json['course_poster_url'] as String,
      pdfData: pdfList.map((item) => Chapter.fromJson(item)).toList(),
      quizData: quizList.map((item) => QuizChapter.fromJson(item)).toList(),
      essayPrompt: List<String>.from(essayList),
      isEnrolled: json['is_enrolled'] as bool? ?? false,
      pdfCompleted: List<int>.from(completedList),
      quizScore: scores,
      essaySubmitted: (json['essay_submitted'] == 1 || json['essay_submitted'] == true),
    );
  }
}
