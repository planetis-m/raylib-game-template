import std/[strutils, os]

mode = ScriptMode.Verbose

proc appendToGithubFile(envVar: string, pairs: openarray[(string, string)]) =
  let filename = getEnv(envVar, "")
  if filename != "":
    var content = ""
    if fileExists(filename):
      content = readFile(filename)
    for key, val in pairs.items:
      content.add key & "=" & val & "\n"
    writeFile(filename, content)
  else:
    echo envVar, " is not set."

template myExec(command, input: string, cache = "") =
  let (output, exitCode) = gorgeEx(command, input, cache)
  echo output
  if exitCode != 0:
    raise newException(OSError, "FAILED: " & command)

template verifyHash(filename, expected, cmd: string) =
  myExec(cmd & " -c -", input = expected & " " & filename)

proc verifySha256(filename, expected: string) =
  verifyHash(filename, expected, "sha256sum")

proc verifySha1(filename, expected: string) =
  verifyHash(filename, expected, "sha1sum")

template toBat(x: string): string =
  (when defined(windows): x & ".bat" else: x)

# Environment variables
const
  JavaHome = when defined(GitHubCI): getEnv"JAVA_HOME" else: "/usr/lib/jvm/default-runtime"
  AndroidNdk = (when defined(GitHubCI): getEnv"GITHUB_WORKSPACE" else: thisDir()) / "android-ndk"
  AndroidHome = (when defined(GitHubCI): getEnv"GITHUB_WORKSPACE" else: thisDir()) / "android-sdk"
  CommandLineToolsZip = "commandlinetools-linux-11076708_latest.zip"
  CommandLineToolsSha256 = "2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258"
  AndroidNdkZip = "android-ndk-r26d-linux.zip"
  AndroidNdkSha1 = "fcdad75a765a46a9cf6560353f480db251d14765"
  AndroidApiVersion = 33

task setupBuildEnv, "Set up Android SDK/NDK":
  # Set up Android SDK
  exec "wget -nv https://dl.google.com/android/repository/" & CommandLineToolsZip
  verifySha256(CommandLineToolsZip, CommandLineToolsSha256)
  myExec("unzip -q " & CommandLineToolsZip & " -d " & AndroidHome, input = "A")
  let sdkmanagerPath = AndroidHome / "cmdline-tools/bin" / "sdkmanager".toBat
  echo "SDKMANAGER EXISTS: ", fileExists(sdkmanagerPath)
  echo "home ", dirExists(AndroidHome)
  echo "bin ", dirExists(AndroidHome / "cmdline-tools/bin")
  echo "list files ", listFiles(AndroidHome / "cmdline-tools/bin")
  myExec(sdkmanagerPath & " --licenses --sdk_root=" & AndroidHome, input = "y\n".repeat(8))
  exec sdkmanagerPath & " --update --sdk_root=" & AndroidHome
  exec sdkmanagerPath & " --install \"build-tools;34.0.0\" --sdk_root=" & AndroidHome
  exec sdkmanagerPath & " --install \"platform-tools\" --sdk_root=" & AndroidHome
  exec sdkmanagerPath & " --install \"platforms;android-" & $AndroidApiVersion & "\" --sdk_root=" & AndroidHome
  when not defined(GitHubCI) and defined(windows):
    exec sdkmanagerPath & " --install extras;google;usb_driver --sdk_root=" & AndroidHome
  # Set up Android NDK
  exec "wget -nv https://dl.google.com/android/repository/" & AndroidNdkZip
  verifySha1(AndroidNdkZip, AndroidNdkSha1)
  myExec("unzip -q " & AndroidNdkZip, input = "A")
  mvDir(thisDir() / "android-ndk-r26d", AndroidNdk)
  when defined(GitHubCI):
    appendToGithubFile("GITHUB_ENV", {"ANDROID_HOME": AndroidHome, "ANDROID_NDK": AndroidNdk})