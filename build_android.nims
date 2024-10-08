# This script builds an Android application (APK file).
# Copyright (c) 2017-2023 Ramon Santamaria (@raysan5)
# Converted to nimscript by Antonis Geralis (@planetis-m) in 2023
# See the file "LICENSE", included in this distribution,
# for details about the copyright.

import std/[os, strutils, strformat, sugar]
from std/private/globs import nativeToUnixPath

type
  CpuPlatform = enum
    arm, arm64, i386, amd64
  GlEsVersion = enum
    openglEs20 = "GraphicsApiOpenGlEs2"
    openglEs30 = "GraphicsApiOpenGlEs3"
  DeviceOrientation = enum
    portrait, landscape, sensor

proc toArchName(x: CpuPlatform): string =
  case x
  of arm: "armeabi-v7a"
  of arm64: "arm64-v8a"
  of i386: "x86"
  of amd64: "x86_64"

proc toValue(x: GlEsVersion): string =
  case x
  of openglEs20: "0x00020000"
  of openglEs30: "0x00030000"

# Define Android architecture (armeabi-v7a, arm64-v8a, x86, x86-64), GLES and API version
const
  AndroidApiVersion = 33
  AndroidCPUs = [arm64]
  AndroidGlEsVersion = openglEs20

# Required path variables
const
  JavaHome = getEnv"JAVA_HOME"
  AndroidNdk = when defined(GitHubCI): getEnv"GITHUB_WORKSPACE" / "android-ndk" else: getEnv"ANDROID_NDK"
  AndroidHome = when defined(GitHubCI): getEnv"GITHUB_WORKSPACE" / "android-sdk" else: getEnv"ANDROID_HOME"
  AndroidBuildTools = AndroidHome / "build-tools/34.0.0"
  AndroidPlatformTools = AndroidHome / "platform-tools"

# Android project configuration variables
const
  ProjectName = "raylib_game"
  ProjectLibraryName = "main"
  ProjectBuildId = "android"
  ProjectBuildPath = ProjectBuildId & "." & ProjectName
  ProjectResourcesPath = "src/resources"
  ProjectSourceFile = "src/raylib_game.nim"

# Android app configuration variables
const
  AppLabelName = "rGame"
  AppCompanyName = "raylib"
  AppProductName = "rgame"
  AppVersionCode = 1
  AppVersionName = "1.0"
  AppIconLdpi = "logo/raylib_36x36.png"
  AppIconMdpi = "logo/raylib_48x48.png"
  AppIconHdpi = "logo/raylib_72x72.png"
  AppScreenOrientation = landscape
  AppKeystorePass = "raylib"

# mode = ScriptMode.Verbose

task setupAndroid, "Prepare raylib project for Android development":
  # Create required temp directories for APK building
  mkDir(ProjectBuildPath / "src/com" / AppCompanyName / AppProductName)
  for cpu in AndroidCPUs: mkDir(ProjectBuildPath / "lib" / cpu.toArchName)
  mkDir(ProjectBuildPath / "bin")
  mkDir(ProjectBuildPath / "res/drawable-ldpi")
  mkDir(ProjectBuildPath / "res/drawable-mdpi")
  mkDir(ProjectBuildPath / "res/drawable-hdpi")
  mkDir(ProjectBuildPath / "res/values")
  mkDir(ProjectBuildPath / "assets/resources")
  mkDir(ProjectBuildPath / "obj/screens")
  # Copy project required resources: strings.xml, icon.png, assets
  writeFile(ProjectBuildPath / "res/values/strings.xml",
      &"<?xml version='1.0' encoding='utf-8'?>\n<resources><string name='app_name'>{AppLabelName}</string></resources>\n")
  cpFile(AppIconLdpi, ProjectBuildPath / "res/drawable-ldpi/icon.png")
  cpFile(AppIconMdpi, ProjectBuildPath / "res/drawable-mdpi/icon.png")
  cpFile(AppIconHdpi, ProjectBuildPath / "res/drawable-hdpi/icon.png")
  cpDir(ProjectResourcesPath, ProjectBuildPath / "assets/resources")
  # Generate NativeLoader.java to load required shared libraries
  writeFile(ProjectBuildPath / "src/com" / AppCompanyName / AppProductName / "NativeLoader.java", &"""
package com.{AppCompanyName}.{AppProductName};

public class NativeLoader extends android.app.NativeActivity {{
    static {{
        System.loadLibrary("{ProjectLibraryName}");
    }}
}}
""")
  # Generate AndroidManifest.xml with all the required options
  writeFile(ProjectBuildPath / "AndroidManifest.xml", &"""
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
        package="com.{AppCompanyName}.{AppProductName}"
        android:versionCode="{$AppVersionCode}" android:versionName="{AppVersionName}" >
    <uses-sdk android:minSdkVersion="{$AndroidApiVersion}" android:targetSdkVersion="{$AndroidApiVersion}" />
    <uses-feature android:glEsVersion="{AndroidGlEsVersion.toValue}" android:required="true" />
    <application android:allowBackup="false" android:label="@string/app_name" android:icon="@drawable/icon" >
        <activity android:name="com.{AppCompanyName}.{AppProductName}.NativeLoader"
            android:theme="@android:style/Theme.NoTitleBar.Fullscreen"
            android:configChanges="orientation|keyboard|keyboardHidden|screenSize"
            android:screenOrientation="{$AppScreenOrientation}" android:launchMode="singleTask"
            android:resizeableActivity="false"
            android:clearTaskOnLaunch="true"
            android:exported="true">
            <meta-data android:name="android.app.lib_name" android:value="{ProjectLibraryName}" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
""")
  # Generate storekey for APK signing: {ProjectName}.keystore
  let keystorePath = ProjectBuildPath / ProjectName & ".keystore"
  if not fileExists(keystorePath):
    exec(JavaHome / "bin/keytool" & " -genkeypair -validity 10000 -dname \"CN=" & AppCompanyName &
        ",O=Android,C=ES\" -keystore " & keystorePath & " -storepass " & AppKeystorePass &
        " -keypass " & AppKeystorePass & " -alias " & ProjectName & "Key -keyalg RSA -keysize 2048")

