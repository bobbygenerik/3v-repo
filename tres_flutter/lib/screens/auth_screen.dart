import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isPhoneAuth = true;
  bool _isSignUp = false;
  bool _isLoading = false;
  
  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  Future<void> _handlePhoneAuth() async {
    final authService = context.read<AuthService>();
    
    if (authService.isVerificationPending) {
      // Verify code
      final code = _codeController.text.trim();
      if (code.isEmpty) {
        _showError('Please enter the verification code');
        return;
      }
      
      setState(() => _isLoading = true);
      final success = await authService.verifyPhoneCode(code);
      setState(() => _isLoading = false);
      
      if (!success && mounted) {
        _showError(authService.errorMessage ?? 'Verification failed');
      }
    } else {
      // Send code
      final phone = _phoneController.text.trim();
      if (phone.isEmpty) {
        _showError('Please enter your phone number');
        return;
      }
      
      // Add + prefix if missing
      final formattedPhone = phone.startsWith('+') ? phone : '+$phone';
      
      setState(() => _isLoading = true);
      final success = await authService.sendPhoneVerificationCode(formattedPhone);
      setState(() => _isLoading = false);
      
      if (!success && mounted) {
        _showError(authService.errorMessage ?? 'Failed to send code');
      }
    }
  }
  
  Future<void> _handleEmailAuth() async {
    final authService = context.read<AuthService>();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter email and password');
      return;
    }
    
    setState(() => _isLoading = true);
    
    final success = _isSignUp
        ? await authService.createAccountWithEmail(email, password)
        : await authService.signInWithEmail(email, password);
    
    setState(() => _isLoading = false);
    
    if (!success && mounted) {
      _showError(authService.errorMessage ?? 'Authentication failed');
    }
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // App Logo
                Image.asset(
                  'assets/images/logo.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 48),
                
                // Auth method toggle
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Phone'),
                      icon: Icon(Icons.phone),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Email'),
                      icon: Icon(Icons.email),
                    ),
                  ],
                  selected: {_isPhoneAuth},
                  onSelectionChanged: (Set<bool> selection) {
                    setState(() {
                      _isPhoneAuth = selection.first;
                      authService.clearError();
                    });
                  },
                ),
                const SizedBox(height: 32),
                
                // Auth form
                if (_isPhoneAuth)
                  _buildPhoneAuthForm(authService)
                else
                  _buildEmailAuthForm(),
                
                const SizedBox(height: 32),
                
                // Submit button - Full width with proper height
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _isLoading ? null : () {
                      _isPhoneAuth ? _handlePhoneAuth() : _handleEmailAuth();
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : Text(_getButtonText(authService)),
                  ),
                ),
                
                // Toggle sign up/sign in (email only)
                if (!_isPhoneAuth) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() => _isSignUp = !_isSignUp);
                      authService.clearError();
                    },
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : 'Need an account? Sign up',
                    ),
                  ),
                ],
              ], // Closing Column children
            ), // Closing Column
          ), // Closing SingleChildScrollView
        ), // Closing ConstrainedBox
      ), // Closing Center
    ), // Closing SafeArea
    ); // Closing Scaffold
  }
  
  Widget _buildPhoneAuthForm(AuthService authService) {
    if (authService.isVerificationPending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter the verification code sent to ${_phoneController.text}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Verification Code',
              hintText: '123456',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
          ),
          TextButton(
            onPressed: () async {
              authService.clearError();
              setState(() => _isLoading = true);
              await authService.sendPhoneVerificationCode(_phoneController.text);
              setState(() => _isLoading = false);
            },
            child: const Text('Resend code'),
          ),
        ],
      );
    }
    
    return TextField(
      controller: _phoneController,
      decoration: const InputDecoration(
        labelText: 'Phone Number',
        hintText: '+15551234567',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.phone),
        helperText: 'Include country code (e.g., +1 for US)',
      ),
      keyboardType: TextInputType.phone,
      autofocus: true,
    );
  }
  
  Widget _buildEmailAuthForm() {
    return Column(
      children: [
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'your@email.com',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email),
          ),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock),
          ),
          obscureText: true,
        ),
      ],
    );
  }
  
  String _getButtonText(AuthService authService) {
    if (_isPhoneAuth) {
      return authService.isVerificationPending ? 'Verify Code' : 'Send Code';
    }
    return _isSignUp ? 'Create Account' : 'Sign In';
  }
}
