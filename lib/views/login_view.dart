import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/auth_view_model.dart';
import '../services/app_state.dart'; // 🟢 1. 引入全局 AppState 支持数据刷洗
import 'register_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = Provider.of<AuthViewModel>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFEDF1F9),
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
                const SizedBox(height: 60),
                // 1. App Logo 图片
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/CognitiveLoadAI-logo.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 24),
                // 2. 主标题与副标题
                const Text(
                  'CognitiveLoadAI',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                ),
                const Text(
                  'Smart Cognitive Load Management',
                  style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 40),

                // 3. Email 输入框
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Email', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'your.email@example.com',
                          hintStyle: TextStyle(color: Colors.grey),
                          prefixIcon: Icon(Icons.mail_outline, color: Colors.grey),
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'This field cannot be empty';
                          }
                          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                          if (!emailRegex.hasMatch(val.trim())) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 4. Password 输入框
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Password', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: '********',
                          hintStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
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
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        validator: (val) => val!.isEmpty ? 'This field cannot be empty' : null,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 5. Forgot Password 按钮
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      final _resetEmailController = TextEditingController();
                      showDialog(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          backgroundColor: const Color(0xFFEDF1F9),
                          title: const Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold)),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Enter your email address to receive a password reset link.', style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: TextField(
                                  controller: _resetEmailController,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'your.email@example.com',
                                    prefixIcon: Icon(Icons.mail_outline, color: Colors.grey),
                                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: authViewModel.isLoading
                                  ? null
                                  : () async {
                                final email = _resetEmailController.text.trim();
                                if (email.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter your email'), backgroundColor: Colors.orange),
                                  );
                                  return;
                                }
                                Navigator.pop(dialogContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Sending reset link...'), backgroundColor: Colors.blue),
                                );
                                String? error = await authViewModel.resetPassword(email);
                                if (error == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Password reset email sent! Check your inbox.'), backgroundColor: Colors.green),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error), backgroundColor: Colors.red),
                                  );
                                }
                              },
                              child: const Text('Send Link', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Forgot password?', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 10),

                // 6. Sign In 按钮
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        final emailInput = _emailController.text.trim();
                        final passwordInput = _passwordController.text;

                        // 1. 先去 Firestore 查一下这个邮箱有没有被注册过
                        try {
                          final userQuery = await FirebaseFirestore.instance
                              .collection('users')
                              .where('email', isEqualTo: emailInput)
                              .get();

                          if (userQuery.docs.isEmpty) {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Account Not Found', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: const Text('Email not registered. Please create an account.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                                  )
                                ],
                              ),
                            );
                            return;
                          }
                        } catch (e) {
                          print("Firestore check bypass: $e");
                        }

                        // 2. 邮箱存在，开始验证密码
                        String? error = await authViewModel.loginUser(emailInput, passwordInput);

                        if (error == null) {
                          // 🟢 2. 核心大联动补丁：登录成功后，立刻洗掉旧设备的 6 分脏缓存，主动把当前账号的所有任务拉回来计算
                          if (context.mounted) {
                            await Provider.of<AppState>(context, listen: false).syncTasksFromFirestore();
                          }
                        } else {
                          String alertMessage = 'Login failed. Please try again.';
                          final lowerError = error.toLowerCase();

                          if (lowerError.contains('wrong-password') ||
                              lowerError.contains('invalid-credential') ||
                              lowerError.contains('credential')) {
                            alertMessage = 'Password incorrect. Please try again.';
                          } else if (lowerError.contains('too-many-requests')) {
                            alertMessage = 'Too many attempts. Account temporarily locked. Try again later.';
                          }

                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Row(
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Login Error', style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              content: Text(alertMessage),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                                )
                              ],
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),
                // 7. 跳转注册页提示
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? ", style: TextStyle(color: Colors.grey)),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterView()));
                      },
                      child: const Text('Sign Up', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}