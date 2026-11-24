# نقل الملفات (موبايل ← كمبيوتر) عبر الواي فاي

بدون PIN وبدون QR. الموبايل والكمبيوتر لازم على نفس الواي فاي.

## بناء الثلاث نسخ تلقائيًا (الأسهل)
1. اعمل repository على GitHub وارفع محتوى المجلد ده (مع فولدر .github).
2. من تبويب Actions شغّل "Build all" (Run workflow).
3. بعد ~10 دقايق نزّل من Artifacts:
   - android-apk  ← app-release.apk (للموبايل)
   - windows-exe  ← فولدر فيه phone_transfer.exe (لازم تنقل الفولدر كله مش الـ exe لوحده)
   - linux-bundle ← فولدر فيه ملف phone_transfer، شغّله بـ ./phone_transfer (Mint / Ubuntu)

## بناء يدوي على جهازك
```bash
flutter create --platforms=android,windows,linux .   # (يحافظ على lib الحالي، راجع الـ workflow)
python3 tools/patch_manifest.py                      # صلاحيات أندرويد
flutter pub get
flutter build apk --release       # على أي جهاز
flutter build windows --release   # على ويندوز فقط
flutter build linux --release     # على لينكس فقط (محتاج: clang cmake ninja-build pkg-config libgtk-3-dev)
```

## ملاحظات
- النقل في الخلفية على أندرويد عبر Foreground Service (إشعار أثناء النقل).
- أول تشغيل على الكمبيوتر: اسمح للتطبيق في الـ Firewall.
- الملفات بتتحفظ في Downloads/PhoneTransfer.
- بدون PIN: أي جهاز على نفس الشبكة يقدر يبعت للكمبيوتر، فاقفل تطبيق الكمبيوتر وانت على شبكة عامة.
