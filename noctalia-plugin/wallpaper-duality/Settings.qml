import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Widgets

Item {
  property var pluginApi: null
  property var settings: ({})

  ColumnLayout {
    anchors.fill: parent

    NText {
      text: "Wallpaper Duality"
      font.pixelSize: 16
      font.bold: true
      Layout.fillWidth: true
      Layout.topMargin: 16
    }

    NText {
      text: "Bar widget showing current wallpaper status from wallpaper-duality."
      font.pixelSize: 12
      color: Color.mOnSurfaceVariant
      Layout.fillWidth: true
      Layout.bottomMargin: 16
    }

    NLabel {
      text: "Refresh interval (seconds):"
    }
    NSpinBox {
      id: intervalBox
      from: 1
      to: 60
      value: settings.refreshInterval ?? 5
      onValueChanged: settings.refreshInterval = value
    }

    NToggle {
      id: tooltipToggle
      text: "Show tooltip"
      checked: settings.showTooltip ?? true
      onCheckedChanged: settings.showTooltip = checked
    }
  }
}
