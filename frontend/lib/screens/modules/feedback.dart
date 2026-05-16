import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _formKey = GlobalKey<FormState>();
  String feedback = '';
  int rating = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  @override
  Widget build(BuildContext context) {
    final user = currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Feedback")),
        body: const Center(
          child: Text("Please log in to submit feedback."),
        ),
      );
    }

    final displayName = user.displayName ?? "Anonymous";
    final email = user.email ?? "No Email";
    final uid = user.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("Feedback"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Hello, $displayName", style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 16),

                TextFormField(
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: "Your Feedback",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please write your feedback";
                    }
                    return null;
                  },
                  onSaved: (value) => feedback = value!,
                ),
                const SizedBox(height: 16),

                const Text("Rate Experience", style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        size: 32,
                        color: Colors.amber,
                      ),
                      onPressed: () => setState(() => rating = index + 1),
                    );
                  }),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    child: const Text("Submit Feedback"),
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        _formKey.currentState!.save();

                        await _firestore.collection('feedback').add({
                          'userId': uid,
                          'name': displayName,
                          'email': email,
                          'feedback': feedback,
                          'rating': rating,
                          'timestamp': FieldValue.serverTimestamp(),
                        });
                        if (!context.mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Thank you for your feedback!")),
                        );

                        _formKey.currentState!.reset();
                        setState(() => rating = 0);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
