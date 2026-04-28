import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'map_screen.dart';
import 'radar_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  
  bool _showLoginForm = false;
  bool _isLoading = false;
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // THE OFFLINE TRICK: If Firebase finds a cached token, instantly skip the login screen!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_authService.currentUser != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const RadarScreen()),
        );
      }
    });
  }

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);
    
    String? error = await _authService.signInRescueTeam(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (error == null) {
      // Success! Route to the Radar
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const RadarScreen()),
        );
      }
    } else {
      // Failed. Show error.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        // THE FIX: Added Center and SingleChildScrollView here
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- APP LOGO & BRANDING ---
                  // ClipRRect(
                  //   borderRadius: BorderRadius.circular(20), // Optional: rounds the corners slightly
                  //   child: Image.asset(
                  //     'assets/images/lifex_logo.png',
                  //     height: 100, // Adjust this to make it larger or smaller
                  //     width: 100,
                  //     fit: BoxFit.cover,
                  //   ),
                  // ),
                  const SizedBox(height: 20),
                  const Text(
                    "L I F E X",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 8.0),
                  ),
                  const Text(
                    "ACTIVE DISASTER MESH",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey, letterSpacing: 2.0),
                  ),
                  const SizedBox(height: 80),

                  // --- SURVIVOR PATH (Zero Friction) ---
                  // NEW: Hides this block when login form is active
                  if (!_showLoginForm) ...[
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        elevation: 10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: () {
                        // Bypass everything, go straight to the beacon
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const MapScreen()),
                        );
                      },
                      child: const Text(
                        "USE AS SURVIVOR",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],

                  // --- RESCUE TEAM PATH (Auth Gated) ---
                  if (!_showLoginForm)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white, 
                        foregroundColor: Colors.black87, 
                        padding: const EdgeInsets.symmetric(vertical: 20), // Matched to 20
                        elevation: 10, // Matched to 10
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15), // Matched to 15
                        ),
                      ),
                      icon: const Icon(Icons.lock, size: 18),
                      label: const Text(
                        "PERSONNEL LOGIN", 
                        style: TextStyle(
                          fontSize: 16, // Matched to 16
                          fontWeight: FontWeight.bold, 
                          letterSpacing: 1.5
                        ),
                      ), 
                      onPressed: () => setState(() => _showLoginForm = true),
                    ),

                  // The Hidden Login Form
                  if (_showLoginForm) ...[
                    TextField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Email",
                        labelStyle: const TextStyle(color: Colors.grey),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue[400]!)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Password",
                        labelStyle: const TextStyle(color: Colors.grey),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue[400]!)),
                      ),
                    ),
                    const SizedBox(height: 30),
                    _isLoading 
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[900],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          onPressed: _handleLogin,
                          child: const Text("AUTHENTICATE", style: TextStyle(letterSpacing: 2.0)),
                        ),
                    const SizedBox(height: 15),
                    
                    // NEW: A way to back out if they clicked by accident
                    TextButton(
                      onPressed: () => setState(() {
                        _showLoginForm = false;
                        _emailController.clear();
                        _passwordController.clear();
                      }),
                      child: const Text("CANCEL", style: TextStyle(color: Colors.grey, letterSpacing: 1.5)),
                    ),
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}