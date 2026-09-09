import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';

/// 移动端实现：XFile.path 是磁盘文件路径
ImageProvider platformImageProvider(XFile file) => FileImage(File(file.path));
