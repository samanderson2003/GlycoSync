import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glycosync/screens/Patients/auth/view/Login_view.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:glycosync/screens/Patients/routine/model/routine_model.dart';
import '../model/profile_model.dart';

class ProfileController {
  final ValueNotifier<ProfileModel> modelNotifier = ValueNotifier(
    ProfileModel(),
  );

  final RoutineModel _routineData =
      _getInitialRoutineData(); // Master routine data

  // Fetches initial profile and report data for the current week.
  Future<void> fetchProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    modelNotifier.value = modelNotifier.value.copyWith(isLoading: true);

    try {
      // Fetch patient details from all collections
      final patientDoc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(user.uid)
          .get();
      final patientDetailsDoc = await FirebaseFirestore.instance
          .collection('patients_details')
          .doc(user.uid)
          .get();

      // --- MODIFIED: Fetch the LATEST lab report from the subcollection ---
      final latestReportSnapshot = await FirebaseFirestore.instance
          .collection('lab_reports')
          .doc(user.uid)
          .collection('submissions')
          .orderBy('reportDate', descending: true)
          .limit(1)
          .get();

      Map<String, dynamic>? labReportDataMap;
      DateTime? lastReportDate;

      // If a report exists, get its data and date
      if (latestReportSnapshot.docs.isNotEmpty) {
        labReportDataMap = latestReportSnapshot.docs.first.data();
        lastReportDate = (labReportDataMap['reportDate'] as Timestamp).toDate();
      }

      final patientData = patientDoc.data();
      final patientDetailsData = patientDetailsDoc.data();

      // Fetch the report for the current week
      final weeklyData = await fetchWeeklyReport(DateTime.now());

      modelNotifier.value = modelNotifier.value.copyWith(
        patientName: patientData?['name'] ?? 'No Name',
        patientEmail: patientData?['email'] ?? 'No Email',
        diabetesType: patientDetailsData?['diabetesType'] ?? '-',
        height: patientDetailsData?['height'] ?? '-',
        weight: patientDetailsData?['weight'] ?? '-',
        weeklyReportData: weeklyData,
        labReportData: LabReportData(
          hba1c: labReportDataMap?['hba1c'] ?? '-',
          avgBloodGlucose: labReportDataMap?['avgBloodGlucose'] ?? '-',
          fastingBloodSugar: labReportDataMap?['fastingBloodSugar'] ?? '-',
        ),
        // --- NEW: Pass the date to the model ---
        lastReportDate: lastReportDate,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error fetching profile data: $e');
      modelNotifier.value = modelNotifier.value.copyWith(isLoading: false);
    }
  }

  // Fetches report data for a specific week.
  Future<List<DailyReportData>> fetchWeeklyReport(DateTime date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    // Determine the start and end of the week for the given date
    final startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    final completionsSnapshot = await FirebaseFirestore.instance
        .collection('patients')
        .doc(user.uid)
        .collection('routine_completions')
        .where(
          'completedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
        )
        .where(
          'completedAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek),
        )
        .get();

    // Group completions by date
    final Map<String, List<QueryDocumentSnapshot>> completionsByDate = {};
    for (var doc in completionsSnapshot.docs) {
      final dateString = doc['completionDate'] as String;
      if (completionsByDate[dateString] == null) {
        completionsByDate[dateString] = [];
      }
      completionsByDate[dateString]!.add(doc);
    }

    // Generate daily data for the whole week
    final List<DailyReportData> weeklyData = [];
    for (int i = 0; i < 7; i++) {
      final day = startOfWeek.add(Duration(days: i));
      final dayString = DateFormat('yyyy-MM-dd').format(day);
      final dayCompletions = completionsByDate[dayString] ?? [];

      double netGlucose = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;
      List<String> completedLevels = [];

      final completedTitles = dayCompletions
          .map((doc) => doc['levelTitle'] as String)
          .toSet();
      netGlucose = dayCompletions.fold(
        0.0,
        (sum, doc) => sum + (doc['glucoseImpact'] ?? 0.0),
      );
      completedLevels = completedTitles.toList();

      // Calculate nutrition from master data
      for (var level in _routineData.levels) {
        if (completedTitles.contains(level.title)) {
          for (var task in level.subTasks) {
            totalProtein += task.protein ?? 0;
            totalCarbs += task.carbs ?? 0;
            totalFat += task.fat ?? 0;
          }
        }
      }

      weeklyData.add(
        DailyReportData(
          date: day,
          netGlucoseImpact: netGlucose,
          totalProtein: totalProtein,
          totalCarbs: totalCarbs,
          totalFat: totalFat,
          completedLevels: completedLevels,
        ),
      );
    }
    return weeklyData;
  }

