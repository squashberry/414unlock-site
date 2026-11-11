/// Authoritative database of Apple device hardware identifiers.
/// Maps CPID (Chip ID), BDID (Board ID), and ProductType to iPhone models
/// and Apple Silicon architectures.
///
/// This database allows instant identification of activation-locked iPhones,
/// recovery-mode iPhones, and DFU-mode iPhones without requiring device pairing,
/// passcode entry, or user trust.
class AppleDeviceDatabase {
  AppleDeviceDatabase._();

  /// Maps 4-digit hex CPID (e.g. "8110") or integer CPID to Apple Silicon architecture name
  static const Map<String, String> cpidToChipFamily = {
    '8960': 'Apple A7',
    '7000': 'Apple A8',
    '7001': 'Apple A8X',
    '8000': 'Apple A9 (Samsung)',
    '8003': 'Apple A9 (TSMC)',
    '8001': 'Apple A9X',
    '8010': 'Apple A10 Fusion',
    '8011': 'Apple A10X Fusion',
    '8012': 'Apple T2',
    '8015': 'Apple A11 Bionic',
    '8020': 'Apple A12 Bionic',
    '8027': 'Apple A12X/A12Z Bionic',
    '8030': 'Apple A13 Bionic',
    '8101': 'Apple A14 Bionic',
    '8103': 'Apple M1',
    '8110': 'Apple A15 Bionic',
    '8112': 'Apple M2',
    '8120': 'Apple A16 Bionic',
    '8122': 'Apple M3',
    '8130': 'Apple A17 Pro',
    '8140': 'Apple A18 / A18 Pro',
  };

