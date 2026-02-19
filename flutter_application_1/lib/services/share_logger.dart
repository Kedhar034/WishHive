import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ShareLogger {
  static Future<File> _getLogFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/share_logs.txt');
  }

  static Future<void> log(String message) async {
    try {
      final file = await _getLogFile();
      final timestamp = DateTime.now().toIso8601String();
      final logMessage = '[$timestamp] $message\n-----------------------------------\n';
      await file.writeAsString(logMessage, mode: FileMode.append);
      print("Logged to file: $message"); // Keep console log as well
    } catch (e) {
      print("Failed to write to log file: $e");
    }
  }

  static Future<String> readLogs() async {
    try {
      final file = await _getLogFile();
      if (await file.exists()) {
        return await file.readAsString();
      }
      return 'No logs found.';
    } catch (e) {
      return 'Error reading logs: $e';
    }
  }

  static Future<void> clearLogs() async {
    try {
      final file = await _getLogFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print("Failed to clear logs: $e");
    }
  }
}
