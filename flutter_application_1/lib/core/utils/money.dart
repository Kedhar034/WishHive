import 'package:intl/intl.dart';

/// Indian grouping, so 139950 reads as ₹1,39,950 rather than ₹139,950.
final NumberFormat _inr =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Display formatting only. Nothing reads this back into a number.
String formatMoney(num amount) => _inr.format(amount);

/// "3 Oct", or "3 Oct 2025" once it is from another year, for "as of" labels.
String formatPriceDate(DateTime date) {
  final now = DateTime.now();
  return DateFormat(date.year == now.year ? 'd MMM' : 'd MMM y').format(date);
}

/// A fetched price is a snapshot of the store on that day.
bool isPriceStale(DateTime? fetchedAt) =>
    fetchedAt != null &&
    DateTime.now().difference(fetchedAt) > const Duration(hours: 24);