  /// Composite key of "$cpid:$bdid" in uppercase hex -> ProductType (e.g. "8110:0A" -> "iPhone14,5")
  static const Map<String, String> cpidBdidToProductType = {
    // A7 (8960)
    '8960:00': 'iPhone6,1', // iPhone 5s (GSM)
    '8960:02': 'iPhone6,2', // iPhone 5s (Global)

    // A8 (7000)
    '7000:00': 'iPhone7,1', // iPhone 6 Plus
    '7000:02': 'iPhone7,2', // iPhone 6
    '7000:06': 'iPod7,1',   // iPod touch 6th gen

    // A9 (8000 / 8003)
    '8000:00': 'iPhone8,1', // iPhone 6s
    '8003:00': 'iPhone8,1', // iPhone 6s
    '8000:02': 'iPhone8,2', // iPhone 6s Plus
    '8003:02': 'iPhone8,2', // iPhone 6s Plus
    '8000:04': 'iPhone8,4', // iPhone SE 1st gen
    '8003:04': 'iPhone8,4', // iPhone SE 1st gen

    // A10 (8010)
    '8010:00': 'iPhone9,1', // iPhone 7 (Global)
    '8010:01': 'iPhone9,2', // iPhone 7 Plus (Global)
    '8010:02': 'iPhone9,3', // iPhone 7 (GSM)
    '8010:03': 'iPhone9,4', // iPhone 7 Plus (GSM)
    '8010:08': 'iPad7,5',   // iPad 6th gen
    '8010:09': 'iPad7,6',   // iPad 6th gen
    '8010:0A': 'iPad7,11',  // iPad 7th gen
    '8010:0B': 'iPad7,12',  // iPad 7th gen

    // A11 (8015)
    '8015:00': 'iPhone10,1', // iPhone 8 (Global)
    '8015:02': 'iPhone10,2', // iPhone 8 Plus (Global)
    '8015:04': 'iPhone10,3', // iPhone X (Global)
    '8015:06': 'iPhone10,6', // iPhone X (GSM)
    '8015:08': 'iPhone10,4', // iPhone 8 (GSM)
    '8015:0A': 'iPhone10,5', // iPhone 8 Plus (GSM)

    // A12 (8020)
    '8020:00': 'iPhone11,2', // iPhone XS
    '8020:02': 'iPhone11,4', // iPhone XS Max
    '8020:04': 'iPhone11,6', // iPhone XS Max (China)
    '8020:06': 'iPhone11,8', // iPhone XR
    '8020:08': 'iPad11,3',   // iPad Air 3
    '8020:0A': 'iPad11,4',   // iPad Air 3
    '8020:0C': 'iPad11,1',   // iPad mini 5
    '8020:0E': 'iPad11,2',   // iPad mini 5
    '8020:1A': 'iPad11,6',   // iPad 8th gen
    '8020:1B': 'iPad11,7',   // iPad 8th gen

    // A13 (8030)
    '8030:00': 'iPhone12,3', // iPhone 11 Pro
    '8030:02': 'iPhone12,5', // iPhone 11 Pro Max
    '8030:04': 'iPhone12,1', // iPhone 11
    '8030:06': 'iPhone12,8', // iPhone SE 2nd gen
    '8030:1A': 'iPad12,1',   // iPad 9th gen
    '8030:1B': 'iPad12,2',   // iPad 9th gen

    // A14 (8101)
    '8101:00': 'iPhone13,4', // iPhone 12 Pro Max
    '8101:02': 'iPhone13,1', // iPhone 12 mini
    '8101:04': 'iPhone13,2', // iPhone 12
    '8101:06': 'iPhone13,3', // iPhone 12 Pro
    '8101:08': 'iPad13,1',   // iPad Air 4
    '8101:0A': 'iPad13,2',   // iPad Air 4
    '8101:10': 'iPad13,18',  // iPad 10th gen
    '8101:12': 'iPad13,19',  // iPad 10th gen

    // A15 (8110)
    '8110:02': 'iPhone14,2', // iPhone 13 Pro
    '8110:04': 'iPhone14,3', // iPhone 13 Pro Max
    '8110:08': 'iPhone14,4', // iPhone 13 mini
    '8110:0A': 'iPhone14,5', // iPhone 13
    '8110:0C': 'iPhone14,6', // iPhone SE 3rd gen
    '8110:18': 'iPhone14,7', // iPhone 14
    '8110:1A': 'iPhone14,8', // iPhone 14 Plus
    '8110:10': 'iPad14,1',   // iPad mini 6
    '8110:12': 'iPad14,2',   // iPad mini 6

    // A16 (8120)
    '8120:00': 'iPhone15,2', // iPhone 14 Pro
    '8120:02': 'iPhone15,3', // iPhone 14 Pro Max
    '8120:04': 'iPhone15,4', // iPhone 15
    '8120:06': 'iPhone15,5', // iPhone 15 Plus

    // A17 Pro (8130)
    '8130:02': 'iPhone16,1', // iPhone 15 Pro
    '8130:04': 'iPhone16,2', // iPhone 15 Pro Max

    // A18 / A18 Pro (8140)
    '8140:00': 'iPhone17,3', // iPhone 16
    '8140:02': 'iPhone17,4', // iPhone 16 Plus
    '8140:04': 'iPhone17,1', // iPhone 16 Pro
    '8140:06': 'iPhone17,2', // iPhone 16 Pro Max
  };

