import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/ocr_viewmodel.dart'; // 🟢 完美修复：调整为带有下划线的正确目录路径
import 'review_edit_view.dart';

class ScanTimetableView extends StatelessWidget {
  const ScanTimetableView({super.key});

  @override
  Widget build(BuildContext context) {
    // 🟢 实例化并监听本地闭环的 OcrViewModel
    return ChangeNotifierProvider(
      create: (_) => OcrViewModel(),
      child: Consumer<OcrViewModel>(
        builder: (context, vm, child) {
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
                onPressed: () => Navigator.pop(context),
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: vm.isProcessing
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4A3AFF)),
                  SizedBox(height: 16),
                  Text('Utilizing Google ML Kit to extract text...', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500))
                ],
              ),
            )
                : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),
                  // 🔮 图标圈
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(color: Color(0xFFEAEAFF), shape: BoxShape.circle),
                      child: const Icon(Icons.document_scanner_outlined, size: 38, color: Color(0xFF4A3AFF)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Scan Timetable', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  const Text('Import your schedule using OCR technology', style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                  const SizedBox(height: 40),

                  // 📸 按钮一：拍照 (FR 2.1)
                  _buildActionButton(
                    icon: Icons.camera_alt_outlined,
                    title: 'Take Photo',
                    subtitle: 'Use camera to scan timetable',
                    onTap: () async {
                      bool success = await vm.capturePhoto();
                      if (success && context.mounted) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewEditView(viewModel: vm)));
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // 🖼️ 按钮二：相册上传 (FR 2.2)
                  _buildActionButton(
                    icon: Icons.upload_file_outlined,
                    title: 'Upload Image',
                    subtitle: 'Select from gallery',
                    onTap: () async {
                      bool success = await vm.uploadFromGallery();
                      if (success && context.mounted) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewEditView(viewModel: vm)));
                      }
                    },
                  ),
                  const Spacer(),

                  // 💡 底部提示框
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(16)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tips for better results:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF), fontSize: 13)),
                        SizedBox(height: 6),
                        Text('•  Ensure good lighting and clear text\n•  Align timetable within frame\n•  Avoid shadows and glare', style: TextStyle(color: Color(0xFF1E40AF), fontSize: 12, height: 1.6)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(color: const Color(0xFF4A3AFF), borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}