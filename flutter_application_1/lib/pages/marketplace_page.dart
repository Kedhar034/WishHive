import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class MarketplacePage extends StatelessWidget {
  const MarketplacePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Lottie Animation
              Container(
                constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
                child: Lottie.asset(
                  'assets/lottie/shopping_cart.json',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.shopping_bag_outlined,
                      size: 100,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
              
              // Text Content
              Text(
                'Marketplace',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'COMING SOON',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              Text(
                'Discover & Shop',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We are building a magical place for you to\nfind items from your wishes directly within the app.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
               
              // Footer Tagline
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
                   const SizedBox(width: 8),
                   Text(
                     'Get ready for a new experience',
                     style: theme.textTheme.labelLarge?.copyWith(
                       color: theme.colorScheme.primary,
                       fontWeight: FontWeight.w500,
                     ),
                   ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
