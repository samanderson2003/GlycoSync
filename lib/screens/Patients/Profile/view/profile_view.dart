import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../controller/profile_controller.dart';
import '../model/profile_model.dart';
// --- NEW: Import the submission view ---
import 'lab_report_submission_view.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final ProfileController _controller;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _controller = ProfileController();
    _controller.fetchProfileData();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _controller.onDateSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5EFE6), // Your cream background
      appBar: AppBar(
        title: const Text(
          "Profile",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22,
          ),
        ),
        backgroundColor: const Color(0xFF6D94C5), // Your medium blue
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ValueListenableBuilder<ProfileModel>(
        valueListenable: _controller.modelNotifier,
        builder: (context, model, child) {
          if (model.isLoading && model.patientName == 'Loading...') {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildProfileHeader(context, model),
                const SizedBox(height: 24),
                // --- NEW: Add the prompt card here ---
                _buildSubmitReportPrompt(context, model.lastReportDate),
                const SizedBox(height: 24),
                _buildHealthSnapshot(context, model),
                const SizedBox(height: 24),
                _buildWeeklyReport(context, model),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, ProfileModel model) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF6D94C5), // Your medium blue
              child: const Icon(Icons.person, size: 30, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.patientName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6D94C5), // Your medium blue
                    ),
                  ),
                  Text(
                    model.patientEmail,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6D94C5), // Your medium blue
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              onPressed: () => _controller.signOut(context),
            ),
          ],
        ),
      ),
    );
  }

  // --- NEW: Widget to display the submission prompt ---
  Widget _buildSubmitReportPrompt(
    BuildContext context,
    DateTime? lastReportDate,
  ) {
    String title;
    String subtitle;

    if (lastReportDate == null) {
      title = 'Submit Your First Lab Report';
      subtitle = 'Start tracking your health progress.';
    } else if (DateTime.now().difference(lastReportDate).inDays > 30) {
      title = 'New Lab Report Due';
      subtitle = 'Your last report was over a month ago.';
    } else {
      // If the report is recent, don't show the prompt
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      color: const Color(0xFFCBDCEB), // Your light blue
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(
          color: Color(0xFF6D94C5),
        ), // Your medium blue border
      ),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF6D94C5), // Your medium blue
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF6D94C5), // Your medium blue
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Color(0xFF6D94C5), // Your medium blue
        ),
        onTap: () async {
          // Navigate and wait for a result
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => const LabReportSubmissionView(),
            ),
          );
          // If the result is true (submission was successful), refresh the profile data
          if (result == true) {
            _controller.fetchProfileData();
          }
        },
      ),
    );
  }

  Widget _buildHealthSnapshot(BuildContext context, ProfileModel model) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Latest Lab Results',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6D94C5), // Your medium blue
              ),
            ),
            const Divider(
              height: 20,
              color: Color(0xFFCBDCEB), // Your light blue
            ),
            // Use Wrap for better responsiveness
            Wrap(
              alignment: WrapAlignment.spaceAround,
              spacing: 12.0, // Horizontal space
              runSpacing: 16.0, // Vertical space
              children: [
                _buildStatItem(
                  'HbA1c',
                  '${model.labReportData.hba1c} %',
                  _getStatColor('hba1c', model.labReportData.hba1c),
                ),
                _buildStatItem(
                  'Avg. Blood Glucose',
                  '${model.labReportData.avgBloodGlucose} mg/dL',
                  _getStatColor(
                    'avgGlucose',
                    model.labReportData.avgBloodGlucose,
                  ),
                ),
                _buildStatItem(
                  'Fasting Glucose',
                  '${model.labReportData.fastingBloodSugar} mg/dL',
                  _getStatColor(
                    'fasting',
                    model.labReportData.fastingBloodSugar,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatColor(String type, String value) {
    final double? val = double.tryParse(value);
    if (val == null) return Colors.black;

    switch (type) {
      case 'hba1c':
        if (val > 8.0) return Colors.red.shade700; // Poor control
        if (val > 6.5) return Colors.orange.shade700; // Fair control
        return Colors.green.shade700; // Good control
      case 'avgGlucose':
      case 'fasting':
        if (val > 180) return Colors.red.shade700; // Poor control
        if (val > 150) return Colors.orange.shade700; // Fair control
        return Colors.green.shade700; // Good control
      default:
        return Colors.black;
    }
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6D94C5), // Your medium blue
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildWeeklyReport(BuildContext context, ProfileModel model) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Weekly Activity Report',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6D94C5), // Your medium blue
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Color(0xFF6D94C5), // Your medium blue
                  ),
                  label: Text(
                    DateFormat.yMMMd().format(_selectedDate),
                    style: const TextStyle(
                      color: Color(0xFF6D94C5), // Your medium blue
                    ),
                  ),
                  onPressed: () => _selectDate(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (model.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (model.weeklyReportData.isEmpty)
              const Center(child: Text('No data for this week.'))
            else
              Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: BarChart(_buildBarChartData(model.weeklyReportData)),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Download Full Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(
                        0xFF6D94C5,
                      ), // Your medium blue
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      try {
                        await _controller.generateAndDownloadReport();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Report generated successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to generate report: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  BarChartData _buildBarChartData(List<DailyReportData> data) {
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: 50,
      minY: -20,
      barTouchData: BarTouchData(enabled: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final day = data[value.toInt()].date;
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(DateFormat.E().format(day)), // e.g., 'Mon'
              );
            },
            reservedSize: 30,
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 10,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      barGroups: data
          .asMap()
          .entries
          .map(
            (entry) => BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.netGlucoseImpact,
                  color: entry.value.netGlucoseImpact >= 0
                      ? const Color(
                          0xFFE8DFCA,
                        ) // Your beige for positive impact
                      : const Color(
                          0xFF6D94C5,
                        ), // Your medium blue for negative impact
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}
