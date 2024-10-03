// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:bluetooth_gnss/about.dart';
import 'package:flutter/material.dart';
import 'package:pref/pref.dart';
import 'package:package_info/package_info.dart';
import 'package:share/share.dart';
import 'package:flutter/services.dart';

import 'settings.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock/wakelock.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); //https://stackoverflow.com/questions/57689492/flutter-unhandled-exception-servicesbinding-defaultbinarymessenger-was-accesse
  final prefservice = await PrefServiceShared.init(prefix: "pref_");
  await prefservice.setDefaultValues(
          {
            'reconnect': false,
            'secure': true,
            'check_settings_location': false,
            'log_bt_rx': false,
            'disable_ntrip': false,
            'ble_gap_scan_mode': false,
            'autostart': false,
            'list_nearest_streams_first': false,
            'ntrip_host': "igs-ip.net",
            'ntrip_port': "2101"
          }
  );

  runApp(MyApp(prefservice));
}


class MyApp extends StatefulWidget {
  // This widget is the root of your application.

  MyApp(this.prev_service, {Key? key}) : super(key: key);
  final BasePrefService prev_service;

  @override
  _MyAppState createState() => _MyAppState();


}

class _MyAppState extends State<MyApp> {

  ScrollableTabsDemo? m_widget;

  Widget build(BuildContext context) {
    m_widget = ScrollableTabsDemo(widget.prev_service);
    return PrefService(
        service: widget.prev_service,
        child: MaterialApp(
      title: 'Bluetooth GNSS',
      home: m_widget,
    ));
  }
}


enum TabsDemoStyle {
  iconsAndText,
  iconsOnly,
  textOnly
}

class _Page {
  const _Page({ this.icon, this.text });
  final IconData? icon;
  final String? text;
}

const List<_Page> _allPages = <_Page>[
  _Page(icon: Icons.bluetooth, text: 'Connect'),
  _Page(icon: Icons.cloud_download, text: 'RTK/NTRIP'),
  /*_Page(icon: Icons.location_on, text: 'Location'),
  _Page(icon: Icons.landscape, text: 'Map'),
  _Page(icon: Icons.view_list, text: 'Raw Data'),
  */
];

class ScrollableTabsDemo extends StatefulWidget {
  ScrollableTabsDemo(this.pref_service, {Key? key}) : super(key: key);
  final BasePrefService pref_service;
  ScrollableTabsDemoState? m_state;
  @override
  ScrollableTabsDemoState createState() {
    m_state = ScrollableTabsDemoState();
    return m_state!;
  }
}

class ScrollableTabsDemoState extends State<ScrollableTabsDemo> with SingleTickerProviderStateMixin {

  static const method_channel = MethodChannel("com.clearevo.bluetooth_gnss/engine");
  static const event_channel = EventChannel("com.clearevo.bluetooth_gnss/engine_events");

  String _status = "Loading status...";
  String _selected_device = "Loading selected device...";

  static const double default_checklist_icon_size = 35;
  static const double default_connect_state_icon_size = 60;

  static const ICON_NOT_CONNECTED =  Icon(
    Icons.bluetooth_disabled,
    color: Colors.red,
    size: default_connect_state_icon_size,
  );

  static const FLOATING_ICON_BLUETOOTH_SETTINGS =  Icon(
    Icons.settings_bluetooth,
    color: Colors.white,
  );

  static const FLOATING_ICON_BLUETOOTH_CONNECT =  Icon(
    Icons.bluetooth_connected,
    color: Colors.white,
  );

  static const FLOATING_ICON_BLUETOOTH_CONNECTING =  Icon(
    Icons.bluetooth_connected,
    color: Colors.white,
  );

  static const ICON_CONNECTED =  Icon(
    Icons.bluetooth_connected,
    color: Colors.blue,
    size: default_connect_state_icon_size,
  );

  static const ICON_LOADING =  Icon(
    Icons.access_time,
    color: Colors.grey,
    size: default_connect_state_icon_size,
  );

  static const ICON_OK =  Icon(
    Icons.check_circle,
    color: Colors.lightBlueAccent,
    size: default_checklist_icon_size,
  );
  static const ICON_FAIL =  Icon(
    Icons.cancel,
    color: Colors.blueGrey,
    size: default_checklist_icon_size,
  );

  static const uninit_state = "Loading state...";

  //Map<String, String> _check_state_map =

  Map<String, Icon> _check_state_map_icon = {
    "Bluetooth On": ICON_LOADING,
    "Bluetooth Device Paired": ICON_LOADING,
    "Bluetooth Device Selected": ICON_LOADING,
    "Bluetooth Device Selected": ICON_LOADING,
    "Mock location enabled": ICON_LOADING,
  };

  Icon _m_floating_button_icon = Icon(Icons.access_time);

  Icon _main_icon = ICON_LOADING;
  String _main_state = "Loading...";
  static String WAITING_DEV = "No data";
  bool _is_bt_connected = false;
  bool _wakelock_enabled = false;
  bool _is_ntrip_connected = false;
  int _ntrip_packets_count = 0;
  bool _is_bt_conn_thread_alive_likely_connecting = false;
  String _location_from_talker = WAITING_DEV;

