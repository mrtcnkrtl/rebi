# Release derlemesi R8 ile küçültülür. AdMob (play-services-ads) WorkManager 2.7.0 + Room 2.2.5 getirir; Room veritabanı
# sınıfını (androidx.work.impl.WorkDatabase_Impl) yansımayla, boş kurucusuyla oluşturur. R8 tam modu bu kurucuyu siler
# ve uygulama açılışta "Failed to create an instance of androidx.work.impl.WorkDatabase" ile çöker (1.2.0+16).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
