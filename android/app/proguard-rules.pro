# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Preservar clases de aplicación
-keep class com.simert.estacionamientotarifado.** { *; }

# Blue Thermal Printer
-keep class com.example.blue_thermal_printer.** { *; }
-keep class android.bluetooth.** { *; }

# OnesignaL
-keep class com.onesignal.** { *; }

# Preservar enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Preservar métodos onCreate
-keepclasseswithmembernames class * {
    native <methods>;
}

# Reducir tamaño de recursos
-dontshrink
-dontobfuscate