  // Called when the user selects a new date from the calendar.
  Future<void> onDateSelected(DateTime newDate) async {
    modelNotifier.value = modelNotifier.value.copyWith(isLoading: true);
    final weeklyData = await fetchWeeklyReport(newDate);
    modelNotifier.value = modelNotifier.value.copyWith(
      weeklyReportData: weeklyData,
      isLoading: false,
    );
  }

  Future<void> generateAndDownloadReport() async {
    final reportData = modelNotifier.value;
    if (reportData.weeklyReportData.isEmpty) return;

    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.poppinsRegular();
      final boldFont = await PdfGoogleFonts.poppinsBold();

      final startDate = reportData.weeklyReportData.first.date;
      final endDate = reportData.weeklyReportData.last.date;
      final reportDateRange =
          '${DateFormat.yMMMd().format(startDate)} - ${DateFormat.yMMMd().format(endDate)}';

      // Try to load logo, but continue if it fails
      pw.MemoryImage? logoImage;
      try {
        logoImage = pw.MemoryImage(
          (await rootBundle.load('assets/google.png')).buffer.asUint8List(),
        );
      } catch (e) {
        debugPrint('Logo not found, continuing without it: $e');
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    if (logoImage != null)
                      pw.SizedBox(width: 100, child: pw.Image(logoImage))
                    else
                      pw.Container(
                        width: 100,
                        height: 50,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.blue200,
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            'GlycoSync',
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 16,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Weekly Health Report',
                          style: pw.TextStyle(font: boldFont, fontSize: 24),
                        ),
                        pw.Text(
                          reportDateRange,
                          style: pw.TextStyle(font: font, fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 2, height: 30),
                pw.Text(
                  'Patient Details',
                  style: pw.TextStyle(font: boldFont, fontSize: 18),
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Name: ${reportData.patientName}',
                      style: pw.TextStyle(font: font),
                    ),
                    pw.Text(
                      'Email: ${reportData.patientEmail}',
                      style: pw.TextStyle(font: font),
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Latest Lab Results',
                  style: pw.TextStyle(font: boldFont, fontSize: 18),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey),
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      _buildLabStat(
                        'HbA1c',
                        '${reportData.labReportData.hba1c} %',
                        boldFont,
                        font,
                      ),
                      _buildLabStat(
                        'Avg. Blood Glucose',
                        '${reportData.labReportData.avgBloodGlucose} mg/dL',
                        boldFont,
                        font,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Daily Activity Log',
                  style: pw.TextStyle(font: boldFont, fontSize: 18),
                ),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.5),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(3),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Date',
                            style: pw.TextStyle(font: boldFont),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Glucose Impact',
                            style: pw.TextStyle(font: boldFont),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Completed Levels',
                            style: pw.TextStyle(font: boldFont),
                          ),
                        ),
                      ],
                    ),
                    ...reportData.weeklyReportData.map((day) {
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              DateFormat('EEE, MMM d').format(day.date),
                              style: pw.TextStyle(font: font),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              '${day.netGlucoseImpact.toStringAsFixed(1)}',
                              style: pw.TextStyle(font: font),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              day.completedLevels.isEmpty
                                  ? 'No activity'
                                  : day.completedLevels.join(', '),
                              style: pw.TextStyle(font: font),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
                pw.Spacer(),
                pw.Divider(thickness: 1, height: 20),
                pw.Center(
                  child: pw.Text(
                    '*** This is an auto-generated report ***',
                    style: pw.TextStyle(font: font, color: PdfColors.grey),
                  ),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      debugPrint('Error generating PDF report: $e');
      // You could also show a snackbar here if you have BuildContext
      rethrow; // Re-throw to allow UI to handle the error
    }
  }

  pw.Widget _buildLabStat(
    String label,
    String value,
    pw.Font bold,
    pw.Font regular,
  ) {
    return pw.Column(
      children: [
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text(label, style: pw.TextStyle(font: regular, fontSize: 10)),
      ],
    );
  }

  Future<void> signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginView()),
      (route) => false,
    );
  }

  void dispose() {
    modelNotifier.dispose();
  }
}

RoutineModel _getInitialRoutineData() {
  // This function would contain the master list of all routines
  // It's copied here to allow the controller to calculate nutrition
  // based on completed level titles.
  return RoutineModel(
    levels: [
      /* ... Full routine data ... */
    ],
  );
}
