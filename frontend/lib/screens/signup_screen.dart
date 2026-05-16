import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
const SignupScreen({super.key});

@override
State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
final _formKey = GlobalKey<FormState>();
final _nameController = TextEditingController();
final _emailController = TextEditingController();
final _passwordController = TextEditingController();
final _confirmPasswordController = TextEditingController();
final AuthService _authService = AuthService();
bool _obscurePassword = true;
bool _obscureConfirmPassword = true;
bool _agreeToTerms = false;
bool _isLoading = false;

@override
void dispose() {
_nameController.dispose();
_emailController.dispose();
_passwordController.dispose();
_confirmPasswordController.dispose();
super.dispose();
}

Future<void> _handleSignup() async {
if (_formKey.currentState!.validate()) {
if (!_agreeToTerms) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Please agree to the terms and conditions'),
),
);
return;
}

setState(() => _isLoading = true);

try {
final result = await _authService.signUpWithEmailPassword(
email: _emailController.text.trim(),
password: _passwordController.text,
name: _nameController.text.trim(),
);

if (!mounted) return;
if (result != null || _authService.currentUser != null) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Account created successfully!'),
backgroundColor: Colors.green,
),
);
Navigator.pushReplacementNamed(context, '/home');
}
} catch (e) {
if (!mounted) return;
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
);
} finally {
if (mounted) setState(() => _isLoading = false);
}
}
}

Future<void> _handleGoogleSignup() async {
setState(() => _isLoading = true);
try {
final result = await _authService.signInWithGoogle();
if (!mounted) return;
if (result != null || _authService.currentUser != null) {
Navigator.pushReplacementNamed(context, '/home');
} else {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Google sign-in canceled or failed.'),
backgroundColor: Colors.orange,
),
);
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
);
}
} finally {
if (mounted) setState(() => _isLoading = false);
}
}

@override
Widget build(BuildContext context) {
return Scaffold(
body: SafeArea(
child: SingleChildScrollView(
padding: const EdgeInsets.all(24.0),
child: Form(
key: _formKey,
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
const SizedBox(height: 40),
const Text('Create Account',
style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
textAlign: TextAlign.center),
const SizedBox(height: 8),
const Text('Sign up to get started',
style: TextStyle(fontSize: 16, color: Colors.grey),
textAlign: TextAlign.center),
const SizedBox(height: 48),
TextFormField(
controller: _nameController,
keyboardType: TextInputType.name,
decoration: const InputDecoration(
labelText: 'Full Name',
prefixIcon: Icon(Icons.person),
border: OutlineInputBorder()),
validator: (value) {
if (value == null || value.isEmpty) return 'Please enter your name';
if (value.length < 3) return 'Name must be at least 3 characters';
return null;
},
),
const SizedBox(height: 16),
TextFormField(
controller: _emailController,
keyboardType: TextInputType.emailAddress,
decoration: const InputDecoration(
labelText: 'Email',
prefixIcon: Icon(Icons.email),
border: OutlineInputBorder()),
validator: (value) {
if (value == null || value.isEmpty) return 'Please enter your email';
if (!value.contains('@')) return 'Enter a valid email';
return null;
},
),
const SizedBox(height: 16),
TextFormField(
controller: _passwordController,
obscureText: _obscurePassword,
decoration: InputDecoration(
labelText: 'Password',
prefixIcon: const Icon(Icons.lock),
suffixIcon: IconButton(
icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
border: const OutlineInputBorder(),
),
validator: (value) {
if (value == null || value.isEmpty) return 'Please enter password';
if (value.length < 6) return 'Password must be at least 6 characters';
return null;
},
),
const SizedBox(height: 16),
TextFormField(
controller: _confirmPasswordController,
obscureText: _obscureConfirmPassword,
decoration: InputDecoration(
labelText: 'Confirm Password',
prefixIcon: const Icon(Icons.lock_outline),
suffixIcon: IconButton(
icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword)),
border: const OutlineInputBorder(),
),
validator: (value) {
if (value == null || value.isEmpty) return 'Please confirm password';
if (value != _passwordController.text) return 'Passwords do not match';
return null;
},
),
const SizedBox(height: 16),
Row(
children: [
Checkbox(
value: _agreeToTerms,
onChanged: (value) => setState(() => _agreeToTerms = value ?? false),
activeColor: const Color(0xFF6200EE)),
Expanded(
child: GestureDetector(
onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
child: const Text('I agree to the Terms and Conditions'),
))
],
),
const SizedBox(height: 24),
ElevatedButton(
onPressed: _isLoading ? null : _handleSignup,
style: ElevatedButton.styleFrom(
backgroundColor: const Color(0xFF6200EE),
padding: const EdgeInsets.symmetric(vertical: 16)),
child: _isLoading
? const CircularProgressIndicator(color: Colors.white)
    : const Text('Sign Up', style: TextStyle(fontSize: 16)),
),
const SizedBox(height: 16),
Row(children: const [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('OR')), Expanded(child: Divider())]),
const SizedBox(height: 16),
OutlinedButton.icon(
onPressed: _isLoading ? null : _handleGoogleSignup,
icon: const Icon(Icons.g_mobiledata, size: 28),
label: const Text('Sign up with Google'),
style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
),
const SizedBox(height: 24),
Row(mainAxisAlignment: MainAxisAlignment.center, children: [
const Text("Already have an account? "),
TextButton(onPressed: () => Navigator.pop(context), child: const Text('Login'))
])
],
),
),
),
),
);
}
}
