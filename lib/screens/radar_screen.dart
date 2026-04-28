import 'dart:async';
import 'dart:io'; // NEW: Required to check if the device is Android
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; 
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_triage_agent.dart'; 
import 'login_screen.dart';


class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  StreamSubscription<BluetoothAdapterState>? _btStateSubscription; 
  GoogleMapController? mapController;
  final FirestoreService _dbService = FirestoreService();
  final GeminiTriageAgent _aiAgent = GeminiTriageAgent();
  
  LatLng? _currentPosition;
  Set<Marker> _markers = {};

  bool _isScanningBle = false;
  bool _hasRung = false;

  double _rescuerPressure = 1013.25; 
  StreamSubscription<BarometerEvent>? _barometerSubscription;

  // The unique identifier that proves the signal is coming from a LifeX user
  final Guid _lifeXServiceUuid = Guid("8b0caaf2-1718-4503-9e46-1db98db18218");
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // Caches Gemini responses so we don't spam the API on every frame rebuild
  Map<String, Map<String, dynamic>> _triageCache = {};

  @override
  void initState() {
    super.initState();
    _locateRescuer();
    _startRescuerBarometer();

    // NEW: Listen to Bluetooth Hardware State
    _btStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        if (_isScanningBle) {
           // If they turn BT off manually, kill the scanner and update UI
           setState(() => _isScanningBle = false);
           FlutterBluePlus.stopScan();
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bluetooth disabled. Scan aborted."), backgroundColor: Colors.red));
        }
      }
    });
  }

  @override
  void dispose() {
    _btStateSubscription?.cancel();
    _barometerSubscription?.cancel();
    _scanSubscription?.cancel();
    if (_isScanningBle) FlutterBluePlus.stopScan();
    super.dispose();
  }

  void _startRescuerBarometer() {
    _barometerSubscription = barometerEventStream().listen((BarometerEvent event) {
      _rescuerPressure = event.pressure; 
    });
  }

  Future<void> _locateRescuer() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition();
    setState(() => _currentPosition = LatLng(position.latitude, position.longitude));
    mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition!, 16.0));
  }

  void _processTriageLogic(List<QueryDocumentSnapshot> docs) {
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final message = data['message'] as String?;

      if (message != null && message.isNotEmpty) {
        if (_triageCache[doc.id]?['message'] != message) {
          _triageCache[doc.id] = {
            'message': message,
            'priority': 0, 
            'tag': 'GEMINI ANALYZING...',
          };
          _fetchTriage(doc.id, message);
        }
      } else {
        _triageCache[doc.id] = {
          'message': '',
          'priority': 4, 
          'tag': 'UNKNOWN STATUS (NO TEXT)',
        };
      }
    }
  }

  Future<void> _fetchTriage(String docId, String message) async {
    final result = await _aiAgent.analyzePayload(message);
    if (mounted) {
      setState(() {
        _triageCache[docId] = {
          'message': message,
          'priority': result['priority'],
          'tag': result['tag'],
        };
      });
    }
  }

  double _getMarkerHue(int priority) {
    if (priority == 1) return BitmapDescriptor.hueRed;
    if (priority == 2) return BitmapDescriptor.hueOrange;
    if (priority == 3) return BitmapDescriptor.hueYellow;
    if (priority == 0) return BitmapDescriptor.hueMagenta; 
    return BitmapDescriptor.hueAzure; 
  }

  Color _getUIColor(int priority) {
    if (priority == 1) return Colors.redAccent;
    if (priority == 2) return Colors.orangeAccent;
    if (priority == 3) return Colors.yellowAccent;
    if (priority == 0) return Colors.purpleAccent; 
    return Colors.blueGrey; 
  }

  void _showRescueBottomSheet(String docId, double lat, double lng, double survivorPressure) {
    double depthMeters = (survivorPressure - _rescuerPressure) * 8.3;
    String direction = depthMeters >= 0 ? "BELOW SURFACE" : "ABOVE SURFACE";
    String formattedDepth = depthMeters.abs().toStringAsFixed(1);

    final cacheData = _triageCache[docId] ?? {'priority': 4, 'tag': 'LOADING...', 'message': ''};
    int priority = cacheData['priority'];
    String tag = cacheData['tag'];
    String rawMsg = cacheData['message'];

    Color uiColor = _getUIColor(priority);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("TARGET MAP COORDINATES", style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 2.0), textAlign: TextAlign.center),
              const SizedBox(height: 5),
              Text("${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 15),
              
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                decoration: BoxDecoration(
                  color: uiColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: uiColor, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      priority == 4 ? "STANDARD EXTRACTION" : (priority == 0 ? "PROCESSING..." : "GEMINI PRIORITY $priority"), 
                      style: TextStyle(color: uiColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)
                    ),
                    const SizedBox(height: 5),
                    Text(tag, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    if (rawMsg.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('"$rawMsg"', style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                    ]
                  ],
                ),
              ),

              const SizedBox(height: 10),
              
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue[900]?.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueAccent),
                ),
                child: Column(
                  children: [
                    const Text("ESTIMATED DEPTH", style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    Text("$formattedDepth METERS", style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                    Text(direction, style: const TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.5)),
                  ],
                ),
              ),
              
              const SizedBox(height: 25),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 15)),
                icon: const Icon(Icons.notifications_active),
                label: const Text("NOTIFY SURVIVOR", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('macro_rescues').doc(docId).update({'rescue_incoming': true});
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Signal sent to survivor's device.")));
                },
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent[700], foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 15)),
                icon: const Icon(Icons.check_circle),
                label: const Text("SAVED (CLEAR MESH)", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  Navigator.pop(context); 
                  await _dbService.markAsSaved(docId); 
                },
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LifeX: Command Center', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService().signOut();
              if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          )
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _dbService.activeRescuesStream,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                _processTriageLogic(snapshot.data!.docs);
                
                _markers.clear();
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final lat = data['survivor_lat'] as double;
                  final lng = data['survivor_lng'] as double;
                  final survivorPressure = data['survivor_pressure'] as double? ?? _rescuerPressure; 

                  int priority = _triageCache[doc.id]?['priority'] ?? 4;

                  _markers.add(
                    Marker(
                      markerId: MarkerId(doc.id),
                      position: LatLng(lat, lng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(_getMarkerHue(priority)),
                      onTap: () => _showRescueBottomSheet(doc.id, lat, lng, survivorPressure),
                    ),
                  );
                }
              }

              return GoogleMap(
                initialCameraPosition: CameraPosition(target: _currentPosition ?? const LatLng(17.3850, 78.4867), zoom: 14.0),
                myLocationEnabled: true,
                compassEnabled: true,
                markers: _markers,
                onMapCreated: (controller) => mapController = controller,
              );
            },
          ),

          Positioned(
            top: 15, left: 15, right: 15,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isScanningBle ? Colors.black87 : Colors.blue[800],
                    foregroundColor: _isScanningBle ? Colors.greenAccent : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
                    elevation: _isScanningBle ? 0 : 8,
                    side: _isScanningBle ? BorderSide(color: Colors.greenAccent.withOpacity(0.5), width: 1.5) : BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isScanningBle
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 2))
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(
                    _isScanningBle ? "SCANNING FOR BLUETOOTH SIGNALS..." : "SCAN VIA BLUETOOTH",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: _isScanningBle ? 12 : 14, letterSpacing: 1.2),
                  ),
                  onPressed: () async {
                    if (!_isScanningBle) {
                      setState(() { _isScanningBle = true; _hasRung = false; });

                      // UPDATED: Hardware check with OS-level prompt
                      if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.off) {
                        if (Platform.isAndroid) {
                          try {
                            await FlutterBluePlus.turnOn();
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please manually turn on Bluetooth to scan!"), backgroundColor: Colors.red));
                            setState(() => _isScanningBle = false);
                            return;
                          }
                        } else {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please turn on Bluetooth in Settings to scan!"), backgroundColor: Colors.red));
                          setState(() => _isScanningBle = false);
                          return;
                        }
                      }

                      await FlutterBluePlus.startScan(
                        withServices: [_lifeXServiceUuid], 
                        timeout: const Duration(seconds: 15), 
                      );

                      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
                        if (results.isNotEmpty && !_hasRung) {
                          setState(() => _hasRung = true);
                          
                          FlutterRingtonePlayer().playNotification();
                          FlutterBluePlus.stopScan(); 
                          
                          if (mounted) {
                            setState(() => _isScanningBle = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("LIFEX SURVIVOR DETECTED: ${results.first.device.remoteId}"), 
                                backgroundColor: Colors.greenAccent[700],
                                duration: const Duration(seconds: 5),
                              )
                            );
                          }
                        }
                      });

                      Future.delayed(const Duration(seconds: 15), () {
                        if (mounted && _isScanningBle) {
                          setState(() => _isScanningBle = false);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Scan finished. No LifeX signals found."), backgroundColor: Colors.grey));
                        }
                      });
                    }
                  },
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: !_isScanningBle ? const SizedBox.shrink() : Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.cancel, size: 20),
                      label: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      onPressed: () {
                        FlutterBluePlus.stopScan();
                        setState(() => _isScanningBle = false);
                      },
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}