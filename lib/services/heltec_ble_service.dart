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

  static const String deviceName = 'AGAKBAY-Heltec';
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

  BluetoothDevice? _device;
  BluetoothCharacteristic? _sosChar;
  BluetoothCharacteristic? _hikeInfoChar;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _locationSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  bool _isScanning = false;
  double? _lastLatitude;
  double? _lastLongitude;
  DateTime? _lastFixAt;
  String? _lastError;

  bool get isConnected =>
      _connectionState == BluetoothConnectionState.connected;
  bool get isScanning => _isScanning;
  double? get lastLatitude => _lastLatitude;
  double? get lastLongitude => _lastLongitude;
  DateTime? get lastFixAt => _lastFixAt;
  String? get lastError => _lastError;

  Future<void> connect({Duration timeout = const Duration(seconds: 12)}) async {
    if (isConnected || _isScanning) return;
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
          if (result.device.platformName == deviceName ||
              result.advertisementData.advName == deviceName) {
            if (!foundDevice.isCompleted) {
              foundDevice.complete(result.device);
            }
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        withNames: [deviceName],
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
        _lastError = 'No Heltec device found nearby. Make sure it is on.';
        notifyListeners();
        return;
      }

      _device = device;
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
      }
    }
  }

  void _onConnectionStateChanged(BluetoothConnectionState state) {
    _connectionState = state;
    if (state == BluetoothConnectionState.disconnected) {
      _sosChar = null;
      _hikeInfoChar = null;
      unawaited(_locationSub?.cancel());
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

  /// Writes an SOS trigger to the Heltec so it broadcasts the alert over
  /// LoRa even though this phone has no internet connection.
  Future<bool> sendSos() async {
    final characteristic = _sosChar;
    if (characteristic == null) {
      _lastError = 'Not connected to a Heltec device.';
      notifyListeners();
      return false;
    }
    try {
      await characteristic.write([0x01], withoutResponse: false);
      return true;
    } catch (error) {
      _lastError = 'Failed to send SOS over BLE: $error';
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
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _sosChar = null;
    _hikeInfoChar = null;
    _connectionState = BluetoothConnectionState.disconnected;
    notifyListeners();
  }
}
