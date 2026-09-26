# GymOS Biometric & Gate Access Local Sync Bridge

Yeh bridge software Gym reception ke PC (Windows 10 / 11) par chalta hai aur aapke biometric devices (eSSL, ZKTeco, Realtime, BioMax, Mantra) ko GymOS Supabase Cloud ke saath seamlessly connect karta hai.

---

### 🔥 4 Main Features (As Requested):

1. **Zero Data Loss on Internet Down (Offline Machine Buffer)**:
   - Agar internet band ho jata hai, machine attendance punches apne flash storage me rakhti hai.
   - Bridge software local machine se punches nikaal kar PC ki **SQLite Database (`gymos_biometric_buffer.db`)** me securely store kar leta hai.

2. **PC Sudden Power-Off / Shutdown Safe (WAL Mode)**:
   - SQLite ko **Write-Ahead Logging (WAL)** mode me configure kiya gaya hai.
   - Agar reception ka PC achanak power cut ya crash se band ho jaye, to bhi ek bhi attendance record delete ya corrupt nahi hoga.
   - Jab PC restart hoga aur internet aayega, Bridge automatic remaining punches GymOS Supabase me push kar dega.

3. **2-Way Expiry Synchronization (Door Lock/Unlock)**:
   - Jab owner GymOS Mobile App me kisi member ki membership renew karta hai ya expiry date badalta hai, GymOS database automatic `biometric_sync_queue` me command bhejta hai.
   - Bridge software iss command ko read karke biometric machine ke andar member ki nayi expiry date set kar deta hai.
   - Agar member ki membership expire ho gayi hai, to **bina internet ke bhi machine gate/turnstile ko unlock nahi karegi!**

4. **Multi-Tenant Protection & High Security**:
   - Kisi bhi gym ka attendance dusre gym me mix nahi ho sakta (Unique scoped composite key `gym_id + biometric_pin`).
   - Database credentials PC par store nahi hote; sirf Gym-specific Secret Key use hoti hai.

---

### 🚀 Setup Instructions (Reception PC):

1. **Python Install**: PC me Python 3.10+ install karein.
2. **Dependencies**:
   ```bash
   pip install requests
   ```
3. **Configuration**:
   - `config.json` me apna Gym Secret Key daalein (GymOS App > Owner Attendance Settings > Biometric Card se copy karein).
   - Biometric Machine ka Local IP address daalein (e.g. `192.168.1.201`).
4. **Run**:
   ```bash
   python gymos_biometric_bridge.py
   ```
5. *(Optional)* Windows Task Scheduler ya NSSM use karke ise as a Windows Service chala sakte hain taaki PC on hote hi background me start ho jaye.
