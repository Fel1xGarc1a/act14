import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'firebase_options.dart';

const String regularChannelId = 'regular_channel';
const String importantChannelId = 'important_channel';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _messageHandler(RemoteMessage message) async {
  print('background message ${message.notification!.body}');
  await _storeNotification(message);
}

Future<void> _storeNotification(RemoteMessage message) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> history = prefs.getStringList('notification_history') ?? [];
  
  String notification = '${DateTime.now().toIso8601String()} - ${message.notification?.title ?? ""}: ${message.notification?.body ?? ""}';
  
  history.add(notification);
  if (history.length > 20) {
    history.removeAt(0);
  }
  
  await prefs.setStringList('notification_history', history);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  const AndroidNotificationChannel regularChannel = AndroidNotificationChannel(
    regularChannelId,
    'Regular Notifications',
    importance: Importance.defaultImportance,
    description: 'Channel for regular notifications',
  );
  
  const AndroidNotificationChannel importantChannel = AndroidNotificationChannel(
    importantChannelId,
    'Important Notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    description: 'Channel for important notifications',
  );
  
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(regularChannel);
  
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(importantChannel);
  
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      print("Notification clicked: ${response.payload}");
    },
  );
  
  FirebaseMessaging.onBackgroundMessage(_messageHandler);
  
  runApp(const MessagingApp());
}

class MessagingApp extends StatelessWidget {
  const MessagingApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Act14 - Firebase Messaging',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MyHomePage(title: 'Act14 - Firebase Messaging'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late FirebaseMessaging messaging;
  String? fcmToken;
  List<Map<String, dynamic>> notificationHistory = [];

  @override
  void initState() {
    super.initState();
    
    messaging = FirebaseMessaging.instance;
    _initMessaging();
    _loadNotificationHistory();
  }

  Future<void> _initMessaging() async {
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    
    messaging.getToken().then((token) {
      print('FCM Token: $token');
      setState(() {
        fcmToken = token;
      });
    });
    
    messaging.subscribeToTopic("messaging");
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('FCM message received: ${message.notification!.body}');
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(message.notification?.title ?? "Notification"),
          content: Text(message.notification?.body ?? "No content"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
      
      _storeNotification(message);
      _loadNotificationHistory();
      
      String notificationType = message.data['type'] ?? 'regular';
      _showLocalNotification(message, notificationType);
    });
    
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification clicked: ${message.notification!.body}');
      
      String? route = message.data['route'];
      if (route != null) {
        print('Should navigate to route: $route');
      }
    });
  }

  void _showLocalNotification(RemoteMessage message, String notificationType) async {
    String channelId = notificationType == 'important' 
        ? importantChannelId 
        : regularChannelId;
    
    NotificationDetails details;
    
    if (notificationType == 'important') {
      details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId, 
          'Important Notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Colors.red,
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'open',
              'Open',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'dismiss',
              'Dismiss',
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
    } else {
      details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Regular Notifications',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      );
    }
    
    await flutterLocalNotificationsPlugin.show(
      message.hashCode,
      message.notification?.title ?? 'Notification',
      message.notification?.body ?? '',
      details,
      payload: message.data['route'],
    );
  }
  
  Future<void> _vibrate() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 500);
    }
  }
  
  Future<void> _loadNotificationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('notification_history') ?? [];
    
    setState(() {
      notificationHistory = history.map((notification) {
        List<String> parts = notification.split(' - ');
        String timestamp = parts[0];
        String content = parts.length > 1 ? parts[1] : '';
        
        return {
          'timestamp': DateTime.parse(timestamp),
          'content': content,
        };
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => _showNotificationHistory(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                'FCM Token:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: SelectableText(
                  fcmToken ?? 'Fetching token...',
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationHistory() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Notification History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: notificationHistory.isEmpty
                    ? const Center(child: Text('No notifications yet'))
                    : ListView.builder(
                        itemCount: notificationHistory.length,
                        itemBuilder: (context, index) {
                          final notification = notificationHistory[index];
                          return ListTile(
                            title: Text(notification['content']),
                            subtitle: Text(
                              '${notification['timestamp']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
