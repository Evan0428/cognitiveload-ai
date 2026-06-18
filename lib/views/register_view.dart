import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 🟢 引入用于在本地校验手机号是否重复
import '../view_models/auth_view_model.dart';
import 'setup_profile_view.dart'; // 🟢 导入新页面

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = Provider.of<AuthViewModel>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFEDF1F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: authViewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Create Account', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 8),
                const Text('Join CognitiveLoadAI to manage your cognitive load', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                const SizedBox(height: 30),

                _buildCustomTextField(controller: _nameController, hintText: 'e.g:John Doe', labelText: 'Full Name', icon: Icons.person_outline),
                const SizedBox(height: 16),
                _buildCustomTextField(
                    controller: _emailController,
                    hintText: 'your.email@example.com',
                    labelText: 'Email',
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'This field cannot be empty';
                      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegex.hasMatch(val.trim())) return 'Please enter a valid email address';
                      return null;
                    }
                ),
                const SizedBox(height: 16),
                _buildCustomTextField(controller: _mobileController, hintText: 'e.g:0123456789', labelText: 'Mobile Number', icon: Icons.phone_android_outlined),
                const SizedBox(height: 16),

                _buildCustomTextField(
                  controller: _passwordController,
                  hintText: '********',
                  labelText: 'Password',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),

                _buildCustomTextField(
                  controller: _confirmPasswordController,
                  hintText: '********',
                  labelText: 'Confirm Password',
                  icon: Icons.lock_outline,
                  obscureText: _obscureConfirmPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'This field cannot be empty';
                    if (val != _passwordController.text) return 'Passwords do not match!';
                    return null;
                  },
                ),
                const SizedBox(height: 40),

                // 下一步按钮：直接去注册用户，并在后端暂存基础信息后跳转
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A3AFF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        final emailInput = _emailController.text.trim();
                        final mobileInput = _mobileController.text.trim();
                        final passwordInput = _passwordController.text;

                        // 🔒 核心安全机制：先去 Firestore 中查询该电话号码是否已被绑定注册
                        try {
                          final mobileQuery = await FirebaseFirestore.instance
                              .collection('users')
                              .where('mobileNumber', isEqualTo: mobileInput)
                              .get();

                          if (mobileQuery.docs.isNotEmpty) {
                            // 如果结果不为空，说明号码已被占用，立刻弹出警告拦截
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.phone_android_rounded, color: Colors.redAccent),
                                    SizedBox(width: 8),
                                    Text('Mobile Number In Use', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: const Text('This mobile number is already linked to another account. Please use a different number.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK', style: TextStyle(color: Color(0xFF4A3AFF), fontWeight: FontWeight.bold)),
                                  )
                                ],
                              ),
                            );
                            return; // 🛑 关键：在此处强行掐断函数，不运行下方的注册逻辑
                          }
                        } catch (e) {
                          // 容错处理：若 Firestore 查询发生意外，打印日志，让底层的 Auth 模块保障兜底
                          print("Mobile uniqueness check exception: $e");
                        }

                        // 🟢 号码独一无二，通过本地验证，正常开始走向账号注册
                        String? error = await authViewModel.registerUser(
                          name: _nameController.text.trim(),
                          email: emailInput,
                          password: passwordInput,
                          mobileNumber: mobileInput,
                          profileType: 'Student', // 默认初值
                          burnoutThreshold: 70.0, // 默认初值
                        );

                        if (error == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account basic settings created!'), backgroundColor: Colors.green));

                          // 🟢 重点：完美路由跳转去个性化资料设置页
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const SetupProfileView()),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
                        }
                      }
                    },
                    child: const Text('Next Step', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String hintText,
    required String labelText,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labelText, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hintText,
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: Icon(icon, color: Colors.grey),
              suffixIcon: suffixIcon,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            ),
            validator: validator ?? (val) => val == null || val.isEmpty ? 'This field cannot be empty' : null,
          ),
        ),
      ],
    );
  }
}