task buildAndroid, "Compile and package raylib project for Android":
  # Config project package and resource using AndroidManifest.xml and res/values/strings.xml
  let androidResourcePath = AndroidHome / ("platforms/android-" & $AndroidApiVersion) / "android.jar"
  exec(AndroidBuildTools / "aapt" & " package -f -m -S " & ProjectBuildPath / "res" & " -J " &
      ProjectBuildPath / "src" & " -M " & ProjectBuildPath / "AndroidManifest.xml" & " -I " & androidResourcePath)
  # Compile project code into a shared library: lib/{AndroidArchName}/lib{ProjectLibraryName}.so
  for cpu in AndroidCPUs:
    exec("nim c -d:release --os:android --cpu:" & $cpu & " -d:AndroidApiVersion=" & $AndroidApiVersion &
        " -d:AndroidNdk=" & AndroidNdk & " -d:" & $AndroidGlEsVersion &
        " -o:" & ProjectBuildPath / "lib" / cpu.toArchName / ("lib" & ProjectLibraryName & ".so") &
        " --nimcache:" & nimcacheDir().parentDir / (ProjectName & "_" & $cpu) & " " & ProjectSourceFile)
  # Compile project .java code into .class (Java bytecode)
  exec(JavaHome / "bin/javac" & " -verbose --source 11 --target 11 -d " & ProjectBuildPath / "obj" &
      " --system " & quoteShell(JavaHome) & " --class-path " & androidResourcePath &
      (when defined(windows): ";" else: ":") &
      ProjectBuildPath / "obj" & " --source-path " & ProjectBuildPath / "src" & " " &
      ProjectBuildPath / "src/com" / AppCompanyName / AppProductName / "R.java" & " " &
      ProjectBuildPath / "src/com" / AppCompanyName / AppProductName / "NativeLoader.java")
  # Compile .class files into Dalvik executable bytecode (.dex)
  let classes = collect:
    for f in listFiles(ProjectBuildPath / "obj/com" / AppCompanyName / AppProductName):
      if f.endsWith(".class"): quoteShell(f)
  exec(AndroidBuildTools / (when defined(windows): "d8.bat" else: "d8") &
      " --release --no-desugaring --output " & ProjectBuildPath / "bin" &
      " " & join(classes, " "))
  # Create Android APK package: bin/{ProjectName}.unaligned.apk
  let unalignedApkPath = ProjectBuildPath / "bin" / (ProjectName & ".unaligned.apk")
  let alignedApkPath = ProjectBuildPath / "bin" / (ProjectName & ".aligned.apk")
  rmFile(unalignedApkPath) # fixes rebuilding
  rmFile(alignedApkPath)
  exec(AndroidBuildTools / "aapt" & " package -f -M " & ProjectBuildPath / "AndroidManifest.xml" & " -S " &
      ProjectBuildPath / "res" & " -A " & ProjectBuildPath / "assets" & " -I " & androidResourcePath & " -F " &
      unalignedApkPath & " " & ProjectBuildPath / "bin")
  withDir(ProjectBuildPath):
    for cpu in AndroidCPUs:
      exec(AndroidBuildTools / "aapt" & " add " & "bin" / (ProjectName & ".unaligned.apk") & " " &
          nativeToUnixPath("lib" / cpu.toArchName / ("lib" & ProjectLibraryName & ".so")))
  # Create zip-aligned APK package: bin/{ProjectName}.aligned.apk
  exec(AndroidBuildTools / "zipalign" & " -p -f 4 " & unalignedApkPath & " " & alignedApkPath)
  # Create signed APK package using generated Key: {ProjectName}.apk
  exec(AndroidBuildTools / (when defined(windows): "apksigner.bat" else: "apksigner") &
      " sign --ks " & ProjectBuildPath / (ProjectName & ".keystore") &
      " --ks-pass pass:" & AppKeystorePass & " --key-pass pass:" & AppKeystorePass &
      " --out " & ProjectName & ".apk" & " --ks-key-alias " & ProjectName & "Key" & " " & alignedApkPath)

task info, "Retrieve device compatibility information":
  # Check supported ABI for the device (armeabi-v7a, arm64-v8a, x86, x86_64)
  echo "Checking supported ABI for the device..."
  exec(AndroidPlatformTools / "adb shell getprop ro.product.cpu.abi")
  # Check supported API level for the device (31, 32, 33, ...)
  echo "Checking supported API level for the device..."
  exec(AndroidPlatformTools / "adb shell getprop ro.build.version.sdk")

task logcat, "Display raylib-specific logs from the Android device":
  # Monitorize output log coming from device, only raylib tag
  exec(AndroidPlatformTools / "adb logcat -c")
  exec(AndroidPlatformTools / "adb logcat raylib:V *:S")

task deploy, "Install and monitor raylib project on Android device/emulator":
  # Install and monitorize {ProjectName}.apk to default emulator/device
  exec(AndroidPlatformTools / "adb install " & ProjectName & ".apk")
  logcatTask()
