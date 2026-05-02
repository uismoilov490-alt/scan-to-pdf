# google_mlkit_text_recognition — ixtiyoriy yozuv tanlovlari APKga kiritilmaydi,
# lekin plagin ushbu klasslarga havola qiladi. R8 xatosiz yig’ish uchun:
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Firebase Auth — R8 tomonidan o’chirilmasligi uchun
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.android.gms.internal.firebase_auth.** { *; }
-dontwarn com.google.firebase.auth.**