  int _mock_location_set_ts = 0;
  String _mock_location_set_status = WAITING_DEV;
  List<String> talker_ids = ["GP", "GL", "GA", "GB", "GQ"];

  TabController? _controller;
  TabsDemoStyle _demoStyle = TabsDemoStyle.iconsAndText;
  bool _customIndicator = false;

  Timer? timer;
  static String note_how_to_disable_mock_location = "";
  Map<dynamic, dynamic> _param_map = Map<dynamic, dynamic>();

  void wakelock_enable() {
    if (_wakelock_enabled == false) {
      Wakelock
          .enable(); //keep screen on for users to continuously monitor connection state
      _wakelock_enabled = true;
    }
  }

  void wakelock_disable() {
    if (_wakelock_enabled == true) {
      Wakelock
          .disable(); //keep screen on for users to continuously monitor connection state
      _wakelock_enabled = false;
    }
  }


  static void LogPrint(Object object) async {
    int defaultPrintLength = 1020;
    if (object == null || object.toString().length <= defaultPrintLength) {
      print(object);
    } else {
      String log = object.toString();
      int start = 0;
      int endIndex = defaultPrintLength;
      int logLength = log.length;
      int tmpLogLength = log.length;
      while (endIndex < logLength) {
        print(log.substring(start, endIndex));
        endIndex += defaultPrintLength;
        start += defaultPrintLength;
        tmpLogLength -= defaultPrintLength;
      }
      if (tmpLogLength > 0) {
        print(log.substring(start, logLength));
      }
    }
  }

  @override
  void initState() {
    super.initState();

    timer = Timer.periodic(Duration(seconds: 2), (Timer t) => check_and_update_selected_device());

    _controller = TabController(vsync: this, length: _allPages.length);

    check_and_update_selected_device();


    event_channel.receiveBroadcastStream().listen(
            (dynamic event) {

              print("got event -----------");
              //LogPrint("$event");
              Map<dynamic, dynamic> param_map = event;

              setState(() {
                _param_map = param_map;
              });

              // 660296614

              if (param_map.containsKey('mock_location_set_ts')) {
                try {
                  _mock_location_set_ts = param_map['mock_location_set_ts'] ?? 0;
                }  catch (e) {
                  print('get parsed param exception: $e');
                }
              }
        },
        onError: (dynamic error) {
          print('Received error: ${error.message}');
        }
    );

  }

  void cleanup()
  {
    print('cleanup()');
    if (timer != null) {
      timer!.cancel();
    }
  }

  @override
  void deactivate()
  {
    print('deactivate()');
    //cleanup();
  }

  @override
  void dispose() {
    print('dispose()');
    cleanup();

    _controller!.dispose();
    super.dispose();
  }

  void changeDemoStyle(TabsDemoStyle style) {
    setState(() {
      _demoStyle = style;
    });
  }

