import QtQuick
import qs.Commons

// "Label        [-]  value  [+]" row for the settings tab.
Item {
  id: stepper

  property string label: ""
  property string valueText: ""
  property color fg: "white"
  property string fontFamily: ""

  signal decrement()
  signal increment()

  implicitHeight: Style.space(28)

  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: stepper.label
    color: stepper.fg
    font.family: stepper.fontFamily !== "" ? stepper.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  Row {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    Rectangle {
      width: Style.space(24)
      height: Style.space(24)
      radius: Style.space(6)
      color: Qt.rgba(stepper.fg.r, stepper.fg.g, stepper.fg.b, minus.containsMouse ? 0.25 : 0.12)

      Text {
        anchors.centerIn: parent
        text: "\u2212"
        color: stepper.fg
        font.family: stepper.fontFamily !== "" ? stepper.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: minus
        anchors.fill: parent
        hoverEnabled: true
        onClicked: stepper.decrement()
      }
    }

    Text {
      width: Style.space(78)
      height: Style.space(24)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: stepper.valueText
      color: stepper.fg
      font.family: stepper.fontFamily !== "" ? stepper.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Rectangle {
      width: Style.space(24)
      height: Style.space(24)
      radius: Style.space(6)
      color: Qt.rgba(stepper.fg.r, stepper.fg.g, stepper.fg.b, plus.containsMouse ? 0.25 : 0.12)

      Text {
        anchors.centerIn: parent
        text: "+"
        color: stepper.fg
        font.family: stepper.fontFamily !== "" ? stepper.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: plus
        anchors.fill: parent
        hoverEnabled: true
        onClicked: stepper.increment()
      }
    }
  }
}
