import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  Icon(Icons.privacy_tip_rounded,
                      size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'WishHive Privacy Policy',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last updated: February 2026',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _buildSection(
              theme,
              '1. Introduction',
              'Welcome to WishHive ("we", "our", or "us"). We are committed to '
                  'protecting your personal information and your right to privacy. '
                  'This Privacy Policy explains how we collect, use, disclose, and '
                  'safeguard your information when you use our WishHive mobile application '
                  '(the "App").\n\n'
                  'By using WishHive, you agree to the collection and use of information '
                  'in accordance with this policy. If you do not agree with our policies, '
                  'please do not use the App.',
            ),

            _buildSection(
              theme,
              '2. Information We Collect',
              'We collect the following types of information:\n\n'
                  '• Account Information: When you register, we collect your name, email '
                  'address, and profile picture through Firebase Authentication (Google, '
                  'Apple, or Email sign-in).\n\n'
                  '• User Content: Wishes, hive names, product links, images, notes, and '
                  'other content you create within the App.\n\n'
                  '• Social Information: Friend connections, friend requests, and shared '
                  'hive access permissions that you choose to configure.\n\n'
                  '• Device Information: Basic device identifiers for crash reporting and '
                  'analytics purposes.\n\n'
                  '• Usage Data: How you interact with the App, including features used '
                  'and time spent, to improve our services.',
            ),

            _buildSection(
              theme,
              '3. How We Use Your Information',
              'We use the information we collect to:\n\n'
                  '• Provide, maintain, and improve the App functionality.\n'
                  '• Create and manage your account.\n'
                  '• Enable social features such as friend connections and shared hives.\n'
                  '• Display wish details, product links, and associated images.\n'
                  '• Send notifications about friend requests and wish updates.\n'
                  '• Monitor and analyze usage patterns to enhance user experience.\n'
                  '• Detect, prevent, and address technical issues.',
            ),

            _buildSection(
              theme,
              '4. Data Storage & Security',
              'Your data is stored securely using Google Firebase services, including '
                  'Cloud Firestore for structured data and Firebase Storage for images. '
                  'We implement industry-standard security measures including:\n\n'
                  '• Encrypted data transmission (HTTPS/TLS).\n'
                  '• Firebase Authentication for secure sign-in.\n'
                  '• Firestore Security Rules to restrict unauthorized data access.\n'
                  '• Local image caching with secure file storage.\n\n'
                  'While we strive to use commercially acceptable means to protect your '
                  'data, no method of electronic storage is 100% secure.',
            ),

            _buildSection(
              theme,
              '5. Data Sharing & Third Parties',
              'We do not sell, trade, or rent your personal information to third parties. '
                  'Your data may be shared in limited circumstances:\n\n'
                  '• With Friends: When you share a hive or accept a friend request, '
                  'selected information (display name, profile picture, wish lists) is '
                  'visible to your approved friends.\n\n'
                  '• Service Providers: We use Firebase (Google) for authentication, '
                  'database, and storage services. Their privacy policy applies to their '
                  'handling of data.\n\n'
                  '• Legal Requirements: We may disclose information if required to do so '
                  'by law or in response to valid legal requests.',
            ),

            _buildSection(
              theme,
              '6. Your Rights & Choices',
              'You have the following rights regarding your data:\n\n'
                  '• Access & Update: You can view and update your profile information '
                  'directly within the App settings.\n\n'
                  '• Delete Account: You may request deletion of your account and '
                  'associated data by contacting us.\n\n'
                  '• Friend Management: You can remove friends, mute users, or hide '
                  'specific hives at any time.\n\n'
                  '• Privacy Controls: You control who can view or edit your hives '
                  'through the privacy settings (Public, Friends, Specific Friends, '
                  'or Private).',
            ),

            _buildSection(
              theme,
              '7. Children\'s Privacy',
              'WishHive is not intended for children under the age of 13. We do not '
                  'knowingly collect personal information from children under 13. If we '
                  'become aware that we have collected personal data from a child under '
                  '13, we will take steps to delete that information promptly.',
            ),

            _buildSection(
              theme,
              '8. Changes to This Policy',
              'We may update this Privacy Policy from time to time. We will notify you '
                  'of any changes by updating the "Last updated" date at the top of this '
                  'page. You are advised to review this Privacy Policy periodically for '
                  'any changes. Changes are effective when posted.',
            ),

            _buildSection(
              theme,
              '9. Contact Us',
              'If you have any questions or concerns about this Privacy Policy or our '
                  'data practices, please contact us at:\n\n'
                  '📧 WishHive@outlook.com\n\n'
                  'We will respond to your inquiry within a reasonable timeframe.',
            ),

            const SizedBox(height: 24),
            Center(
              child: Text(
                '© 2026 WishHive. All rights reserved.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[400],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ThemeData theme, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.6,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
