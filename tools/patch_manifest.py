p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()

perms = '''<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
    '''

service = '''<service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false"/>
    </application>'''

s = s.replace('<application', 'ARCHOR_APP', 1)
s = s.replace('ARCHOR_APP', perms + '<application android:usesCleartextTraffic="true"', 1)
s = s.replace('</application>', service, 1)
s = s.replace('android:label="phone_transfer"', 'android:label="File Transfer"')
open(p, 'w', encoding='utf-8').write(s)
print('manifest patched')
