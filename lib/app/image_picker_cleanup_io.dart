import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// 删除 image_picker 为本次选择生成的应用内副本。
///
/// Android 上的相机拍摄和相册选择都会先把结果复制到应用缓存；读取完后删除这份副本，
/// 用户相册里的原文件不受影响。清理是尽力而为的，失败时留给系统缓存回收。
Future<void> discardImagePickerCopy(XFile file) =>
    discardImagePickerPath(file.path);

Future<void> discardImagePickerPath(String? path) async {
  if (path == null || path.isEmpty) {
    return;
  }
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // 清理失败不影响已经读取完成的图片数据；缓存由系统按空间回收。
  }
}
