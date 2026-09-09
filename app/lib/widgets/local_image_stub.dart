import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';

/// Web 实现：image_picker 在 Web 端返回的 XFile.path 是 blob: URL
ImageProvider platformImageProvider(XFile file) => NetworkImage(file.path);
