import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class TranslationService {
  Future<Map<String, String>> translateAudio(
    String audioFilePath, {
    String srcLang = 'eng_Latn',
    String tgtLang = 'spa_Latn',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://15.204.95.57:5000/translate'),
    );

    request.fields['srcLang'] = srcLang;
    request.fields['tgtLang'] = tgtLang;
    request.files.add(
      await http.MultipartFile.fromPath('audio', audioFilePath),
    );

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    final data = jsonDecode(responseBody);

    return {'text': data['text']};
  }
}
