// lib/services/gemini_triage_agent.dart

import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiTriageAgent {
  // TODO: Paste your real Google AI Studio key here
  static const String _apiKey = 'YOUR_API_KEY_HERE'; 
  
  Future<Map<String, dynamic>> analyzePayload(String survivorText) async {
    if (_apiKey == 'YOUR_API_KEY_HERE') {
      return {
        "priority": 3,
        "tag": "API KEY MISSING",
        "raw_text": survivorText,
      };
    }

    // 1. Initialize Gemini 1.5 Flash (Fastest model for triage)
    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
      // 2. Force the AI to output pure JSON so our app doesn't crash
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );

    // 3. The System Prompt
    final prompt = '''
    You are an autonomous medical triage agent operating in a disaster zone. 
    Analyze the survivor's raw text. Categorize into:
    Priority 1 (Critical/Minutes to live - e.g., severe bleeding, crush injuries, toxic gas)
    Priority 2 (Urgent/Hours to live - e.g., broken bones, feeling unwell)
    Priority 3 (Stable/Days to live - e.g., trapped but stable, safe in a void space, minor cuts, panic)
    You may use your own logic to determine priority based on the text.
    
    Respond strictly with a valid JSON object matching this schema:
    {"priority": int, "tag": "short 3-word reason, if not possible then 5-6 words"}

    Survivor text: "$survivorText"
    ''';

    try {
      print("Sending payload to Gemini API...");
      final response = await model.generateContent([Content.text(prompt)]);
      final responseText = response.text;
      
      if (responseText != null) {
        // 4. Parse the live JSON from Google's servers
        final Map<String, dynamic> jsonMap = jsonDecode(responseText);
        print("Gemini Response: $jsonMap");
        
        return {
          "priority": jsonMap['priority'] ?? 3,
          "tag": jsonMap['tag'].toString().toUpperCase() ?? "UNKNOWN STATUS",
          "raw_text": survivorText,
        };
      }
    } catch (e) {
      print("Gemini API Error: $e");
      return {
        "priority": 3,
        "tag": "NETWORK PARSE ERROR",
        "raw_text": survivorText,
      };
    }
    
    return {
      "priority": 3,
      "tag": "UNABLE TO TRIAGE",
      "raw_text": survivorText,
    };
  }
}