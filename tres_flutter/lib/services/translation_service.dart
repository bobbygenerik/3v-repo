import 'package:http/http.dart' as http;
import 'dart:convert';

class TranslationService {
  Future<Map<String, String>> translateAudio(String audioUrl, {String srcLang = 'eng_Latn', String tgtLang = 'spa_Latn'}) async {
    final response = await http.post(
      Uri.parse('http://15.204.95.57:5000/translate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'audioUrl': audioUrl, 'srcLang': srcLang, 'tgtLang': tgtLang}),
    );
    
    final data = jsonDecode(response.body);
    return {'text': data['text']};
  }
}
