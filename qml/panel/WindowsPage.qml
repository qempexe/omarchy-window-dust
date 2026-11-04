import QtQuick
import QtQuick.Layouts
import "../js/Model.js" as Model
import "../controls"

// The Windows tab: every window, the dustiest first, with how long it has been left
// alone and how dusty it is. Click a row to focus it (its dust flies off). Each row
// can be wiped, dusted at once, or put on the never-dusted list (also a right click).
Item {
    id: root

    property var svc: null
    readonly property var ui: svc ? svc.ui : null
    readonly property var cfg: svc ? svc.cfg : null
    // the height to fill: the whole tab when this is the only thing on show
    property real fill: 0

    readonly property var entries: svc ? svc.entries : []
    implicitHeight: Math.max(col.implicitHeight, fill)

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: ui.px(8)

        // a summary and the two things you do to all of them
        RowLayout {
            Layout.fillWidth: true
            spacing: ui.px(8)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Txt {
                    ui: root.ui
                    text: !root.cfg ? "" : !root.cfg.enabled ? "Paused"
                        : root.svc.dustyCount === 0 ? "Everything is clean"
                        : root.svc.dustyCount + (root.svc.dustyCount === 1 ? " window is dusty" : " windows are dusty")
                    font.pixelSize: ui.fs(13)
                    font.weight: Font.DemiBold
                }
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Click a window to focus it. Right click it to never dust that app."
                    font.pixelSize: ui.fs(10)
                    opacity: 0.55
                }
            }
            Btn {
                ui: root.ui
                visible: root.svc !== null && root.svc.dustyCount > 0
                text: "Dust everything off"
                onClicked: root.svc.cleanAll()
            }
        }

        Txt {
            ui: root.ui
            visible: root.entries.length === 0
            Layout.topMargin: ui.px(20)
            Layout.alignment: Qt.AlignHCenter
            text: "No windows open."
            opacity: 0.5
        }

        Repeater {
            model: root.entries
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var e: modelData
                Layout.fillWidth: true
                implicitHeight: rowLay.implicitHeight + ui.px(16)
                radius: ui.r(1.4)
                color: rowArea.containsMouse ? ui.tint(0.08) : ui.tint(0.035)
                border.width: 1
                border.color: ui.tint(0.07)
                Behavior on color { enabled: ui.animations; ColorAnimation { duration: 90 } }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(m) {
                        if (m.button === Qt.RightButton) root.svc.toggleExempt(row.e.cls)
                        else { root.svc.scatter(row.e.address); root.svc.focusWindow(row.e.address) }
                    }
                }

                RowLayout {
                    id: rowLay
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: ui.px(10)
                    anchors.rightMargin: ui.px(8)
                    spacing: ui.px(10)

                    // how dusty: a little meter
                    Item {
                        implicitWidth: ui.px(34)
                        implicitHeight: ui.px(26)
                        Rectangle {
                            anchors.fill: parent
                            radius: ui.r(0.8)
                            color: ui.tint(0.06)
                            border.width: 1
                            border.color: ui.tint(0.10)
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 2
                            height: Math.max(0, (parent.height - 4) * row.e.level)
                            radius: ui.r(0.5)
                            color: root.cfg ? root.cfg.dustColor : "#8b8378"
                            opacity: 0.85
                            Behavior on height { enabled: ui.animations; NumberAnimation { duration: 250 } }
                        }
                        Txt {
                            ui: root.ui
                            anchors.centerIn: parent
                            text: row.e.exempt ? "—" : Math.round(row.e.level * 100) + "%"
                            font.pixelSize: ui.fs(9)
                            font.weight: Font.DemiBold
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1
                        Txt {
                            ui: root.ui
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: row.e.title !== "" ? row.e.title : row.e.cls
                            font.pixelSize: ui.fs(12)
                        }
                        Txt {
                            ui: root.ui
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: row.e.cls + "  ·  " + Model.stateText(row.e)
                                + (row.e.exempt ? "" : "  ·  left alone " + Model.idleText(row.e.idleSec))
                            font.pixelSize: ui.fs(10)
                            opacity: 0.55
                        }
                    }

                    Btn {
                        ui: root.ui
                        visible: !row.e.exempt && row.e.level > 0
                        text: "Wipe"
                        onClicked: root.svc.cleanWindow(row.e.address)
                    }
                    Btn {
                        ui: root.ui
                        visible: !row.e.exempt && row.e.level < 1 && root.cfg && root.cfg.enabled
                        text: "Dust it"
                        onClicked: root.svc.dustWindow(row.e.address)
                    }
                    Btn {
                        ui: root.ui
                        active: row.e.exempt
                        text: row.e.exempt ? "Allow dust" : "Never"
                        onClicked: root.svc.toggleExempt(row.e.cls)
                    }
                }
            }
        }
    }
}
