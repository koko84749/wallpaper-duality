import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var pluginApi: null

  readonly property string screenName: screen?.name ?? ""
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

  property string statusIcon: "󰋩"
  property string statusClass: "static"

  implicitWidth: 24
  implicitHeight: capsuleHeight

  Process {
    id: proc
    command: ["sh", "-c", "/home/hamo/.config/hypr/Scripts/wallpaper-waybar.sh"]
    running: true

    stdout: SplitParser {
      onRead: data => {
        try {
          var obj = JSON.parse(data.trim())
          var parts = (obj.text || "󰱟").split(" ")
          root.statusIcon = parts.length > 0 ? parts[0] : "󰱟"
          root.statusClass = obj.class || "none"
        } catch (e) {}
      }
    }

    onExited: {
      timer.restart()
    }
  }

  Timer {
    id: timer
    interval: 5000
    repeat: true
    onTriggered: proc.running = true
  }

  NText {
    anchors.centerIn: parent
    text: root.statusIcon
    font.pixelSize: 14
    color: root.statusClass === "live" ? "#ffb3ad"
         : root.statusClass === "static" ? "#e1c28c"
         : Color.mOnSurface
  }

  MouseArea {
    id: clickArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onClicked: mouse => {
      if (mouse.button === Qt.LeftButton) {
        Process.exec("sh", ["-c", "/home/hamo/.config/hypr/Scripts/wallpaper-picker.sh"])
      } else if (mouse.button === Qt.RightButton) {
        PanelService.showContextMenu(contextMenu, root, screen)
      }
    }

    onWheel: wheel => {
      if (wheel.angleDelta.y > 0) {
        Process.exec("sh", ["-c", "/home/hamo/.config/hypr/Scripts/wallpaperctl.sh live"])
      } else {
        Process.exec("sh", ["-c", "/home/hamo/.config/hypr/Scripts/wallpaperctl.sh static"])
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      { "label": "Random", "action": "random-wallpaper", "icon": "dice" },
      { "label": "Toggle pause", "action": "toggle-pause", "icon": "pause" },
      { "label": "Picker", "action": "open-picker", "icon": "wallpaper-selector" },
      { "label": "Settings", "action": "widget-settings", "icon": "settings" },
    ]

    onTriggered: action => {
      contextMenu.close()
      PanelService.closeContextMenu(screen)
      if (action === "random-wallpaper")
        Process.exec("sh", ["-c", "/home/hamo/.config/hypr/Scripts/wallpaper-picker.sh random"])
      else if (action === "toggle-pause")
        Process.exec("sh", ["-c", "/home/hamo/.config/hypr/Scripts/wallpaperctl.sh toggle"])
      else if (action === "open-picker")
        Process.exec("sh", ["-c", "/home/hamo/.config/hypr/Scripts/wallpaper-picker.sh"])
      else if (action === "widget-settings")
        BarService.openPluginSettings(screen, pluginApi.manifest)
    }
  }
}
