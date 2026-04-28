# **LifeX \- Disaster Saving App & Active Mesh**
&nbsp;&nbsp;
<div align="center">
<img width="124" height="124" alt="lifex_logo" src="https://github.com/user-attachments/assets/b84ddc30-1ac3-42f6-9389-40bf80393678" />
</div>
&nbsp;&nbsp;
During severe natural disasters (earthquakes, hurricanes), traditional cellular networks and Wi-Fi infrastructure collapse. Survivors are left trapped and disconnected, while rescue personnel lose precious "Golden Hour" response time blindly searching the rubble without remote triage capabilities.  
Lifex is an emergency response platform built to solve this. It operates completely independent of cellular infrastructure, transforming standard smartphones into an active, low-power BLE mesh network.  
Survivors can broadcast continuous SOS beacons with environmental data (like barometer depth) while offline. Rescue personnel use the app to actively scan the local environment, ping survivors, and utilize **Google Gemini AI** to automatically triage incoming distress signals based on medical severity.
&nbsp;&nbsp;
<div align="center">
<img height="512" alt="Screenshot 2026-04-28 235302" src="https://github.com/user-attachments/assets/174b3171-5c51-4ed8-b247-f8948192c725" />
<img height="512" alt="Screenshot 2026-04-28 235324" src="https://github.com/user-attachments/assets/e27a28c3-4578-4a56-b98f-47031f387a6d" />
</div>
&nbsp;&nbsp;
## **Core Architecture & Features**

### **1\. Native BLE Background Persistence**

Standard cross-platform Bluetooth libraries get killed by the OS when the app is backgrounded. Lifex utilizes a **custom Flutter-to-Kotlin Method Channel** to launch a native Android Foreground Service.

* **Result:** The survivor's SOS beacon continues to broadcast indefinitely, even if the phone screen is locked or the app is swiped away, consuming \< 5% battery over 24 hours.

### **2\. Generative AI Triage (Gemini)**

When rescue personnel detect a survivor's raw broadcast, the payload is parsed by Gemini 1.5 Pro.

* **Result:** The AI instantly analyzes panicked, messy text payloads and categorizes them into standard triage priorities (🟥 Critical, 🟨 Moderate, 🟩 Stable), preventing rescuer cognitive overload.

### **3\. Sensor Fusion & Depth Mapping**

The app accesses the device's native barometer to calculate dynamic air pressure deltas.

* **Result:** Allows rescuers to estimate if a survivor is trapped in a basement beneath the rubble or on a higher elevation relative to the rescuer's current position.

### **4\. Tactical UI & Secure Gateway**

* **Survivor Path:** Zero-friction entry. One tap activates the hardware beacon.  
* **Rescuer Path:** Auth-gated via Firebase. Features a dark, high-contrast tactical map/radar interface designed for low-light, high-stress environments. Includes offline token caching for instant access.

## **Tech Stack**

* **Frontend:** Flutter & Dart  
* **Hardware/Radio Layer:** Kotlin (Native Android BluetoothAdapter & Background Services)  
* **Backend Sync:** Firebase Authentication & Cloud Firestore (for syncing mesh data between active rescuer units)  
* **AI Engine:** Google Gemini SDK

## **Installation & Testing**

To run this project locally, you will need Flutter installed and an Android physical device (Emulators do not support BLE broadcasting).

1. **Clone the repository:** 
``` 
   git clone \[https://github.com/yourusername/lifex-mesh.git\](https://github.com/yourusername/lifex-mesh.git)  
   cd lifex-mesh
   ``` 

2. **Install dependencies:**  
``` 
   flutter pub get
``` 
3. **Configure Firebase & AI (Keys required):**  
   * Add your google-services.json to android/app/.  
   * Add your Gemini API key to the designated environment variables/auth service.  
4. **Run the App:**  
``` 
   \# A physical device is required for Bluetooth operations  
   flutter run \--release
``` 
*(Note: Building in \--release mode is highly recommended to properly test the native Kotlin foreground service efficiency).*

## **Future Roadmap**

* **Multi-Hop Relaying:** Upgrading from a localized broadcast to a true multi-hop mesh, allowing survivor phones to act as repeaters to pass signals out of deep rubble.  
* **Wearable Integration:** Porting the emergency broadcast trigger to WearOS for hands-free activation.  
* **Offline On-Device AI:** Migrating the Gemini API calls to on-device Nano models to allow triage even when the rescuer lacks satellite/cellular internet.
