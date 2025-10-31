import 'dart:typed_data';
import 'dart:html' as html;

class WebImagePicker {
  static Future<Uint8List?> pickImage() async {
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    uploadInput.click();

    await uploadInput.onChange.first;
    final files = uploadInput.files;
    if (files == null || files.isEmpty) return null;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(files[0]);
    await reader.onLoad.first;

    return reader.result as Uint8List;
  }
}
