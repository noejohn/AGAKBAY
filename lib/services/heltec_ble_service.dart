import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Talks BLE to a paired Heltec WiFi LoRa 32 unit running the AGAKBAY
/// firmware (see firmware/agakbay_heltec/agakbay_heltec.ino). The UUIDs
/// here must match the ones defined in that sketch exactly.
///
/// Singleton so the connection survives navigation between screens, same
/// pattern as [AgakController].
class HeltecBleService extends ChangeNotifier {
  HeltecBleService._();

  static final HeltecBleService instance = HeltecBleService._();

  // Two boards, two distinct advertised names — flashed permanently onto
  // whichever physical unit takes that role (see firmware/agakbay_heltec's
  // DEVICE_NAME). A phone connects to the name matching its OWN user's
  // role, so a hiker's phone never accidentally pairs with a nearby
  // tour guide's unit, or vice versa.
  static const String hikerDeviceName = 'AGAKBAY-Hiker';
  static const String guideDeviceName = 'AGAKBAY-TourGuide';
  static final Guid _serviceUuid = Guid(
    'd64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0001',
  );
  static final Guid _locationCharUuid = Guid(
    'd64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0002',
  );
  static final Guid _sosCharUuid = Guid(
    'd64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0003',
  );
  static final Guid _hikeInfoCharUuid = Guid(
    'd64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0004',
  );
  // Notified by the firmware when THIS board receives a neighbor's SOS
  // over LoRa — the offline hiker-to-guide relay path, no internet
  // involved anywhere in the chain.
  static final Guid _sosRelayCharUuid = Guid(
    'd64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0005',
  );
  // "I Can't Continue" — same relay shape as SOS above, but for a hiker
  // stopping partway through an active hike rather than an emergency.
  static final Guid _stopCharUuid = Guid(
    'd64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0006',
  );
  static final Guid _stopRelayCharUuid = Guid(
    'd64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0007',
  );
  // The guide's acknowledgment of an ended hike, travelling back over LoRa
  // to the hiker: the guide's phone writes it, the hiker's board notifies.
  static final Guid _stopAckCharUuid = Guid(
    'd64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0008',
  );
  static final Guid _stopAckRelayCharUuid = Guid(
    'd64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0009',
  );

  BluetoothDevice? _device;
  String? _lastDeviceId;
  String? _lastDeviceName;
  BluetoothCharacteristic? _sosChar;
  BluetoothCharacteristic? _stopChar;
  BluetoothCharacteristic? _stopAckChar;
  BluetoothCharacteristic? _hikeInfoChar;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _locationSub;
  StreamSubscription<List<int>>? _sosRelaySub;
  StreamSubscription<List<int>>? _stopRelaySub;
  StreamSubscription<List<int>>? _stopAckRelaySub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  bool _isScanning = false;
  double? _lastLatitude;
  double? _lastLongitude;
  DateTime? _lastFixAt;
  String? _lastError;

  // The most recent SOS relayed to this board over LoRa from another
  // Heltec — set with zero internet/cellular signal involved.
  String? _lastRelaySenderName;
  String? _lastRelayReason;
  bool _lastRelayHasFix = false;
  double? _lastRelayLatitude;
  double? _lastRelayLongitude;
  DateTime? _lastRelayAt;

  bool get isConnected =>
      _connectionState == BluetoothConnectionState.connected;
  String? get deviceId => _device?.remoteId.str ?? _lastDeviceId;
  String? get deviceName => _lastDeviceName;
  bool get isScanning => _isScanning;
  double? get lastLatitude => _lastLatitude;
  double? get lastLongitude => _lastLongitude;
  DateTime? get lastFixAt => _lastFixAt;
  String? get lastError => _lastError;
  String? get lastRelaySenderName => _lastRelaySenderName;
  // Null when the sender's firmware/app predates SOS reasons.
  String? get lastRelayReason => _lastRelayReason;
  // False means the sender's device had no GPS fix yet when it sent this
  // SOS — treat lastRelayLatitude/Longitude as meaningless (0,0) in that
  // case, never as a real location.
  bool get lastRelayHasFix => _lastRelayHasFix;
  double? get lastRelayLatitude => _lastRelayLatitude;
  double? get lastRelayLongitude => _lastRelayLongitude;
  DateTime? get lastRelayAt => _lastRelayAt;

