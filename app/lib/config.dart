import 'dart:io';

String getBaseUrl({bool? isAndroid}) {
  final android = isAndroid ?? Platform.isAndroid;
  return android ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
}
