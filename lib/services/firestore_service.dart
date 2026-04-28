import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  // Create a singleton instance of the database
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Logs a detected BLE beacon to the local offline cache.
  /// It will automatically sync to the cloud when connectivity returns.
  Future<void> logSurvivorPing({
    required String ephemeralId,
    required double lat,
    required double lng,
    required int signalStrength,
  }) async {
    try {
      await _db.collection('survival_pings').add({
        'survivor_id': ephemeralId,
        'rescuer_lat': lat,
        'rescuer_lng': lng,
        'rssi_strength': signalStrength,
        // FieldValue.serverTimestamp() ensures the cloud server sets the final 
        // time, preventing issues if the rescuer's phone clock is wrong.
        'timestamp': FieldValue.serverTimestamp(), 
      });
      
      print("Ping logged successfully to local cache/cloud.");
    } catch (e) {
      print("Failed to log ping: $e");
    }
  }

  // updated syncMacroLocation with Anti-Spam Lock
  // Inside lib/services/firestore_service.dart

  Future<void> syncMacroLocation({
    required String deviceId,
    required double lat,
    required double lng,
    required double pressureHpa,
    String? message, // NEW: Accepts the survivor's text
  }) async {
    try {
      Map<String, dynamic> payload = {
        'status': 'AWAITING_EXTRACTION',
        'survivor_lat': lat,
        'survivor_lng': lng,
        'survivor_pressure': pressureHpa,
        'network_type': 'Drone/Emergency Cell',
        'timestamp': FieldValue.serverTimestamp(), 
        'rescue_incoming': false, 
      };

      // If they typed a message, add/overwrite it in the database
      if (message != null && message.isNotEmpty) {
        payload['message'] = message;
      }

      await _db.collection('macro_rescues').doc(deviceId).set(payload, SetOptions(merge: true));
      
      print("LifeX Watchdog: Macro Coordinates & Data Synced!");
    } catch (e) {
      print("Watchdog Sync Failed: $e");
    }
  }

  // 1. Stream: Listens to the cloud in real-time for anyone needing rescue
  Stream<QuerySnapshot> get activeRescuesStream {
    return _db.collection('macro_rescues').snapshots();
  }

  // 2. Action: Deletes the coordinate from the database once saved
  Future<void> markAsSaved(String documentId) async {
    try {
      await _db.collection('macro_rescues').doc(documentId).delete();
      print("LifeX: Target successfully marked as saved and removed from mesh.");
    } catch (e) {
      print("Failed to update rescue status: $e");
    }
  }

}