  // The most recent "I Can't Continue" relayed to this board over LoRa —
  // same no-internet-involved path as the SOS relay above.
  String? _lastStopRelaySenderName;
  String? _lastStopRelayReason;
  DateTime? _lastStopRelayAt;
  String? get lastStopRelaySenderName => _lastStopRelaySenderName;
  String? get lastStopRelayReason => _lastStopRelayReason;
  DateTime? get lastStopRelayAt => _lastStopRelayAt;

  // Hiker side: the guide's acknowledgment heard over LoRa.
  String? _lastStopAckName;
  DateTime? _lastStopAckAt;

  // Guide side: hikers this phone already acknowledged over the device, so
  // the offline card can show it as done without any internet round trip.
  final Set<String> _stopAcksSent = <String>{};

  static String _nameKey(String name) => name.trim().toLowerCase();

  /// True if the guide's acknowledgment for [hikerName] arrived over LoRa
  /// after [since] (when this hiker ended their hike).
  bool stopAcknowledgedOverLoraFor(String hikerName, {DateTime? since}) {
    final name = _lastStopAckName;
    final at = _lastStopAckAt;
    if (name == null || at == null) return false;
    if (_nameKey(name) != _nameKey(hikerName)) return false;
    return since == null || at.isAfter(since);
  }

  bool stopAckSentFor(String hikerName) =>
      _stopAcksSent.contains(_nameKey(hikerName));

