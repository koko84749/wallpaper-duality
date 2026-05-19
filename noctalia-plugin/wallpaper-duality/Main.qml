import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  property var pluginApi: null

  IpcHandler {
    target: "plugin:wallpaper-duality"

    function toggle() {
      Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaperctl.sh toggle"])
    }

    function nextLive() {
      Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaperctl.sh live"])
    }

    function nextStatic() {
      Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaperctl.sh static"])
    }

    function openPicker() {
      Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaper-picker.sh"])
    }
  }
}