  /// Maps ProductType to friendly consumer name
  static const Map<String, String> productTypeToName = {
    // iPhone 16
    'iPhone17,1': 'iPhone 16 Pro',
    'iPhone17,2': 'iPhone 16 Pro Max',
    'iPhone17,3': 'iPhone 16',
    'iPhone17,4': 'iPhone 16 Plus',

    // iPhone 15
    'iPhone16,1': 'iPhone 15 Pro',
    'iPhone16,2': 'iPhone 15 Pro Max',
    'iPhone15,4': 'iPhone 15',
    'iPhone15,5': 'iPhone 15 Plus',

    // iPhone 14
    'iPhone15,2': 'iPhone 14 Pro',
    'iPhone15,3': 'iPhone 14 Pro Max',
    'iPhone14,7': 'iPhone 14',
    'iPhone14,8': 'iPhone 14 Plus',

    // iPhone 13
    'iPhone14,2': 'iPhone 13 Pro',
    'iPhone14,3': 'iPhone 13 Pro Max',
    'iPhone14,4': 'iPhone 13 mini',
    'iPhone14,5': 'iPhone 13',

    // iPhone 12
    'iPhone13,1': 'iPhone 12 mini',
    'iPhone13,2': 'iPhone 12',
    'iPhone13,3': 'iPhone 12 Pro',
    'iPhone13,4': 'iPhone 12 Pro Max',

    // iPhone 11
    'iPhone12,1': 'iPhone 11',
    'iPhone12,3': 'iPhone 11 Pro',
    'iPhone12,5': 'iPhone 11 Pro Max',

    // iPhone SE
    'iPhone8,4': 'iPhone SE (1st gen)',
    'iPhone12,8': 'iPhone SE (2nd gen)',
    'iPhone14,6': 'iPhone SE (3rd gen)',

    // iPhone X / XS / XR
    'iPhone11,2': 'iPhone XS',
    'iPhone11,4': 'iPhone XS Max',
    'iPhone11,6': 'iPhone XS Max',
    'iPhone11,8': 'iPhone XR',
    'iPhone10,3': 'iPhone X',
    'iPhone10,6': 'iPhone X',

    // iPhone 8 / 7 / 6s / 6 / 5s
    'iPhone10,1': 'iPhone 8',
    'iPhone10,4': 'iPhone 8',
    'iPhone10,2': 'iPhone 8 Plus',
    'iPhone10,5': 'iPhone 8 Plus',
    'iPhone9,1': 'iPhone 7',
    'iPhone9,3': 'iPhone 7',
    'iPhone9,2': 'iPhone 7 Plus',
    'iPhone9,4': 'iPhone 7 Plus',
    'iPhone8,1': 'iPhone 6s',
    'iPhone8,2': 'iPhone 6s Plus',
    'iPhone7,1': 'iPhone 6 Plus',
    'iPhone7,2': 'iPhone 6',
    'iPhone6,1': 'iPhone 5s',
    'iPhone6,2': 'iPhone 5s',

    // iPads
    'iPad14,1': 'iPad mini 6 (Wi-Fi)',
    'iPad14,2': 'iPad mini 6 (Cellular)',
    'iPad13,18': 'iPad 10th gen (Wi-Fi)',
    'iPad13,19': 'iPad 10th gen (Cellular)',
    'iPad13,1': 'iPad Air 4 (Wi-Fi)',
    'iPad13,2': 'iPad Air 4 (Cellular)',
    'iPad12,1': 'iPad 9th gen (Wi-Fi)',
    'iPad12,2': 'iPad 9th gen (Cellular)',
    'iPad11,6': 'iPad 8th gen (Wi-Fi)',
    'iPad11,7': 'iPad 8th gen (Cellular)',
    'iPad11,3': 'iPad Air 3 (Wi-Fi)',
    'iPad11,4': 'iPad Air 3 (Cellular)',
    'iPad11,1': 'iPad mini 5 (Wi-Fi)',
    'iPad11,2': 'iPad mini 5 (Cellular)',
    'iPad7,5': 'iPad 6th gen (Wi-Fi)',
    'iPad7,6': 'iPad 6th gen (Cellular)',
    'iPad7,11': 'iPad 7th gen (Wi-Fi)',
    'iPad7,12': 'iPad 7th gen (Cellular)',
  };

