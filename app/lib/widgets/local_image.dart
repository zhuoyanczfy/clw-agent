import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';

import 'local_image_stub.dart' if (dart.library.io) 'local_image_io.dart';

/// 刚选中的本地图片（XFile）转 ImageProvider：
/// 移动端 path 是磁盘路径走 FileImage；Web 端 path 是 blob: URL 走 NetworkImage。
/// （dart:io 在 Web 上无法编译，File 的创建拆到条件导入文件里）
ImageProvider localImageProvider(XFile file) => platformImageProvider(file);
