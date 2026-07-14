class ExtractedTaskModel {
  String subject;
  String day;
  String date;
  String startTime;
  String endTime;
  int cognitiveLoadScore;

  ExtractedTaskModel({
    required this.subject,
    required this.day,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.cognitiveLoadScore = 50,
  });
}