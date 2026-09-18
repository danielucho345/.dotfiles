import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

Ui.Button {
  id: row
  required property var windowData
  property bool compact: false
  property string iconSource: ""
  signal activate(string address)
  implicitHeight: Math.max(Style.space(58), labels.implicitHeight + Style.space(20))
  onClicked: activate(windowData.address)
  tooltipText: windowData.name + " — " + windowData.title
  Accessible.name: tooltipText + ", Workspace " + windowData.workspaceName + ", " + windowData.monitor

  Rectangle {
    visible: row.selected
    width: Style.space(2)
    height: parent.height
    color: Color.accent
  }
  RowLayout {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(12)
    Image {
      source: row.iconSource
      Layout.preferredWidth: Style.space(22)
      Layout.preferredHeight: Style.space(22)
      sourceSize.width: Style.space(22)
      sourceSize.height: Style.space(22)
      fillMode: Image.PreserveAspectFit
    }
    ColumnLayout {
      id: labels
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      spacing: Style.space(4)
      Text {
        Layout.fillWidth: true
        text: row.windowData.name
        textFormat: Text.PlainText
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        Layout.fillWidth: true
        text: row.windowData.title
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
    Text {
      visible: row.compact
      text: "WS " + row.windowData.workspaceName + "\n" + row.windowData.monitor
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
    }
  }
}
