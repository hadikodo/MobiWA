# The accessibility service and activity are referenced by name from the
# manifest / Android settings; keep them (and their members) intact.
-keep class com.mobiwha.mobiwha.** { *; }

# Flutter deferred components reference Play Core classes that this app does
# not ship; don't fail the R8 build on them.
-dontwarn com.google.android.play.core.**
