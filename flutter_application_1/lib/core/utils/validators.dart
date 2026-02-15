/// Shared form validators for Beehive.
class Validators {
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter an email';
    }
    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value.trim())) {
      return 'Please enter a valid email';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? number(String? value, [String fieldName = 'Value']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (double.tryParse(value.trim()) == null) {
      return 'Please enter a valid number';
    }
    return null;
  }

  static String? positiveNumber(String? value, [String fieldName = 'Value']) {
    final numError = number(value, fieldName);
    if (numError != null) return numError;
    if (double.parse(value!.trim()) < 0) {
      return '$fieldName must be positive';
    }
    return null;
  }
}
