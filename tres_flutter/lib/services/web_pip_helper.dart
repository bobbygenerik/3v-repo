// Conditional export for web PiP service
export 'web_pip_service_stub.dart'
    if (dart.library.html) 'web_pip_service.dart';
