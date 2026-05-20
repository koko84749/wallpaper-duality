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
      Quickshell.execDetached(["sh", "-c", "/home/hamo/.config/hypr/Scripts/wallpaperctl.sh toggle"])
    }

    function nextLive() {
      Quickshell.execDetached(["sh", "-c", "/home/hamo/.config/hypr/Scripts/wallpaperctl.sh live"])
    }

    function nextStatic() {
      Quickshell.execDetached(["sh", "-c", "/home/hamo/.config/hypr/Scripts/wallpaperctl.sh static"])
    }

    function openPicker() {
      Quickshell.execDetached(["sh", "-c", "/home/hamo/.config/hypr/Scripts/wallpaper-picker.sh"])
    }
  }
}
