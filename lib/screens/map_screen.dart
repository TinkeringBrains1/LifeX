import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sensors_plus/sensors_plus.dart'; 
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; 
import '../services/firestore_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  StreamSubscription<BluetoothAdapterState>? _btStateSubscription; 
  late GoogleMapController mapController;
  final FirestoreService _dbService = FirestoreService();
  static const platform = MethodChannel('com.lifex/ble_radio');

  final LatLng _center = const LatLng(17.3850, 78.4867); 

  bool _isOffline = true;
  bool _isBroadcastingBle = false; // NEW: Tracks hardware radio state
  double _currentPressure = 1013.25; 
  
  final TextEditingController _messageController = TextEditingController();
  int _wordCount = 0;
  
  late StreamSubscription<List<ConnectivityResult>> _networkSubscription;
  StreamSubscription<BarometerEvent>? _barometerSubscription;

  @override
  void initState() {
    super.initState();
    _startHardwareSensors();

    // NEW: Listen to Bluetooth Hardware State
    _btStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        if (_isBroadcastingBle) {
           // If they turn BT off manually, update the UI and stop the beacon
           setState(() => _isBroadcastingBle = false);
           platform.invokeMethod('stopBeacon');
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bluetooth disabled. Beacon stopped."), backgroundColor: Colors.red));
        }
      }
    });
  }

  @override
  void dispose() {
    _btStateSubscription?.cancel();
    _networkSubscription.cancel();
    _barometerSubscription?.cancel();
    _messageController.dispose();
    if (_isBroadcastingBle) platform.invokeMethod('stopBeacon');
    super.dispose();
  }

  void _startHardwareSensors() {
    _barometerSubscription = barometerEventStream().listen((BarometerEvent event) {
      _currentPressure = event.pressure; 
    });

    _networkSubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      if (!results.contains(ConnectivityResult.none)) {
        setState(() => _isOffline = false);
        _executeMacroSync();
      } else {
        setState(() => _isOffline = true);
      }
    });
  }

  Future<void> _executeMacroSync() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      }

      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('lifex_device_id');
      if (deviceId == null) {
        deviceId = const Uuid().v4();
        await prefs.setString('lifex_device_id', deviceId); 
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      await _dbService.syncMacroLocation(
        deviceId: deviceId,
        lat: position.latitude,
        lng: position.longitude,
        pressureHpa: _currentPressure, 
        message: _messageController.text.trim(),
      );

      FirebaseFirestore.instance.collection('macro_rescues').doc(deviceId).snapshots().listen((doc) {
        if (doc.exists && doc.data()!['rescue_incoming'] == true) {
           if (mounted) {
             showDialog(
               context: context,
               barrierDismissible: false, 
               builder: (context) => AlertDialog(
                 backgroundColor: Colors.greenAccent[700],
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                 title: const Text("RESCUE TEAM NEARBY", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 22)),
                 content: const Text("A responder has detected your signal. Stay calm.", style: TextStyle(color: Colors.black, fontSize: 16)),
               ),
             );
           }
        }
      });
    } catch (e) {
      print("Watchdog Error: $e");
    }
  }

  Future<bool> _requestRadioPermissions() async {
    // 1. Isolate the Notification Request
    var notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      notifStatus = await Permission.notification.request();
      
      // If the OS still blocks it, we force the Settings page open
      if (notifStatus.isDenied || notifStatus.isPermanentlyDenied) {
        print("LifeX: Notification permission blocked. Forcing settings open.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("We need Notifications to keep the radio alive in the background! Opening Settings..."), 
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            )
          );
        }
        // Wait for the snackbar to be read, then open Android Settings
        await Future.delayed(const Duration(seconds: 2));
        await openAppSettings(); 
        return false; // Stop the broadcast attempt until they fix it
      }
    }

    // 2. Now request the Hardware Radios safely
    Map<Permission, PermissionStatus> hardwareStatuses = await [
      Permission.bluetoothAdvertise, 
      Permission.bluetoothConnect, 
      Permission.bluetoothScan, 
      Permission.location,
    ].request();
    
    bool allGranted = true;
    hardwareStatuses.forEach((permission, status) {
      print("LifeX Hardware Check -> $permission: $status");
      if (!status.isGranted) {
        allGranted = false;
      }
    });

    return allGranted; 
  }

  // NEW: Dedicated function strictly for BLE hardware control
  Future<void> _toggleBleBroadcast() async {
    if (_isBroadcastingBle) {
      try {
        await platform.invokeMethod('stopBeacon'); // Tells Android to kill the radio
        setState(() => _isBroadcastingBle = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("BLE Broadcast Stopped."), backgroundColor: Colors.grey));
      } catch (e) {
        print(e);
      }
      return;
    }

    setState(() => _isBroadcastingBle = true);

    bool hasPermissions = await _requestRadioPermissions();
    if (!hasPermissions) {
      setState(() => _isBroadcastingBle = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Radio permissions denied!"), backgroundColor: Colors.red));
      return; 
    }

    // Hardware verification logic moved here
    if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.off) {
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          setState(() => _isBroadcastingBle = false);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please manually turn on Bluetooth to broadcast!"), backgroundColor: Colors.red));
          return;
        }
      } else {
        setState(() => _isBroadcastingBle = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please turn on Bluetooth in Settings to broadcast!"), backgroundColor: Colors.red));
        return;
      }
    }

    try {
      final String result = await platform.invokeMethod('startBeacon');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: Colors.green));
      }
    } on PlatformException catch (e) {
      setState(() => _isBroadcastingBle = false);
      print("Failed to talk to Android: '${e.message}'.");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hardware error: ${e.message}"), backgroundColor: Colors.red));
    }
  }

  // UPDATED: Now ONLY handles syncing data to the Firebase cloud
  Future<void> _triggerCloudSync() async {
    if (!_isOffline) {
      await _executeMacroSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location Updated."), backgroundColor: Colors.blueAccent),
        );
      }
    } else {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No network connection! Use BLE Broadcast above."), backgroundColor: Colors.orange),
        );
      }
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LifeX: Active Mesh', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(target: _center, zoom: 14.0),
            myLocationEnabled: true,
            compassEnabled: true,
          ),
          
          Positioned(
            top: 0, left: 0, right: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              color: _isOffline ? Colors.red.withOpacity(0.9) : Colors.green.withOpacity(0.9),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  _isOffline ? "STATUS: OFFLINE" : "STATUS: DRONE NETWORK ACTIVE",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ),
            ),
          ),

          // NEW: The Top BLE Broadcast Button
          Positioned(
            top: 60, left: 15, right: 15, // Placed right below the status banner
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isBroadcastingBle ? Colors.black87 : Colors.blue[800],
                    foregroundColor: _isBroadcastingBle ? Colors.greenAccent : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
                    elevation: _isBroadcastingBle ? 0 : 8,
                    side: _isBroadcastingBle ? BorderSide(color: Colors.greenAccent.withOpacity(0.5), width: 1.5) : BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isBroadcastingBle
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 2))
                      : const Icon(Icons.bluetooth_audio),
                  label: Text(
                    _isBroadcastingBle ? "BROADCASTING BLE BEACON..." : "BROADCAST VIA BLUETOOTH",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: _isBroadcastingBle ? 12 : 14, letterSpacing: 1.2),
                  ),
                  onPressed: _toggleBleBroadcast,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: !_isBroadcastingBle ? const SizedBox.shrink() : Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.stop, size: 20),
                      label: const Text("STOP BROADCASTING", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      onPressed: _toggleBleBroadcast, // Toggles it back off
                    ),
                  ),
                ),
              ],
            ),
          ),

          // The Bottom UI (Text Box and Cloud Sync)
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[800]!),
                  ),
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3, 
                    minLines: 1,
                    
                    onChanged: (text) {
                      setState(() {
                        _wordCount = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
                      });
                    },
                    
                    inputFormatters: [
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        int newWordCount = newValue.text.trim().isEmpty ? 0 : newValue.text.trim().split(RegExp(r'\s+')).length;
                        if (newWordCount > 50) return oldValue; 
                        return newValue; 
                      }),
                    ],

                    decoration: InputDecoration(
                      hintText: "Describe injuries/situation (Optional)",
                      hintStyle: const TextStyle(color: Colors.grey),
                      contentPadding: const EdgeInsets.all(15),
                      border: InputBorder.none,
                      
                      counterText: "$_wordCount / 50 words",
                      counterStyle: TextStyle(
                        color: _wordCount == 50 ? Colors.redAccent : Colors.grey,
                        fontWeight: _wordCount == 50 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 8,
                  ),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text("SYNC STATUS", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: _triggerCloudSync, 
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}