import QtQuick
import QtQuick.Layouts
import "../js/Schema.js" as Schema
import "../js/Model.js" as Model
import "../controls"

// "How fast dust settles": a tile per ready made speed, each with a little window
// showing how dusty it gets and how soon. Clicking one sets everything it names.
ColumnLayout {
    id: root

    property var svc: null
    readonly property var ui: svc ? svc.ui : null
    property string label: ""
    property string hint: ""
    spacing: ui.px(10)

    Txt { ui: root.ui; Layout.fillWidth: true; text: root.label; font.pixelSize: ui.fs(13); font.weight: Font.DemiBold }
    Txt {
        ui: root.ui
        Layout.fillWidth: true
        visible: root.hint !== ""
        text: root.hint
        wrapMode: Text.WordWrap
        font.pixelSize: ui.fs(10)
        opacity: 0.55
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 4
        columnSpacing: ui.px(8)
        rowSpacing: ui.px(8)

        Repeater {
            model: Schema.presets
            delegate: Rectangle {
                id: tile
                required property var modelData
                readonly property bool on: root.svc !== null && Schema.presetActive(root.svc.cfg, modelData)
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: ui.px(92)
                radius: ui.r(1.4)
                color: on ? ui.accentTint(0.16) : ui.tint(area.containsMouse ? 0.09 : 0.04)
                border.width: on ? 1.5 : 1
                border.color: on ? ui.accent : ui.tint(0.08)
                Behavior on color { enabled: ui.animations; ColorAnimation { duration: 100 } }

                Canvas {   // a window, as dusty as this speed leaves it, with its fade
                    id: art
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: ui.px(9)
                    width: 64
                    height: 34
                    readonly property var set: tile.modelData.set
                    readonly property color ink: root.ui ? root.ui.fg : "white"
                    readonly property color ac: root.ui ? root.ui.accent : "white"
                    readonly property string dust: root.svc ? root.svc.cfg.dustColor : "#8b8378"
                    onInkChanged: requestPaint()
                    onDustChanged: requestPaint()
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const c = Model.rgbOf(dust)
                        const amount = Math.min(1, set.particleDensity * 1.6 + set.powderDensity / 40)
                        const fade = set.minOpacity
                        // the window
                        ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.10 * fade + 0.03)
                        ctx.fillRect(2, 2, width - 4, height - 4)
                        ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.12)
                        ctx.fillRect(2, 2, width - 4, 5)
                        ctx.strokeStyle = "rgba(" + c.r + "," + c.g + "," + c.b + "," + (0.35 + 0.5 * (1 - fade)) + ")"
                        ctx.lineWidth = 1
                        ctx.strokeRect(2.5, 2.5, width - 5, height - 5)
                        // its dust, always the same specks
                        const n = Math.round(30 + amount * 140)
                        const seed = Model.hashStr(tile.modelData.key)
                        for (let i = 0; i < n; i++) {
                            const u = Model.rand01(seed, i, 0), v = 1 - Math.pow(Model.rand01(seed, i, 1), 1.6)
                            const a = (0.25 + 0.6 * Model.rand01(seed, i, 2)) * set.particleOpacity
                            ctx.fillStyle = "rgba(" + c.r + "," + c.g + "," + c.b + "," + a + ")"
                            const sz = 0.8 + Model.rand01(seed, i, 3) * 1.2
                            ctx.fillRect(3 + u * (width - 6), 8 + v * (height - 11), sz, sz)
                        }
                        // a web in a corner when it gets that far
                        if (set.spiderMax >= 2) {
                            ctx.strokeStyle = "rgba(" + c.r + "," + c.g + "," + c.b + ",0.6)"
                            ctx.lineWidth = 0.7
                            for (let s = 0; s < 4; s++) {
                                const ang = Math.PI / 2 * (s / 3)
                                ctx.beginPath(); ctx.moveTo(width - 3, 8)
                                ctx.lineTo(width - 3 - Math.cos(ang) * 10, 8 + Math.sin(ang) * 10); ctx.stroke()
                            }
                            for (const r of [5, 8.5]) { ctx.beginPath(); ctx.arc(width - 3, 8, r, Math.PI / 2, Math.PI); ctx.stroke() }
                        }
                    }
                }
                Txt {
                    ui: root.ui
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: hintText.top
                    anchors.bottomMargin: ui.px(1)
                    text: tile.modelData.label
                    font.pixelSize: ui.fs(11)
                    font.weight: tile.on ? Font.DemiBold : Font.Normal
                    opacity: tile.on ? 1 : 0.85
                }
                Txt {
                    id: hintText
                    ui: root.ui
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: ui.px(7)
                    width: parent.width - ui.px(8)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: tile.modelData.hint
                    font.pixelSize: ui.fs(9)
                    opacity: 0.5
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.svc.applyPreset(tile.modelData.key)
                }
            }
        }
    }
}
