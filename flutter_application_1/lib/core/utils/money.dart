import 'package:intl/intl.dart';

/// Indian grouping, so 139950 reads as ₹1,39,950 rather than ₹139,950.
final NumberFormat _inr =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Display formatting only. Nothing reads this back into a number.
String formatMoney(num amount) => _inr.format(amount);