  /// [isGuide] picks which physical unit's name to scan for — a tour
  /// guide's phone must never pair with a hiker's device, or vice versa.
  Future<void> connect({
    required bool isGuide,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (isConnected || _isScanning) return;
    final targetName = isGuide ? guideDeviceName : hikerDeviceName;
    _lastError = null;
    if (!await FlutterBluePlus.isSupported) {
      _lastError = 'This phone does not support Bluetooth Low Energy.';
      notifyListeners();
      return;
    }

    _isScanning = true;
    notifyListeners();

    try {
      final foundDevice = Completer<BluetoothDevice?>();

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          if (result.device.platformName == targetName ||
              result.advertisementData.advName == targetName) {
            final advertisedName = result.advertisementData.advName.trim();
            final platformName = result.device.platformName.trim();
            _lastDeviceName = advertisedName.isNotEmpty
                ? advertisedName
                : platformName;
            if (!foundDevice.isCompleted) {
              foundDevice.complete(result.device);
            }
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        withNames: [targetName],
        timeout: timeout,
      );

      final device = await foundDevice.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _isScanning = false;

      if (device == null) {
        _lastError = 'No $targetName found nearby. Make sure it is on.';
        notifyListeners();
        return;
      }

      _device = device;
      _lastDeviceId = device.remoteId.str;
      _connectionSub = device.connectionState.listen(_onConnectionStateChanged);
      await device.connect(timeout: timeout);
      await _discoverCharacteristics(device);
    } catch (error) {
      _lastError = 'Could not connect to the Heltec device: $error';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> _discoverCharacteristics(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final service = services.firstWhere(
      (service) => service.uuid == _serviceUuid,
      orElse: () => throw StateError('AGAKBAY service not found on device.'),
    );

    for (final characteristic in service.characteristics) {
      if (characteristic.uuid == _locationCharUuid) {
        await characteristic.setNotifyValue(true);
        _locationSub = characteristic.lastValueStream.listen(_onLocationData);
      } else if (characteristic.uuid == _sosCharUuid) {
        _sosChar = characteristic;
      } else if (characteristic.uuid == _hikeInfoCharUuid) {
        _hikeInfoChar = characteristic;
      } else if (characteristic.uuid == _sosRelayCharUuid) {
        await characteristic.setNotifyValue(true);
        _sosRelaySub = characteristic.lastValueStream.listen(_onSosRelayData);
      } else if (characteristic.uuid == _stopCharUuid) {
        _stopChar = characteristic;
      } else if (characteristic.uuid == _stopRelayCharUuid) {
        await characteristic.setNotifyValue(true);
        _stopRelaySub = characteristic.lastValueStream.listen(_onStopRelayData);
      } else if (characteristic.uuid == _stopAckCharUuid) {
        _stopAckChar = characteristic;
      } else if (characteristic.uuid == _stopAckRelayCharUuid) {
        await characteristic.setNotifyValue(true);
        _stopAckRelaySub = characteristic.lastValueStream.listen(
          _onStopAckRelayData,
        );
      }
    }
  }

  void _onConnectionStateChanged(BluetoothConnectionState state) {
    _connectionState = state;
    if (state == BluetoothConnectionState.disconnected) {
      _sosChar = null;
      _stopChar = null;
      _stopAckChar = null;
      _hikeInfoChar = null;
      unawaited(_locationSub?.cancel());
      unawaited(_sosRelaySub?.cancel());
      unawaited(_stopRelaySub?.cancel());
      unawaited(_stopAckRelaySub?.cancel());
    }
    notifyListeners();
  }

  void _onLocationData(List<int> bytes) {
    if (bytes.isEmpty) return;
    // Firmware sends "lat,lon" as plain ASCII, e.g. "14.599512,120.984222".
    final text = utf8.decode(bytes, allowMalformed: true);
    final parts = text.split(',');
    if (parts.length != 2) return;
    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    if (lat == null || lon == null) return;
    _lastLatitude = lat;
    _lastLongitude = lon;
    _lastFixAt = DateTime.now();
    notifyListeners();
  }

  /// Firmware sends "hikerName|hasFix|lat|lon|reason" the moment this board
  /// receives an SOS relayed over LoRa from another Heltec — this is the
  /// entire offline hiker-to-guide path arriving with zero internet
  /// involved. hasFix is "0" or "1": the sender's device may not have had
  /// a GPS lock yet, in which case lat/lon are meaningless placeholders
  /// (0,0) that must not be shown or plotted as a real location. reason is
  /// missing entirely when relayed from older firmware.
  void _onSosRelayData(List<int> bytes) {
    if (bytes.isEmpty) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    final parts = text.split('|');
    if (parts.length < 4) return;
    final lat = double.tryParse(parts[2]);
    final lon = double.tryParse(parts[3]);
    if (lat == null || lon == null) return;
    final reason = parts.length > 4 ? parts.sublist(4).join('|').trim() : '';
    _lastRelayReason = reason.isEmpty ? null : reason;
    _lastRelaySenderName = parts[0];
    _lastRelayHasFix = parts[1] == '1';
    _lastRelayLatitude = lat;
    _lastRelayLongitude = lon;
    _lastRelayAt = DateTime.now();
    notifyListeners();
  }

  /// Firmware sends "hikerName|reason" the moment this board receives an
  /// "I Can't Continue" relayed over LoRa from another Heltec — same
  /// no-internet path as the SOS relay above, for a hiker stopping
  /// partway through an active hike rather than an emergency.
  void _onStopRelayData(List<int> bytes) {
    if (bytes.isEmpty) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    final separator = text.indexOf('|');
    if (separator == -1) return;
    _lastStopRelaySenderName = text.substring(0, separator);
    _lastStopRelayReason = text.substring(separator + 1);
    _lastStopRelayAt = DateTime.now();
    notifyListeners();
  }

  /// Firmware sends just "hikerName" when this board hears the guide's
  /// "ACK|hikerName" over LoRa. Every board in range hears it — the hiker
  /// screen decides whether the name is its own (see
  /// [stopAcknowledgedOverLoraFor]).
  void _onStopAckRelayData(List<int> bytes) {
    if (bytes.isEmpty) return;
    final name = utf8.decode(bytes, allowMalformed: true).trim();
    if (name.isEmpty) return;
    _lastStopAckName = name;
    _lastStopAckAt = DateTime.now();
    notifyListeners();
  }

  /// Guide side: tells [hikerName]'s device over LoRa that the guide saw
  /// their ended-hike message, for when neither side has signal.
  Future<bool> sendStopAck({required String hikerName}) async {
    final characteristic = _stopAckChar;
    if (characteristic == null) return false;
    try {
      await characteristic.write(
        utf8.encode('ACK|$hikerName'),
        withoutResponse: false,
      );
      _stopAcksSent.add(_nameKey(hikerName));
      notifyListeners();
      return true;
    } catch (error) {
      _lastError = 'Failed to send acknowledgment over BLE: $error';
      notifyListeners();
      return false;
    }
  }

  /// Writes an SOS trigger to the Heltec so it broadcasts the alert over
  /// LoRa even though this phone has no internet connection. Coordinates
  /// come from THIS phone's own GPS, not the device's — the Heltec's
  /// onboard GPS module is unreliable on the current hardware, so the
  /// device just relays these numbers over LoRa rather than measuring
  /// its own location. The phone's GPS works with zero signal too, so
  /// this doesn't compromise the "no internet needed" requirement.
  ///
  /// [reason] goes last in the payload so the firmware's fixed-size LoRa
  /// buffer can only ever truncate it, never the coordinates before it.
  Future<bool> sendSos({
    String hikerName = 'Hiker',
    required double latitude,
    required double longitude,
    required String reason,
  }) async {
    final characteristic = _sosChar;
    if (characteristic == null) {
      _lastError = 'Not connected to a Heltec device.';
      notifyListeners();
      return false;
    }
    try {
      await characteristic.write(
        utf8.encode(
          'SOS|$hikerName|${latitude.toStringAsFixed(6)}|${longitude.toStringAsFixed(6)}|$reason',
        ),
        withoutResponse: false,
      );
      return true;
    } catch (error) {
      _lastError = 'Failed to send SOS over BLE: $error';
      notifyListeners();
      return false;
    }
  }

  /// Writes an "I Can't Continue" trigger to the Heltec so it relays the
  /// stop reason over LoRa to the guide's device, the same offline path
  /// [sendSos] uses. Not an emergency — see HikeRoomService.stopHiking.
  Future<bool> sendStop({
    String hikerName = 'Hiker',
    required String reason,
  }) async {
    final characteristic = _stopChar;
    if (characteristic == null) {
      _lastError = 'Not connected to a Heltec device.';
      notifyListeners();
      return false;
    }
    try {
      await characteristic.write(
        utf8.encode('STOP|$hikerName|$reason'),
        withoutResponse: false,
      );
      return true;
    } catch (error) {
      _lastError = 'Failed to send stop-hiking over BLE: $error';
      notifyListeners();
      return false;
    }
  }

  /// Sends the current hike's guide and mountain name — for a hiker's
  /// device, so its OLED can show who's guiding and where, even with no
  /// one looking at the phone.
  Future<bool> sendHikerInfo({
    required String guideName,
    required String mountainName,
  }) {
    return _writeHikeInfo('H|$guideName|$mountainName');
  }

  /// Sends the mountain name and live participant count — for a tour
  /// guide's device, whose OLED shows the group instead of a single guide
  /// name (they already know who they are).
  Future<bool> sendGuideInfo({
    required String mountainName,
    required int participantCount,
  }) {
    return _writeHikeInfo('G|$mountainName|$participantCount');
  }

  Future<bool> _writeHikeInfo(String payload) async {
    final characteristic = _hikeInfoChar;
    if (characteristic == null) return false;
    try {
      await characteristic.write(utf8.encode(payload), withoutResponse: false);
      return true;
    } catch (error) {
      _lastError = 'Failed to send hike info over BLE: $error';
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _locationSub?.cancel();
    await _sosRelaySub?.cancel();
    await _stopRelaySub?.cancel();
    await _stopAckRelaySub?.cancel();
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _sosChar = null;
    _stopChar = null;
    _stopAckChar = null;
    _hikeInfoChar = null;
    _connectionState = BluetoothConnectionState.disconnected;
    notifyListeners();
  }
}