  /// Maps ProductType to chip family label
  static const Map<String, String> productTypeToChipFamily = {
    'iPhone17,1': 'Apple A18 Pro',
    'iPhone17,2': 'Apple A18 Pro',
    'iPhone17,3': 'Apple A18',
    'iPhone17,4': 'Apple A18',

    'iPhone16,1': 'Apple A17 Pro',
    'iPhone16,2': 'Apple A17 Pro',
    'iPhone15,4': 'Apple A16 Bionic',
    'iPhone15,5': 'Apple A16 Bionic',

    'iPhone15,2': 'Apple A16 Bionic',
    'iPhone15,3': 'Apple A16 Bionic',
    'iPhone14,7': 'Apple A15 Bionic',
    'iPhone14,8': 'Apple A15 Bionic',

    'iPhone14,2': 'Apple A15 Bionic',
    'iPhone14,3': 'Apple A15 Bionic',
    'iPhone14,4': 'Apple A15 Bionic',
    'iPhone14,5': 'Apple A15 Bionic',

    'iPhone13,1': 'Apple A14 Bionic',
    'iPhone13,2': 'Apple A14 Bionic',
    'iPhone13,3': 'Apple A14 Bionic',
    'iPhone13,4': 'Apple A14 Bionic',

    'iPhone12,1': 'Apple A13 Bionic',
    'iPhone12,3': 'Apple A13 Bionic',
    'iPhone12,5': 'Apple A13 Bionic',
    'iPhone12,8': 'Apple A13 Bionic',

    'iPhone14,6': 'Apple A15 Bionic',

    'iPhone11,2': 'Apple A12 Bionic',
    'iPhone11,4': 'Apple A12 Bionic',
    'iPhone11,6': 'Apple A12 Bionic',
    'iPhone11,8': 'Apple A12 Bionic',
    'iPhone10,3': 'Apple A11 Bionic',
    'iPhone10,6': 'Apple A11 Bionic',
    'iPhone10,1': 'Apple A11 Bionic',
    'iPhone10,4': 'Apple A11 Bionic',
    'iPhone10,2': 'Apple A11 Bionic',
    'iPhone10,5': 'Apple A11 Bionic',
    'iPhone9,1': 'Apple A10 Fusion',
    'iPhone9,3': 'Apple A10 Fusion',
    'iPhone9,2': 'Apple A10 Fusion',
    'iPhone9,4': 'Apple A10 Fusion',
    'iPhone8,1': 'Apple A9',
    'iPhone8,2': 'Apple A9',
    'iPhone8,4': 'Apple A9',
  };

  /// Resolve product name from ProductType
  static String mapProductType(String rawProductType) {
    final clean = rawProductType.trim();
    if (productTypeToName.containsKey(clean)) {
      return productTypeToName[clean]!;
    }
    if (clean.toLowerCase().startsWith('iphone')) {
      return 'Apple iPhone ($clean)';
    }
    if (clean.toLowerCase().startsWith('ipad')) {
      return 'Apple iPad ($clean)';
    }
    return 'Apple Device ($clean)';
  }

  /// Resolve ProductType from CPID and BDID (e.g. from Recovery or DFU descriptor)
  static String? lookupProductTypeByCpidBdid({
    required String cpidHex,
    required String bdidHex,
  }) {
    final cpidClean = cpidHex.replaceAll('0x', '').toUpperCase().padLeft(4, '0');
    final bdidClean = bdidHex.replaceAll('0x', '').toUpperCase().padLeft(2, '0');
    final key = '$cpidClean:$bdidClean';
    return cpidBdidToProductType[key];
  }

  /// Resolve Apple Silicon chip architecture by CPID hex (e.g. "8110" -> "Apple A15 Bionic")
  static String? lookupChipFamilyByCpid(String cpidHex) {
    final cpidClean = cpidHex.replaceAll('0x', '').toUpperCase().padLeft(4, '0');
    return cpidToChipFamily[cpidClean];
  }

  /// Resolve chip family by ProductType (e.g. "iPhone14,5" -> "Apple A15 Bionic")
  static String? lookupChipFamilyByProductType(String productType) {
    final clean = productType.trim();
    return productTypeToChipFamily[clean];
  }
}