  Decoration? getIndicator() {
    if (!_customIndicator)
      return const UnderlineTabIndicator();

    switch(_demoStyle) {
      case TabsDemoStyle.iconsAndText:
        return ShapeDecoration(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4.0)),
            side: BorderSide(
              color: Colors.white24,
              width: 2.0,
            ),
          ) + const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4.0)),
            side: BorderSide(
              color: Colors.transparent,
              width: 4.0,
            ),
          ),
        );

      case TabsDemoStyle.iconsOnly:
        return ShapeDecoration(
          shape: const CircleBorder(
            side: BorderSide(
              color: Colors.white24,
              width: 4.0,
            ),
          ) + const CircleBorder(
            side: BorderSide(
              color: Colors.transparent,
              width: 4.0,
            ),
          ),
        );

      case TabsDemoStyle.textOnly:
        return ShapeDecoration(
          shape: const StadiumBorder(
            side: BorderSide(
              color: Colors.white24,
              width: 2.0,
            ),
          ) + const StadiumBorder(
            side: BorderSide(
              color: Colors.transparent,
              width: 4.0,
            ),
          ),
        );
    }
    return null;
  }

  Scaffold? _scaffold;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  @override
  Widget build(BuildContext context) {
    final Color iconColor = Theme.of(context).hintColor;

    bool gap_mode =  false;

    _scaffold = Scaffold(
        key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Bluetooth GNSS'),
        actions: <Widget>[

          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              check_and_update_selected_device(true, false).then(
                      (sw) {
                        if (sw == null) {
                          return;
                        }
                        if (_is_bt_connected || _is_bt_conn_thread_alive_likely_connecting) {
                          toast("Please Disconnect first - cannot change settings during live connection...");
                          return;
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) {
                              dynamic bdmap = sw.m_bdaddr_to_name_map;
                              print("sw.bdaddr_to_name_map: $bdmap");
                              return settings_widget(widget.pref_service, bdmap);
                            }
                            ),
                          );
                        }
                      }
              );
            },
          ),
          // overflow menu
          PopupMenuButton(
                  itemBuilder: (_) => <PopupMenuItem<String>>[
                    new PopupMenuItem<String>(
                            child: const Text('Disconnect/Stop'),
                            value: 'disconnect',
                    ),
                    new PopupMenuItem<String>(
                        child: const Text('Issues/Suggestions'), value: 'issues'),
                    new PopupMenuItem<String>(
                        child: const Text('Project page'), value: 'project'),
                    new PopupMenuItem<String>(
                        child: const Text('About'), value: 'about'),
                  ],
                  onSelected: menu_selected,
          ),
        ],
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          indicator: getIndicator(),
          tabs: _allPages.map<Tab>((_Page page) {
            assert(_demoStyle != null);
            switch (_demoStyle) {
              case TabsDemoStyle.iconsAndText:
                return Tab(text: page.text, icon: Icon(page.icon));
              case TabsDemoStyle.iconsOnly:
                return Tab(icon: Icon(page.icon));
              case TabsDemoStyle.textOnly:
              default:
                return Tab(text: page.text);
            }
          }).toList(),
        ),
      ),
    floatingActionButton: Visibility(
      visible: !_is_bt_connected,
            child: FloatingActionButton(
              onPressed: connect,
              tooltip: 'Connect',
              child: _m_floating_button_icon,
            )
    ), // This trailing comma makes auto-formatting nicer for build methods.
      body: new SafeArea(child: TabBarView(
        controller: _controller,
        children: _allPages.map<Widget>((_Page page) {
          String pname = page.text.toString();
          //print ("page: $pname");

          switch (pname) {

            case "Connect":
              List<Widget> rows = List.empty();
              if (_is_bt_connected) {

                rows = <Widget>[
                  Card(
                    child: Container(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        children: <Widget>[
                          Text(
                            'GNSS Device read stats',
                            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                                    fontFamily: 'GoogleSans',
                                    color: Colors.blueGrey
                            ),
                          ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Lat:',
                                  style: Theme.of(context).textTheme.headline6
                              ),
                              Text(
                                  (_param_map['lat_double_07_str'] ?? WAITING_DEV),
                                  style: Theme.of(context).textTheme.headline5
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Lon:',
                                  style: Theme.of(context).textTheme.headline6
                              ),
                              Text(
                                  (_param_map['lon_double_07_str'] ?? WAITING_DEV),
                                  style: Theme.of(context).textTheme.headline5
                              ),
                            ],
                          ),



                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              ElevatedButton(
                                onPressed: () {
                                  String content = (_param_map['lat_double_07_str'] ?? WAITING_DEV) + "," /* no space here for sharing to gmaps */ + (_param_map['lon_double_07_str'] ?? WAITING_DEV);
                                  Share.share('https://www.google.com/maps/search/?api=1&query='+content).then((result) {
                                    snackbar('Shared: '+content);
                                  });
                                },
                                child: const Icon(Icons.share),
                              ),
                              Padding(padding: const EdgeInsets.all(2.0),),
                              ElevatedButton(
                                onPressed: () {
                                  String content = (_param_map['lat_double_07_str'] ?? WAITING_DEV) + "," + (_param_map['lon_double_07_str'] ?? WAITING_DEV);
                                  Clipboard.setData(ClipboardData(text: content)).then((result) {
                                    snackbar('Copied to clipboard: '+content);
                                  });
                                },
                                child: const Icon(Icons.content_copy),
                              )
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Time from GNSS:',
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                              Text(
                                  _param_map['GN_time'] ?? _param_map['GP_time'] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Ellipsoidal Height:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map['GN_ellipsoidal_height_double_02_str'] ?? _param_map['GP_ellipsoidal_height_double_02_str'] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Orthometric (MSL) Height:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map['GN_gga_alt_double_02_str'] ?? _param_map['GP_gga_alt_double_02_str'] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Geoidal Height:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map['GN_geoidal_height_double_02_str'] ?? _param_map['GP_geoidal_height_double_02_str'] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Fix status:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  (_param_map["GN_status"] ?? _param_map["GP_status"] ?? "No data"),
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Fix quality:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["GN_fix_quality"] ?? _param_map["GP_fix_quality"] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'UBLOX Fix Type:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["UBX_POSITION_navStat"] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'UBLOX XY Accuracy(m):',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["UBX_POSITION_hAcc"] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'UBLOX Z Accuracy(m):',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["UBX_POSITION_vAcc"] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'HDOP:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["hdop_str"] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Course:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["course_str"] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(5.0),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                      'N Sats used TOTAL:',
                                      style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  ((_param_map["GP_n_sats_used"] ?? 0) + (_param_map["GL_n_sats_used"] ?? 0) + (_param_map["GA_n_sats_used"] ?? 0) + (_param_map["GB_n_sats_used"] ?? 0) + (_param_map["GQ_n_sats_used"] ?? 0)).toString(),
                                      style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                      'N Galileo in use/view:',
                                      style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  "${_param_map["GA_n_sats_used_str"] ?? WAITING_DEV} / ${_param_map["GA_n_sats_in_view_str"] ?? WAITING_DEV}",
                                      style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                      'N GPS in use/view:',
                                      style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  "${_param_map["GP_n_sats_used_str"] ?? WAITING_DEV} / ${_param_map["GP_n_sats_in_view_str"] ?? WAITING_DEV}",
                                      style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                      'N GLONASS in use/view:',
                                      style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  "${_param_map["GL_n_sats_used_str"] ?? WAITING_DEV} / ${_param_map["GL_n_sats_in_view_str"] ?? WAITING_DEV}",
                                      style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                      'N BeiDou in use/view:',
                                      style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  "${_param_map["GB_n_sats_used_str"] ?? WAITING_DEV} / ${_param_map["GB_n_sats_in_view_str"] ?? WAITING_DEV}",
                                      style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'N QZSS in use/view:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  "${_param_map["GQ_n_sats_used_str"] ?? WAITING_DEV} / ${_param_map["GQ_n_sats_in_view_str"] ?? WAITING_DEV}",
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(5.0),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Location sent to Android:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  '$_mock_location_set_status',
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Alt type used:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["alt_type"] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(5.0),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                      'Total GGA Count:',
                                      style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                      _param_map["GN_GGA_count_str"] ?? _param_map["GP_GGA_count_str"] ?? WAITING_DEV,
                                      style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                      'Total RMC Count:',
                                      style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["GN_RMC_count_str"] ?? _param_map["GP_RMC_count_str"] ?? WAITING_DEV,
                                      style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Current log folder:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["logfile_folder"] ??WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Current log name:',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["logfile_name"] ?? WAITING_DEV,
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                  'Current log size (MB):',
                                  style: Theme.of(context).textTheme.bodyText2
                              ),
                              Text(
                                  _param_map["logfile_n_bytes"] == null ? WAITING_DEV : (_param_map["logfile_n_bytes"] / 1000000).toString(),
                                  style: Theme.of(context).textTheme.bodyText1
                              ),
                            ],
                          ),


                        ],
                      ),

                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10.0),
                  ),
                  Card(
                    child: Container(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: <Widget>[
                            Text(
                              'Connected',
                              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                                  fontFamily: 'GoogleSans',
                                  color: Colors.grey
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.all(5.0),
                            ),
                            ICON_CONNECTED
                            ,
                            Padding(
                              padding: const EdgeInsets.all(5.0),
                            ),
                            Text(
                                '$_selected_device'
                            ),
                            Padding(
                              padding: const EdgeInsets.all(5.0),
                            ),
                            Text(
                                "- You can now use other apps like 'Waze' normally.\n- Location is now from connected device\n- To stop, press the 'Disconnect' menu in top-right options.",
                                style: Theme.of(context).textTheme.bodyText2
                            ),
                            Padding(
                              padding: const EdgeInsets.all(5.0),
                            ),
                            /*Text(
                                        ""+note_how_to_disable_mock_location.toString(),
                                        style: Theme.of(context).textTheme.caption
                                ),*/
                          ],
                        )
                    ),
                  ),
                ];

              } else if (_is_bt_connected == false && _is_bt_conn_thread_alive_likely_connecting) {

                rows = <Widget>[
                  Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children:
                          [
                            ICON_LOADING,
                          ]
                  ),
                  Padding(
                    padding: const EdgeInsets.all(15.0),
                  ),
                  Text(
                    '$_status',
                    style: Theme.of(context).textTheme.headline5,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10.0),
                  ),
                  Text(
                    'Selected device:',
                    style: Theme.of(context).textTheme.caption,
                  ),
                  Text(
                          '$_selected_device'
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10.0),
                  ),
                ];

              } else {

                rows = <Widget>[
                  Text(
                    'Pre-connect checklist',
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                      fontFamily: 'GoogleSans',
                      color: Colors.blueGrey
                    ),
                    //style: Theme.of(context).textTheme.headline,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10.0),
                  ),
                ];

                List<Widget> checklist = [];
                for (String key in _check_state_map_icon.keys) {
                  Row row = Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children:
                      [
                        _check_state_map_icon[key]!,
                        new Container(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  key,
                                  style: Theme.of(context).textTheme.bodyText1,
                                )
                        ),
                      ]
                  );
                  checklist.add(row);
                }

                rows.add(
                  new Card(
                          child: new Container(
                            padding: const EdgeInsets.all(10.0),
                            child: new Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: checklist,
                            ),
                          )
                  )
                );

                List<Widget> bottom_widgets = [
                  Padding(
                    padding: const EdgeInsets.all(15.0),
                  ),
                  new Card(
                    child: new Column(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(15.0),
                        ),
                        Text(
                          'Next step',
                          style:  Theme.of(context).textTheme.titleSmall!.copyWith(
                            fontFamily: 'GoogleSans',
                            color: Colors.blueGrey,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10.0),
                        ),
                        new Container(
                          padding: const EdgeInsets.all(10.0),

                          child: Text(
                            '$_status',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    )
                  )

                ];
                rows.addAll(bottom_widgets);
              }

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: new Container(
                          child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: rows,
                  )),
                )
              );
              break;



            case "RTK/NTRIP":
              //print("build location");
              return  SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child:  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(8.0),
                        child: new Container(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "${_is_ntrip_connected?'NTRIP Connected':'NTRIP Not Connected'}",
                              style:  Theme.of(context).textTheme.titleSmall!.copyWith(
                                fontFamily: 'GoogleSans',
                                color: Colors.blueGrey,
                              ),
                            ),
                            Padding(padding: EdgeInsets.all(10.0)),
                            Text("${(PrefService.of(context).get('ntrip_host') != null && PrefService.of(context).get('ntrip_port') != null) ? (PrefService.of(context).get('ntrip_host').toString())+":"+PrefService.of(context).get('ntrip_port').toString() : ''}"),
                            Padding(padding: EdgeInsets.all(10.0)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                    "NTRIP Server/Login filled:",
                                    style: Theme.of(context).textTheme.bodyText2
                                ),
                                Text(
                                    (
                                        PrefService.of(context).get('ntrip_host') != null &&
                                            PrefService.of(context).get('ntrip_host').toString().length > 0 &&

                                            PrefService.of(context).get('ntrip_port') != null &&
                                            PrefService.of(context).get('ntrip_port').toString().length > 0 &&

                                            PrefService.of(context).get('ntrip_mountpoint') != null &&
                                            PrefService.of(context).get('ntrip_mountpoint').toString().length > 0 &&

                                            PrefService.of(context).get('ntrip_user') != null &&
                                            PrefService.of(context).get('ntrip_user').toString().length > 0 &&

                                            PrefService.of(context).get('ntrip_pass') != null &&
                                            PrefService.of(context).get('ntrip_pass').toString().length > 0
                                    ) ? (
                                        (PrefService.of(context).get('disable_ntrip') ?? false) ? "Yes but disabled": "Yes"
                                    ) : "No",
                                    style: Theme.of(context).textTheme.bodyText1
                                ),
                              ],
                            ),
                            Padding(padding: EdgeInsets.all(10.0)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                    "NTRIP Stream selected:",
                                    style: Theme.of(context).textTheme.bodyText2
                                ),
                                Text(
                                    PrefService.of(context).get('ntrip_mountpoint') ?? "None",
                                    style: Theme.of(context).textTheme.bodyText1
                                ),
                              ],
                            ),
                            Padding(padding: EdgeInsets.all(10.0)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                    "N NTRIP packets received:",
                                    style: Theme.of(context).textTheme.bodyText2
                                ),
                                Text(
                                    "$_ntrip_packets_count",
                                    style: Theme.of(context).textTheme.bodyText1
                                ),
                              ],
                            ),
                          ],
                        )),
                        )
                    )
                  )
              );
              break;
          }
          return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: new Container(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "<UNDER DEVELOPMENT/>\n\nSorry, dev not done yet - please check again after next update...",
                                  style:  Theme.of(context).textTheme.titleSmall!.copyWith(
                                    fontFamily: 'GoogleSans',
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ],
                            )),
                  )
          );

        }).toList(),
      ),
    ));

    return _scaffold!;
  }


  /////////////functions

  void menu_selected(String menu) async {
    print('menu_selected: $menu');
    switch (menu) {
      case "disconnect":
        await disconnect();
        break;
      case "about":
        PackageInfo packageInfo = await PackageInfo.fromPlatform();
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) {
                return Scaffold(
                    appBar: AppBar(
                      title: Text("About"),
                    ),
                    body: get_about_view(packageInfo.version.toString())
                );
              }
          ),
        );
        break;
      case "issues":
        launch("https://github.com/ykasidit/bluetooth_gnss/issues");
        break;
      case "project":
        launch("https://github.com/ykasidit/bluetooth_gnss");
        break;
    }
  }

  void clear_disp_text() {
    _selected_device = "";
    _status = "";
  }

  //return settings_widget that can be used to get selected bdaddr
  Future<settings_widget_state?> check_and_update_selected_device([bool user_pressed_settings_take_action_and_ret_sw=false, bool user_pressed_connect_take_action_and_ret_sw=false]) async {
    _m_floating_button_icon = FLOATING_ICON_BLUETOOTH_SETTINGS;

    try {
      _is_bt_connected = await method_channel.invokeMethod('is_bt_connected');
      _is_ntrip_connected =
      await method_channel.invokeMethod('is_ntrip_connected');
      _ntrip_packets_count =
      await method_channel.invokeMethod('get_ntrip_cb_count');

      if (_is_bt_connected) {
        wakelock_enable();
      } else {
        wakelock_disable();
      }

      if (_is_bt_connected) {
        _status = "Connected";
        _m_floating_button_icon = FLOATING_ICON_BLUETOOTH_CONNECT;

        try {
          int mock_set_millis_ago;
          DateTime now = DateTime.now();
          int nowts = now.millisecondsSinceEpoch;
          _mock_location_set_status = "";
          if (_mock_location_set_ts == null) {
            _mock_location_set_ts = 0;
          }
          mock_set_millis_ago = nowts - _mock_location_set_ts;
          //print("mock_location_set_ts $mock_set_ts, nowts $nowts");

          double secs_ago = mock_set_millis_ago / 1000.0;

          if (_mock_location_set_ts == 0) {
            setState(() {
              _mock_location_set_status = "Never";
            });
          } else {
            setState(() {
              _mock_location_set_status =
                  secs_ago.toStringAsFixed(3) + " Seconds ago";
            });
          }
        } catch (e, trace) {
          print('get parsed param exception: $e $trace');
        }

        return null;
      }
    } on PlatformException catch (e) {
      toast("WARNING: check _is_bt_connected failed: $e");
      _is_bt_connected = false;
    }

    try {
      _is_bt_conn_thread_alive_likely_connecting = await method_channel.invokeMethod('is_conn_thread_alive');
      print("_is_bt_conn_thread_alive_likely_connecting: $_is_bt_conn_thread_alive_likely_connecting");
      if (_is_bt_conn_thread_alive_likely_connecting) {
        setState(() {
          _status = "Connecting...";
        });
        return null;
      }
    } on PlatformException catch (e) {
      toast("WARNING: check _is_connecting failed: $e");
      _is_bt_conn_thread_alive_likely_connecting = false;
    }
    //print('check_and_update_selected_device1');

    _check_state_map_icon.clear();
    _main_icon = ICON_FAIL;
    _main_state = "Not ready";

    //print('check_and_update_selected_device2');

    List<String> not_granted_permissions = await check_permissions_not_granted();
    if (not_granted_permissions.length > 0) {
      String msg = "Please allow required app permissions... Re-install app if declined earlier and not seeing permission request pop-up: "+not_granted_permissions.toString();
      setState(() {
        _check_state_map_icon["App permissions"] = ICON_FAIL;
        _status = msg;
      });
      return null;
    }

    _check_state_map_icon["App permissions"] = ICON_OK;


    if (!(await is_bluetooth_on())) {
      String msg = "Please turn ON Bluetooth...";
      setState(() {
        _check_state_map_icon["Bluetooth is OFF"] = ICON_FAIL;
        _status = msg;
      });
      //print('check_and_update_selected_device4');

      if (user_pressed_connect_take_action_and_ret_sw ||
          user_pressed_settings_take_action_and_ret_sw) {
        bool open_act_ret = false;
        try {
          open_act_ret =
          await method_channel.invokeMethod('open_phone_blueooth_settings');
          toast("Please turn ON Bluetooth...");
        } on PlatformException catch (e) {
          //print("Please open phone Settings and change first (can't redirect screen: $e)");
        }
      }
      return null;
    }

    _check_state_map_icon["Bluetooth powered ON"] = ICON_OK;
    //print('check_and_update_selected_device5');

    Map<dynamic, dynamic> bd_map = await get_bd_map();
    settings_widget_state sw = settings_widget_state(bd_map);
    if (user_pressed_settings_take_action_and_ret_sw) {
      return sw;
    }
    bool gap_mode = PrefService.of(context).get('ble_gap_scan_mode') ?? false;
    if (gap_mode) {
      //bt ble gap broadcast mode
      _check_state_map_icon["EcoDroidGPS-Broadcast device mode"] = ICON_OK;
    } else {
      //bt connect mode
      if (bd_map.length == 0) {
        String msg = "Please pair your Bluetooth GPS/GNSS Receiver in phone Settings > Bluetooth first.\n\nClick floating button to go there...";
        setState(() {
          _check_state_map_icon["No paired Bluetooth devices"] = ICON_FAIL;
          _status = msg;
          _selected_device = "No paired Bluetooth devices yet...";
        });
        //print('check_and_update_selected_device6');
        if (user_pressed_connect_take_action_and_ret_sw ||
            user_pressed_settings_take_action_and_ret_sw) {
          bool open_act_ret = false;
          try {
            open_act_ret =
            await method_channel.invokeMethod('open_phone_blueooth_settings');
            toast("Please pair your Bluetooth GPS/GNSS Device...");
          } on PlatformException catch (e) {
            //print("Please open phone Settings and change first (can't redirect screen: $e)");
          }
        }
        return null;
      }
      //print('check_and_update_selected_device7');
      _check_state_map_icon["Found paired Bluetooth devices"] = ICON_OK;

      //print('check_and_update_selected_device8');

      //print('check_and_update_selected_device9');

      if (sw.get_selected_bdaddr(widget.pref_service).isEmpty) {
        String msg = "Please select your Bluetooth GPS/GNSS Receiver in Settings (the gear icon on top right)";
        /*Fluttertoast.showToast(
            msg: msg
        );*/
        setState(() {
          _check_state_map_icon["No device selected\n(select in top-right settings/gear icon)"] =
              ICON_FAIL;
          _selected_device = sw.get_selected_bd_summary(widget.pref_service) ?? "";
          _status = msg;
        });
        //print('check_and_update_selected_device10');

        _main_icon = ICON_NOT_CONNECTED;
        _main_state = "Not connected";

        return null;
      }
      _check_state_map_icon["Target device selected"] = ICON_OK;
    }

    //print('check_and_update_selected_device11');

    bool check_location = PrefService.of(context).get('check_settings_location') ?? true;

    if (check_location) {
      if (!(await is_location_enabled())) {
        String msg = "Location needs to be on and set to 'High Accuracy Mode' - Please go to phone Settings > Location to change this...";
        setState(() {
          _check_state_map_icon["Location must be ON and 'High Accuracy'"] =
              ICON_FAIL;
          _status = msg;
        });

        //print('pre calling open_phone_location_settings() user_pressed_connect_take_action_and_ret_sw $user_pressed_connect_take_action_and_ret_sw');

        if (user_pressed_connect_take_action_and_ret_sw) {
          bool open_act_ret = false;
          try {
            //print('calling open_phone_location_settings()');
            open_act_ret =
            await method_channel.invokeMethod('open_phone_location_settings');
            toast("Please set Location ON and 'High Accuracy Mode'...");
          } on PlatformException catch (e) {
            print(
                "Please open phone Settings and change first (can't redirect screen: $e)");
          }
        }
        //print('check_and_update_selected_device12');
        return null;
      }
      //print('check_and_update_selected_device13');
      _check_state_map_icon["Location is on and 'High Accuracy'"] = ICON_OK;
    }

    if (! (await is_mock_location_enabled())) {
      String msg = "Please go to phone Settings > Developer Options > Under 'Debugging', set 'Mock Location app' to 'Bluetooth GNSS'...";
      setState(() {
        _check_state_map_icon["'Mock Location app' not 'Bluetooth GNSS'\n"] = ICON_FAIL;
        _status = msg;
      });
      //print('check_and_update_selected_device14');
      if (user_pressed_connect_take_action_and_ret_sw) {
        bool open_act_ret = false;
        try {
          open_act_ret = await method_channel.invokeMethod('open_phone_developer_settings');
          toast("Please set 'Mock Locaiton app' to 'Blueooth GNSS'..");
        } on PlatformException catch (e) {
          print("Please open phone Settings and change first (can't redirect screen: $e)");
        }
      }
      return null;
    }
    //print('check_and_update_selected_device15');
    _check_state_map_icon["'Mock Location app' is 'Bluetooth GNSS'\n"+note_how_to_disable_mock_location] = ICON_OK;
    _main_icon = ICON_OK;


    if (_is_bt_connected == false && _is_bt_conn_thread_alive_likely_connecting) {
      setState(() {
        _main_icon = ICON_LOADING;
        _main_state = "Connecting...";
          _m_floating_button_icon = FLOATING_ICON_BLUETOOTH_CONNECTING;
      });
      //print('check_and_update_selected_device16');
    } else {
      //ok - ready to connect
      setState(() {
        _status = "Please press the floating button to connect...";
          _m_floating_button_icon = FLOATING_ICON_BLUETOOTH_CONNECT;
      });
      //print('check_and_update_selected_device17');
    }

    setState(() {
      _selected_device = sw.get_selected_bd_summary(widget.pref_service) ?? "";
    });

    //setState((){});
    //print('check_and_update_selected_device18');

    return sw;
  }

  void toast(String msg) async
  {
    try {
      await method_channel.invokeMethod(
          "toast",
          {
            "msg": msg
          }
      );

    }  catch (e) {
      print("WARNING: toast failed exception: $e");
    }
  }

  void snackbar(String msg)
  {
    try {
      final snackBar = SnackBar(content: Text(msg));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }  catch (e) {
      print("WARNING: snackbar failed exception: $e");
    }
  }

  Future<void> disconnect() async
  {
    try {
      if (_is_bt_connected) {
        toast("Disconnecting...");
      } else {
        //toast("Not connected...");
      }
      //call it in any case just to be sure service it is stopped (.close()) method called
      await method_channel.invokeMethod('disconnect');
    } on PlatformException catch (e) {
      toast("WARNING: disconnect failed: $e");
    }
  }

  Future<void> connect() async {

    print("main.dart connect() start");

    bool log_bt_rx = PrefService.of(context).get('log_bt_rx') ?? false;
    bool gap_mode = PrefService.of(context).get('ble_gap_scan_mode') ?? false;

    if (log_bt_rx) {
      bool write_enabled = false;
      try {
        write_enabled = await method_channel.invokeMethod('is_write_enabled');
      } on PlatformException catch (e) {
        toast("WARNING: check write_enabled failed: $e");
      }
      if (write_enabled == false) {
        toast("Write external storage permission required for data loggging...");
        return;
      }

      bool can_create_file = false;
      try {
        can_create_file = await method_channel.invokeMethod('test_can_create_file_in_chosen_folder');
      } on PlatformException catch (e) {
        toast("WARNING: check test_can_create_file_in_chosen_folder failed: $e");
      }
      if (can_create_file == false) {
        //TODO: try req permission firstu
        toast("Please go to Settings > re-tick 'Enable logging' (failed to access chosen log folder)");
        return;
      }
    }

    if (gap_mode) {
      bool coarse_location_enabled = await is_coarse_location_enabled();
      if (coarse_location_enabled == false) {
        toast("Coarse Locaiton permission required for BLE GAP mode...");
        return;
      }
    }

    if (_is_bt_connected) {
      toast("Already connected...");
      return;
    }

    if (_is_bt_conn_thread_alive_likely_connecting) {
      toast("Connecting, please wait...");
      return;
    }

    settings_widget_state? sw = await check_and_update_selected_device(false, true);
    if (sw == null) {
      //toast("Please see Pre-connect checklist...");
      return;
    }

    bool connecting = false;
    try {
      connecting = await method_channel.invokeMethod('is_conn_thread_alive');
    } on PlatformException catch (e) {
      toast("WARNING: check _is_connecting failed: $e");
    }

    if (connecting) {
      toast("Connecting - please wait...");
      return;
    }


    String bdaddr = sw.get_selected_bdaddr(widget.pref_service) ?? "";
    if (!gap_mode) {
      if (bdaddr == null || sw.get_selected_bdname(widget.pref_service) == null) {
        toast(
          "Please select your Bluetooth GPS/GNSS Receiver device...",
        );

        Map<dynamic, dynamic> bdaddr_to_name_map = await get_bd_map();
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) {
                return settings_widget(widget.pref_service, bdaddr_to_name_map);
              }
          ),
        );
        return;
      }
    }

    print("main.dart connect() start1");

    _param_map = Map<dynamic, dynamic>(); //clear last conneciton params state...
    String status = "unknown";
    try {
      print("main.dart connect() start connect start");
      final bool ret = await method_channel.invokeMethod('connect',
              {
                "bdaddr": bdaddr,
                'secure': PrefService.of(context).get('secure') ?? true,
                'reconnect' : PrefService.of(context).get('reconnect') ?? false,
                'ble_gap_scan_mode':  gap_mode,
                'log_bt_rx' : log_bt_rx,
                'disable_ntrip' : PrefService.of(context).get('disable_ntrip') ?? false,
                'ntrip_host': PrefService.of(context).get('ntrip_host'),
                'ntrip_port': PrefService.of(context).get('ntrip_port'),
                'ntrip_mountpoint': PrefService.of(context).get('ntrip_mountpoint'),
                'ntrip_user': PrefService.of(context).get('ntrip_user'),
                'ntrip_pass': PrefService.of(context).get('ntrip_pass'),
              }
      );
      print("main.dart connect() start connect done");
      if (ret) {
        status = "Starting connection to:\n"+(sw.get_selected_bdname(widget.pref_service)??"") ?? "(No name)";
      } else {
        status = "Failed to connect...";
        setState(() {
          _main_icon = ICON_NOT_CONNECTED;
          _main_state = "Not connected";
        });
      }

      print("main.dart connect() start2");

    } on PlatformException catch (e) {
      status = "Failed to start connection: '${e.message}'.";
      print(status);
    }

    print("main.dart connect() start3");

    setState(() {
      _status = status;
    });

    print("main.dart connect() start4");

    print("marin.dart connect() done");
  }

  Future<Map<dynamic, dynamic>> get_bd_map() async {
    Map<dynamic, dynamic>? ret = null;
    try {
      ret = await method_channel.invokeMethod<Map<dynamic, dynamic>>('get_bd_map');
      //print("got bt_map: $ret");
    } on PlatformException catch (e) {
      String status = "get_bd_map exception: '${e.message}'.";
      //print(status);
    }
    return ret ?? Map();
  }

  Future<bool> is_bluetooth_on() async {
    bool? ret = false;
    try {
      ret = await method_channel.invokeMethod<bool>('is_bluetooth_on');
    } on PlatformException catch (e) {
      String status = "is_bluetooth_on error: '${e.message}'.";
      print(status);
    }
    return ret!;
  }

  Future<List<String>> check_permissions_not_granted() async {
    List<String> ret = ['failed_to_list_ungranted_permissions'];
    try {
      List<Object?>? _ret = await method_channel.invokeMethod<List<Object?>>('check_permissions_not_granted');
      ret.clear();
      for (Object? o in _ret!) {
        ret.add((o??"").toString());
      }
    } on PlatformException catch (e) {
      String status = "check_permissions_not_granted error: '${e.message}'.";
      print(status);
    }
    return ret;
  }


  Future<bool> is_location_enabled() async {
    bool? ret = false;
    try {
      //print("is_location_enabled try0");
      ret = await method_channel.invokeMethod<bool>('is_location_enabled');
      //print("is_location_enabled got ret: $ret");
    } on PlatformException catch (e) {
      String status = "is_location_enabled exception: '${e.message}'.";
      print(status);
    }
    return ret!;
  }

  Future<bool> is_coarse_location_enabled() async {
    bool? ret = false;
    try {
      //print("is_coarse_location_enabled try0");
      ret = await method_channel.invokeMethod<bool>('is_coarse_location_enabled');
      //print("is_coarse_location_enabled got ret: $ret");
    } on PlatformException catch (e) {
      String status = "is_coarse_location_enabled exception: '${e.message}'.";
      print(status);
    }
    return ret!;
  }


  Future<bool> is_mock_location_enabled() async {
    bool? ret = false;
    try {
      //print("is_mock_location_enabled try0");
      ret = await method_channel.invokeMethod<bool>('is_mock_location_enabled');
      //print("is_mock_location_enabled got ret $ret");
    } on PlatformException catch (e) {
      String status = "is_mock_location_enabled exception: '${e.message}'.";
      print(status);
    }
    return ret!;
  }

}
