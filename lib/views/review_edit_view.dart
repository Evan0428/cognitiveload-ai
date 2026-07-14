import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/ocr_viewmodel.dart';
import '../services/app_state.dart'; // 🟢 引入全局状态，用来同步数据更新主页

class ReviewEditView extends StatefulWidget {
  final OcrViewModel viewModel;
  const ReviewEditView({super.key, required this.viewModel});

  @override
  State<ReviewEditView> createState() => _ReviewEditViewState();
}

class _ReviewEditViewState extends State<ReviewEditView> {
  // 🟢 移到类成员变量，防止 build 刷新时输入文字被重置
  final List<TextEditingController> _subjectControllers = [];

  @override
  void initState() {
    super.initState();
    // 🟢 在页面诞生的瞬间初始化一次控制器
    for (var task in widget.viewModel.extractedTasks) {
      _subjectControllers.add(TextEditingController(text: task.subject));
    }
  }

  @override
  void dispose() {
    // 释放资源
    for (var ctrl in _subjectControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: TextButton.icon(
          icon: const Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF4A3AFF)),
          label: const Text('Retake', style: TextStyle(color: Color(0xFF4A3AFF), fontWeight: FontWeight.bold)),
          onPressed: () => Navigator.pop(context),
        ),
        leadingWidth: 100,
        title: const Text('Review & Edit', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 🟢 顶部的绿色提取成功提示条
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF15803D), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Successfully extracted ${widget.viewModel.extractedTasks.length} entries. Review and edit before saving.',
                    style: const TextStyle(color: Color(0xFF15803D), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          // 列表区域
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.viewModel.extractedTasks.length,
              itemBuilder: (context, index) {
                final task = widget.viewModel.extractedTasks[index];

                // 确保防止越界安全策略
                if (index >= _subjectControllers.length) {
                  _subjectControllers.add(TextEditingController(text: task.subject));
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 卡片标题栏包含删除按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Entry ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                          IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 20),
                            onPressed: () {
                              setState(() {
                                widget.viewModel.removeTaskAt(index);
                                _subjectControllers.removeAt(index); // 同步移除对应的控制器
                              });
                            },
                          )
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 课程名输入项
                      _buildLabel('Subject/Task'),
                      TextField(
                        controller: _subjectControllers[index],
                        decoration: _inputDecoration(),
                        onChanged: (val) {
                          // 🟢 随着用户修改，同步调用 ViewModel 算法对该单项实时打分并重算
                          widget.viewModel.updateSubjectAt(index, val);
                        },
                      ),
                      const SizedBox(height: 12),

                      // 星期 & 日期并排
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('Day'),
                                TextFormField(initialValue: task.day, decoration: _inputDecoration(), onChanged: (val) => task.day = val),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('Date'),
                                TextFormField(initialValue: task.date, decoration: _inputDecoration(suffixIcon: Icons.calendar_today_outlined), onChanged: (val) => task.date = val),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 开始时间 & 结束时间并排
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('Start Time'),
                                TextFormField(initialValue: task.startTime, decoration: _inputDecoration(suffixIcon: Icons.access_time), onChanged: (val) => task.startTime = val),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('End Time'),
                                TextFormField(initialValue: task.endTime, decoration: _inputDecoration(suffixIcon: Icons.access_time), onChanged: (val) => task.endTime = val),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 底部保存总动员按钮
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A3AFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () async {
                  // 🟢 核心改动：获取本地全局状态机的指针
                  final globalState = context.read<AppState>();

                  // 🟢 将本地全局状态传入，进行：云端保存备份 + 本地加总算分完美大联动！
                  bool success = await widget.viewModel.saveAllTasksToFirebase(globalState);

                  if (success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All extracted tasks saved & load recalculated!'), backgroundColor: Colors.green),
                    );

                    // 彻底回到最前面的 Dashboard 主页
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
                child: Text('Save to Schedule (${widget.viewModel.extractedTasks.length} tasks)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
    );
  }

  InputDecoration _inputDecoration({IconData? suffixIcon}) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      suffixIcon: suffixIcon != null ? Icon(suffixIcon, size: 16, color: Colors.grey) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF4A3AFF))),
    );
  }
}