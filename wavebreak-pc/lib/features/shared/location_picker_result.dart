import '../../services/core_api/models.dart';

/// What the location picker (Home's dropdown, or an equivalent inline
/// picker) resolved to. Actions that need their own dialog/sheet (share,
/// add-link) are returned as data here rather than invoked directly from
/// inside the picker overlay — opening a second overlay while the first is
/// still closing races the first one's removal and can render behind it.
/// The caller should act on this only *after* the picker has fully closed,
/// using its own stable BuildContext.
class LocationPickerResult {
  const LocationPickerResult._({
    this.selected,
    this.addCustom = false,
    this.shareTitle,
    this.shareLink,
  });

  const LocationPickerResult.select(LocationItem item) : this._(selected: item);
  const LocationPickerResult.addCustom() : this._(addCustom: true);
  const LocationPickerResult.share({required String title, required String link})
      : this._(shareTitle: title, shareLink: link);

  final LocationItem? selected;
  final bool addCustom;
  final String? shareTitle;
  final String? shareLink;
}
