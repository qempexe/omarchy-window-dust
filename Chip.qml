import QtQuick
import qs.Commons

// Small pill button used for presets and choices in the settings tab.
Item {
  id: chip

  property string text: ""
  property bool selected: false
  property color fg: "white"
  property string swatch: ""        // optional RRGGBB dot
  property string fontFamily: ""

  signal clicked()

  implicitWidth: row.implicitWidth + Style.space(20)
  implicitHeight: Style.space(24)

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Qt.rgba(chip.fg.r, chip.fg.g, chip.fg.b,
                   chip.selected ? 0.22 : (area.containsMouse ? 0.14 : 0.07))
    border.width: 1
    border.color: Qt.rgba(chip.fg.r, chip.fg.g, chip.fg.b, chip.selected ? 0.8 : 0.25)
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(5)

    Rectangle {
      visible: chip.swatch !== ""
      width: Style.space(9)
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: chip.swatch !== "" ? ("#" + chip.swatch) : "transparent"
    }

    Text {
      text: chip.text
      color: chip.fg
      font.family: chip.fontFamily !== "" ? chip.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    onClicked: chip.clicked()
  }
}
