import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static const _keyUsername = 'username';
  static const _keyJoinedRooms = 'joined_rooms';
  static const _keyPublicNotif = 'public_notif_asked';

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  static Future<void> setUsername(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, name);
  }

  static Future<List<String>> getJoinedRooms() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyJoinedRooms) ?? ['public'];
  }

  static Future<void> joinRoom(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final rooms = prefs.getStringList(_keyJoinedRooms) ?? ['public'];
    if (!rooms.contains(roomId)) {
      rooms.add(roomId);
      await prefs.setStringList(_keyJoinedRooms, rooms);
    }
  }

  static Future<void> leaveRoom(String roomId) async {
    if (roomId == 'public') return;
    final prefs = await SharedPreferences.getInstance();
    final rooms = prefs.getStringList(_keyJoinedRooms) ?? ['public'];
    rooms.remove(roomId);
    await prefs.setStringList(_keyJoinedRooms, rooms);
  }

  static Future<bool> hasAskedPublicNotif() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPublicNotif) ?? false;
  }

  static Future<void> markPublicNotifAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPublicNotif, true);
  }
}
