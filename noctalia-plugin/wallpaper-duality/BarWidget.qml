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

  property string statusText: ""
  property string statusClass: "none"
  property string statusIcon: "󰱟"

  implicitWidth: 24
  implicitHeight: capsuleHeight

  function refresh() {
    proc.running = true
  }

  Process {
    id: proc
    command: ["sh", "-c", "~/.config/hypr/Scripts/wallpaper-waybar.sh"]
    running: true

    stdout: SplitParser {
      onData: data => {
        try {
          var obj = JSON.parse(data.trim())
          root.statusText = obj.text || ""
          root.statusClass = obj.class || "none"
          var parts = root.statusText.split(" ")
          root.statusIcon = parts.length > 0 ? parts[0] : "󰱟"
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

  RowLayout {
    id: row
    anchors.centerIn: parent
    spacing: 4

    NText {
      text: root.statusIcon
      font.pixelSize: Style.getBarFontSizeForDensity(Settings.getBarDensityForScreen(screenName), capsuleHeight, false) - 1
      color: root.statusClass === "live" ? "#ffb3ad"
           : root.statusClass === "static" ? "#e1c28c"
           : Color.mOnSurface
      Layout.alignment: Qt.AlignVCenter
    }
  }

  MouseArea {
    id: clickArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onClicked: mouse => {
      if (mouse.button === Qt.LeftButton) {
        Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaper-picker.sh"])
      } else if (mouse.button === Qt.RightButton) {
        PanelService.showContextMenu(contextMenu, root, screen)
      }
    }

    onWheel: wheel => {
      if (wheel.angleDelta.y > 0) {
        Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaperctl.sh live"])
      } else {
        Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaperctl.sh static"])
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.random-wallpaper"),
        "action": "random-wallpaper",
        "icon": "dice"
      },
      {
        "label": I18n.tr("actions.toggle-pause"),
        "action": "toggle-pause",
        "icon": "pause"
      },
      {
        "label": I18n.tr("actions.open-picker"),
        "action": "open-picker",
        "icon": "wallpaper-selector"
      },
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
      contextMenu.close()
      PanelService.closeContextMenu(screen)

      if (action === "random-wallpaper") {
        Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaper-picker.sh random"])
      } else if (action === "toggle-pause") {
        Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaperctl.sh toggle"])
      } else if (action === "open-picker") {
        Process.exec("sh", ["-c", "~/.config/hypr/Scripts/wallpaper-picker.sh"])
      } else if (action === "widget-settings") {
        BarService.openPluginSettings(screen, pluginApi.manifest)
      }
    }
  }

  Component.onCompleted: refresh()
}
