pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Settings.js" as Settings

// Popup with two tabs: Windows (what is dusty, click to focus) and Settings (built from Settings.js).
PopupWindow {
    id: root

    // injected by BarWidget
    property var bar: null
    property var barObject: bar                // the shell's bar, a hint for which edge it sits on
    property bool vertical: false              // bar is on the left / right edge
    property var probeBg: undefined            // bar colours from the Foreground probe (when `bar` has none)
    property var probeFg: undefined
    property var anchorItem: null
    property var hostWidget: null
    property var widget: null

    // The shell's live bar colours. `bar.background` / `bar.foreground` are the documented ones;
    // `barBackground` / `barForeground` on the base Panel are a second source when they exist.
    readonly property var shellBgColor: (root.bar && root.bar.background !== undefined) ? root.bar.background
                                       : root.probeBg
    readonly property var shellFgColor: (root.bar && root.bar.foreground !== undefined) ? root.bar.foreground
                                       : root.probeFg

    property string currentTab: "windows"
    readonly property var cfg: widget ? widget.cfg : Model.normalizeConfig({})

    // Colours. "Follow Omarchy" uses the shell's own bar colours, so a light Omarchy theme comes out
    // light and a dark one dark. The Omarchy theme only supplies the accent.
    // Custom, Brown and Monochrome use the widget's own colours.
    readonly property bool useBarColors: !!widget && widget.cfg.theme === "follow"
        && root.shellBgColor !== undefined && root.shellFgColor !== undefined
    readonly property color fg: useBarColors ? root.shellFgColor : (widget ? widget.colors.text : "#e0e0e0")
    readonly property color panelBg: {
        if (useBarColors) { var c = root.shellBgColor; return Qt.rgba(c.r, c.g, c.b, 1) }   // never translucent
        return widget ? widget.colors.background : "#141414"
    }
    readonly property color accent: {
        if (useBarColors) {
            var a = widget.themeAccent
            return Model.isHex(a) ? Qt.color(a) : root.shellFgColor
        }
        return widget ? widget.colors.accent : "#aaaaaa"
    }
    readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.56)
    readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }
    function accentTint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a) }
    function luma(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
    readonly property color inkOnAccent: luma(accent) > 0.55 ? Qt.rgba(0.07, 0.07, 0.09, 1) : Qt.rgba(0.97, 0.97, 0.98, 1)

    readonly property string statusLine: !widget ? "Starting\u2026"
        : Model.statusText(widget.cfg.enabled, widget.dustyCount, widget.dustEntries.length)

    readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    readonly property int fsMain: Math.max(10, Math.round(Style.font.body * 0.9))
    readonly property int fsSub: Math.max(9, Math.round(Style.font.body * 0.8))

    // On / off switch.
    component Sw: Rectangle {
        id: sw
        property bool on: false
        property color ink: "white"
        property color accent: "white"
        property color knob: "black"
        signal flipped()
        implicitWidth: 34
        implicitHeight: 18
        radius: 9
        color: on ? accent : Qt.rgba(ink.r, ink.g, ink.b, 0.18)
        Behavior on color { ColorAnimation { duration: 100 } }
        Rectangle {
            width: 12; height: 12; radius: 6
            y: 3
            x: sw.on ? sw.width - width - 3 : 3
            color: sw.on ? sw.knob : sw.ink
            opacity: sw.on ? 1 : 0.7
            Behavior on x { NumberAnimation { duration: 100 } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.flipped() }
    }

    // The windows that are dusty right now, dustiest first.
    readonly property var dustRows: widget
        ? widget.dustEntries.filter(function (e) { return e.step > 0 }).slice(0, 10)
        : []

    readonly property bool opened: visible
    function open() { if (!root.visible) root.toggle() }
    function close() { root.visible = false }
    function openTab(tab) { root.currentTab = tab; root.open() }

    // Which colour role the custom picker edits (a panel-local choice, not a setting).
    property string colorRole: "customBackground"
    readonly property var colorRoles: [
        { key: "customBackground", label: "Background" },
        { key: "customText", label: "Text" },
        { key: "customAccent", label: "Accent" }
    ]

    // Shown option label for an enum value.
    function labelFor(d, value) {
        var i = d.options.indexOf(value)
        return i >= 0 && d.labels ? d.labels[i] : String(value)
    }

    // Rows of the Settings tab: a header per group, then each visible setting.
    // Built from these three switches only, so typing in a field never rebuilds the list.
    readonly property string themeChoice: root.widget ? root.widget.cfg.theme : "follow"
    readonly property bool particlesOn: root.widget ? root.widget.cfg.particles === true : true
    readonly property bool awayOn: root.widget ? root.widget.cfg.pauseWhenAway === true : true
    readonly property var settingRows: buildRows(themeChoice, particlesOn, awayOn)
    function buildRows(theme, particles, away) {
        var rows = [], lastGroup = ""
        var schema = Settings.SCHEMA
        for (var i = 0; i < schema.length; i++) {
            var d = schema[i]
            if (d.ui === "hidden") continue
            if (d.showWhen && d.showWhen !== theme) continue
            if (d.requires === "particles" && !particles) continue
            if (d.requires === "away" && !away) continue
            if (d.group !== lastGroup) { rows.push({ type: "header", label: d.group }); lastGroup = d.group }
            rows.push(d)
        }
        return rows
    }

    // ---- placement: never overlap the bar -----------------------------------------
    // Worked out each time the panel is about to open (see toggle()), because the
    // bar's position is not known yet when this file is first loaded.
    //
    // The panel is anchored to the outer edge of the bar's own window (not to the
    // widget, which sits inside the bar's padding), and the gap is transparent
    // padding inside the popup window, so it works whatever the compositor does
    // with anchor margins.
    property bool barAtTop: true              // horizontal bar: top edge (else bottom)
    property bool barAtLeft: true             // vertical bar: left edge (else right)
    property bool useRect: false              // anchor to the bar window's edge
    property var anchorWin: null
    property real rectX: 0
    property real rectY: 0
    property real rectW: 1
    property real rectH: 1
    property real extra: 0                    // extra clearance when only the widget is known
    property real maxHeight: 620
    readonly property int gap: 0              // free space between the bar and the panel (0 = flush)
    readonly property real padTop: (!vertical && barAtTop) ? gap + extra : 0
    readonly property real padBottom: (!vertical && !barAtTop) ? gap + extra : 0
    readonly property real padLeft: (vertical && barAtLeft) ? gap + extra : 0
    readonly property real padRight: (vertical && !barAtLeft) ? gap + extra : 0

    function sideFromText(v) {
        var t = String(v === undefined || v === null ? "" : v).toLowerCase()
        if (t.indexOf("top") >= 0) return "top"
        if (t.indexOf("bottom") >= 0) return "bottom"
        if (t.indexOf("left") >= 0) return "left"
        if (t.indexOf("right") >= 0) return "right"
        return ""
    }

    function locate() {
        var item = root.anchorItem
        if (!item) return
        var scr = item.screen
        var sw = scr ? scr.width : 1920
        var sh = scr ? scr.height : 1080
        var side = ""
        var qsWin = null
        var win = null

        // 1. the bar window knows which edges it is attached to
        try { qsWin = item.QsWindow.window } catch (e0) { qsWin = null }
        try { win = qsWin ? qsWin : item.Window.window } catch (e1) { win = null }
        try {
            var an = win ? win.anchors : null
            if (an) {
                if (root.vertical) {
                    if (an.left && !an.right) side = "left"
                    else if (an.right && !an.left) side = "right"
                } else {
                    if (an.top && !an.bottom) side = "top"
                    else if (an.bottom && !an.top) side = "bottom"
                }
            }
        } catch (e2) { side = "" }

        // 2. the shell's bar object may say it outright
        if (side === "" && root.barObject) {
            var names = ["position", "barPosition", "edge", "side", "location", "placement", "barSide"]
            for (var i = 0; i < names.length && side === ""; i++) {
                var got = ""
                try { got = root.sideFromText(root.barObject[names[i]]) } catch (e3) { got = "" }
                if ((root.vertical && (got === "left" || got === "right"))
                        || (!root.vertical && (got === "top" || got === "bottom")))
                    side = got
            }
        }

        // 3. last resort: which half of the screen (only meaningful when the bar
        //    window is as big as the screen)
        var pos = item.mapToItem(null, 0, 0)
        if (side === "") {
            if (root.vertical) side = pos.x < sw / 2 ? "left" : "right"
            else side = pos.y < sh / 2 ? "top" : "bottom"
        }
        root.barAtTop = side === "top"
        root.barAtLeft = side === "left"

        // Anchor rectangle on the bar window's outer edge (window coordinates).
        var ww = (win && win.width > 0) ? win.width : 0
        var wh = (win && win.height > 0) ? win.height : 0
        var small = root.vertical ? (ww > 0 && ww < sw * 0.5) : (wh > 0 && wh < sh * 0.5)
        root.useRect = !!qsWin && small
        root.anchorWin = qsWin
        if (root.useRect) {
            if (root.vertical) {
                root.rectW = 1
                root.rectH = Math.max(1, item.height)
                root.rectY = pos.y
                root.rectX = side === "left" ? Math.max(0, ww - 1) : 0
            } else {
                root.rectW = Math.max(1, item.width)
                root.rectH = 1
                root.rectX = pos.x
                root.rectY = side === "top" ? Math.max(0, wh - 1) : 0
            }
            root.extra = 0
        } else {
            root.extra = 6                    // only the widget is known: allow a little for bar padding
        }

        // Tallest the panel may be and still fit between the bar and the far edge.
        var thick = (!root.vertical && wh > 0 && wh < sh * 0.5) ? wh : 40
        var room = root.vertical ? sh - 40 : sh - thick - root.gap - root.extra - 16
        root.maxHeight = Math.max(300, Math.min(680, room))
    }

    function toggle() {
        // A click on the widget while the panel is open first closes it as an
        // "outside click" (below); don't let the same click open it again.
        if (!root.visible && Date.now() - root.grabClosedAt < 500) return
        if (!root.visible) root.locate()
        root.visible = !root.visible
    }

    // ---- click outside to close -----------------------------------------------------
    // Hyprland's focus grab reports any click outside the panel. It is created at
    // runtime so a shell without that module simply keeps the X button and Esc.
    property var grab: null
    property double grabClosedAt: 0

    Component.onCompleted: {
        try {
            var g = Qt.createQmlObject(
                'import Quickshell.Hyprland\nHyprlandFocusGrab { }', root, "WindowDustFocusGrab")
            g.windows = [root]
            g.cleared.connect(function() {
                root.grabClosedAt = Date.now()
                root.visible = false
            })
            root.grab = g
        } catch (e) {
            root.grab = null
        }
    }

    // ---- window geometry -------------------------------------------------------
    visible: false
    color: "transparent"
    // Windows grows with the number of dusty rows; Settings is a fixed, scrolling page.
    readonly property real wantHeight: Style.space(currentTab === "settings" ? 640
        : 300 + Math.min(dustRows.length, 8) * 58)
    implicitWidth: Style.space(520) + root.padLeft + root.padRight
    implicitHeight: Math.min(root.maxHeight, wantHeight) + root.padTop + root.padBottom

    anchor.item: root.useRect ? null : root.anchorItem
    anchor.window: root.useRect ? root.anchorWin : null
    anchor.rect.x: root.rectX
    anchor.rect.y: root.rectY
    anchor.rect.width: root.rectW
    anchor.rect.height: root.rectH
    // The panel opens on the side of the anchor facing away from the bar.
    anchor.edges: root.vertical ? (root.barAtLeft ? Edges.Right : Edges.Left)
                                : (root.barAtTop ? Edges.Bottom : Edges.Top)
    anchor.gravity: root.vertical ? (root.barAtLeft ? Edges.Right : Edges.Left)
                                  : (root.barAtTop ? Edges.Bottom : Edges.Top)
    // Only slide along the bar, never across it, so the panel can't be pushed onto the bar.
    anchor.adjustment: root.vertical ? PopupAdjustment.SlideY : PopupAdjustment.SlideX

    onVisibleChanged: {
        if (root.grab) Qt.callLater(function() { root.grab.active = root.visible })
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: root.visible = false
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.padTop
        anchors.bottomMargin: root.padBottom
        anchors.leftMargin: root.padLeft
        anchors.rightMargin: root.padRight
        color: root.panelBg
        border.color: root.tint(0.14)
        border.width: 1
        radius: 12
        clip: true

        Item {
            id: card
            anchors.fill: parent

            // ── header card: on/off switch, name and status, close ──
            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                height: Style.space(60)

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: root.tint(0.05)
                    border.width: 1
                    border.color: root.tint(0.08)
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Sw {
                        Layout.alignment: Qt.AlignVCenter
                        ink: root.fg
                        accent: root.accent
                        knob: root.inkOnAccent
                        on: !!root.widget && root.widget.cfg.enabled
                        onFlipped: if (root.widget) root.widget.setValue("enabled", !root.widget.cfg.enabled)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: "Window Dust"
                            color: root.fg
                            font.family: root.fontFamily
                            font.pixelSize: root.fsSub + 2
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.statusLine
                            color: root.fg
                            opacity: 0.6
                            font.family: root.fontFamily
                            font.pixelSize: root.fsSub
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 24; implicitHeight: 24; radius: 6
                        color: closeArea.containsMouse ? root.tint(0.16) : root.tint(0.08)
                        Text {
                            anchors.centerIn: parent
                            text: "\u00d7"
                            color: root.fg
                            font.pixelSize: 15
                            textFormat: Text.PlainText
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }
            }

            // ── tabs: plain labels, a thin line under the row, an accent bar under the active one ──
            Item {
                id: tabs
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: header.bottom
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                height: 30

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: root.tint(0.10)
                }
                RowLayout {
                    anchors.fill: parent
                    spacing: 0
                    Repeater {
                        model: [
                            { key: "windows", label: "Windows" },
                            { key: "settings", label: "Settings" }
                        ]
                        delegate: Item {
                            id: tabItem
                            required property var modelData
                            readonly property bool on: root.currentTab === tabItem.modelData.key
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -1
                                text: tabItem.modelData.label
                                color: root.fg
                                opacity: tabItem.on ? 1.0 : (tabArea.containsMouse ? 0.8 : 0.5)
                                font.family: root.fontFamily
                                font.pixelSize: root.fsSub + 1
                                font.weight: tabItem.on ? Font.DemiBold : Font.Normal
                                textFormat: Text.PlainText
                            }
                            Rectangle {
                                visible: tabItem.on
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 2
                                radius: 1
                                color: root.accent
                            }
                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentTab = tabItem.modelData.key
                            }
                        }
                    }
                }
            }

            // ── footer ──
            RowLayout {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.bottomMargin: 10
                height: 16
                spacing: 6
                Rectangle {
                    implicitWidth: escLabel.implicitWidth + 10
                    implicitHeight: 16
                    radius: 4
                    color: root.tint(0.08)
                    Text {
                        id: escLabel
                        anchors.centerIn: parent
                        text: "Esc"
                        color: root.fg
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: 8
                        textFormat: Text.PlainText
                    }
                }
                Text {
                    text: "close"
                    color: root.fg
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: 8
                    textFormat: Text.PlainText
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "Changes apply instantly"
                    color: root.fg
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: 8
                    textFormat: Text.PlainText
                }
            }

            // pages
            StackLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: tabs.bottom
                anchors.bottom: footer.top
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                anchors.bottomMargin: 10
                currentIndex: ["windows", "settings"].indexOf(root.currentTab)

                // WINDOWS
                Rectangle {
                    radius: 10
                    color: root.tint(0.035)
                    border.width: 1
                    border.color: root.tint(0.07)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: Style.space(10)

                        SectionLabel {
                            Layout.fillWidth: true
                            visible: root.dustRows.length > 0
                            text: "Dusty windows"
                            foreground: root.fg
                            fontFamily: root.fontFamily
                            pixelSize: root.fsSub
                        }

                        ListView {
                            id: dustList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: Style.space(6)
                            model: root.dustRows
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: dRow
                                required property var modelData
                                width: dustList.width
                                height: Style.space(52)
                                radius: 8
                                color: dMouse.containsMouse ? root.tint(0.10) : root.tint(0.06)

                                Column {
                                    anchors.left: parent.left
                                    anchors.right: dIdle.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Style.space(14)
                                    anchors.rightMargin: Style.space(8)
                                    spacing: Style.space(3)
                                    Text {
                                        width: parent.width
                                        text: dRow.modelData.cls !== "" ? dRow.modelData.cls : "window"
                                        color: root.fg
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fsMain
                                        font.bold: true
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                    }
                                    Text {
                                        width: parent.width
                                        text: dRow.modelData.title
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fsSub
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                    }
                                }
                                Text {
                                    id: dIdle
                                    anchors.right: parent.right
                                    anchors.rightMargin: Style.space(14)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Math.round(dRow.modelData.level * 100) + "%  \u00b7  " + Model.formatIdle(dRow.modelData.idleSec)
                                    color: root.fg
                                    opacity: 0.7
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fsSub
                                    textFormat: Text.PlainText
                                }
                                // how dusty it is: an accent line along the bottom edge
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    height: 2
                                    radius: 1
                                    width: parent.width * dRow.modelData.level
                                    color: root.accentTint(0.8)
                                }
                                MouseArea {
                                    id: dMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function (mouse) {
                                        if (!root.widget) return
                                        if (mouse.button === Qt.RightButton) {
                                            root.widget.toggleExempt(dRow.modelData.cls)
                                        } else {
                                            root.widget.scatterAt(dRow.modelData.address)
                                            root.widget.focusWindow(dRow.modelData.address)
                                            root.close()
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: dustList.count === 0
                                width: parent.width - Style.space(40)
                                text: root.widget && !root.widget.cfg.enabled
                                      ? "Window Dust is paused. Windows keep their current dust until you resume."
                                      : "Everything is clean."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: root.fsMain
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                                textFormat: Text.PlainText
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            FlatButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(36)
                                visible: root.dustRows.length > 0
                                outlined: true
                                selected: true
                                text: "Dust everything off"
                                foreground: root.fg
                                accent: root.accent
                                fontFamily: root.fontFamily
                                pixelSize: root.fsMain
                                onClicked: root.widget.wipeAll()
                            }
                            FlatButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(36)
                                outlined: true
                                text: root.widget && root.widget.cfg.enabled ? "Pause" : "Resume"
                                foreground: root.fg
                                accent: root.accent
                                fontFamily: root.fontFamily
                                pixelSize: root.fsMain
                                onClicked: root.widget.setValue("enabled", !root.widget.cfg.enabled)
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.dustRows.length > 0
                            text: "Click a window to focus it. Right-click to never dust that app."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: root.fsSub
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                        }
                    }
                }

                // SETTINGS (built from Settings.js: grouped, every option visible, applied at once)
                Flickable {
                    id: settingsFlick
                    contentHeight: settingsCol.implicitHeight + Style.space(24)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Rectangle {
                        x: 0; y: 0
                        width: settingsFlick.width
                        height: settingsCol.implicitHeight
                        radius: 10
                        color: root.tint(0.035)
                        border.width: 1
                        border.color: root.tint(0.07)
                    }

                    ColumnLayout {
                        id: settingsCol
                        width: settingsFlick.width
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: Style.space(12)
                            Layout.rightMargin: Style.space(12)
                            Layout.topMargin: Style.space(12)
                            Layout.bottomMargin: Style.space(4)
                            text: "Saved to ~/.config/omarchy/window-dust.json. Edit it by hand and it applies live."
                            wrapMode: Text.Wrap
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: root.fsSub
                            textFormat: Text.PlainText
                        }

                        Repeater {
                            // built only while the panel is open, so no text field keeps focus after it closes
                            model: root.opened ? root.settingRows : []
                            delegate: Item {
                                id: row
                                required property var modelData
                                Layout.fillWidth: true
                                readonly property bool isHeader: modelData.type === "header"
                                readonly property int pad: Style.space(12)
                                readonly property real innerWidth: width - pad * 2
                                implicitHeight: content.implicitHeight + (isHeader ? 0 : pad * 2)

                                // thin divider under each setting (the whole list sits in one card)
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: row.pad
                                    anchors.rightMargin: row.pad
                                    height: 1
                                    visible: !row.isHeader
                                    color: root.tint(0.07)
                                }

                                Component {
                                    id: headerC
                                    Item {
                                        width: row.innerWidth
                                        height: Style.space(40)
                                        Text {
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: Style.space(4)
                                            text: row.modelData.label.toUpperCase()
                                            color: root.accent
                                            font.family: root.fontFamily
                                            font.pixelSize: root.fsSub
                                            font.bold: true
                                            font.letterSpacing: 1
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }

                                Component {
                                    id: labelsC
                                    // label and description, with room on the right for a control
                                    Column {
                                        width: row.innerWidth
                                        spacing: Style.space(2)
                                        Text {
                                            width: parent.width
                                            text: row.modelData.label
                                            color: root.fg
                                            font.family: root.fontFamily
                                            font.pixelSize: root.fsMain
                                            wrapMode: Text.Wrap
                                            textFormat: Text.PlainText
                                        }
                                        Text {
                                            width: parent.width
                                            text: row.modelData.description
                                            color: root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: root.fsSub
                                            wrapMode: Text.Wrap
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }

                                // on / off: a switch
                                Component {
                                    id: boolC
                                    Item {
                                        width: row.innerWidth
                                        height: Math.max(labelBlock.height, Style.space(34)) + Style.space(12)
                                        Loader { id: labelBlock; sourceComponent: labelsC; width: parent.width - Style.space(60); anchors.verticalCenter: parent.verticalCenter }
                                        Sw {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            ink: root.fg
                                            accent: root.accent
                                            knob: root.inkOnAccent
                                            on: root.cfg[row.modelData.key] === true
                                            onFlipped: root.widget.setValue(row.modelData.key, !(root.cfg[row.modelData.key] === true))
                                        }
                                    }
                                }

                                // a value that steps through a fixed list, with − and +
                                Component {
                                    id: stepC
                                    Item {
                                        width: row.innerWidth
                                        height: Math.max(labelBlockStep.height, Style.space(34)) + Style.space(12)
                                        Loader { id: labelBlockStep; sourceComponent: labelsC; width: parent.width - Style.space(200); anchors.verticalCenter: parent.verticalCenter }
                                        Row {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Style.space(6)
                                            FlatButton {
                                                text: "\u2212"
                                                outlined: true
                                                implicitHeight: Style.space(30)
                                                hPad: Style.space(12)
                                                foreground: root.fg
                                                accent: root.accent
                                                fontFamily: root.fontFamily
                                                pixelSize: root.fsMain
                                                onClicked: root.widget.setValue(row.modelData.key,
                                                    Model.stepOption(Model.OPTIONS[row.modelData.key], root.cfg[row.modelData.key], -1))
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Style.space(84)
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Model.formatSetting(row.modelData.fmt, root.cfg[row.modelData.key])
                                                color: root.fg
                                                font.family: root.fontFamily
                                                font.pixelSize: root.fsMain
                                                textFormat: Text.PlainText
                                            }
                                            FlatButton {
                                                text: "+"
                                                outlined: true
                                                implicitHeight: Style.space(30)
                                                hPad: Style.space(12)
                                                foreground: root.fg
                                                accent: root.accent
                                                fontFamily: root.fontFamily
                                                pixelSize: root.fsMain
                                                onClicked: root.widget.setValue(row.modelData.key,
                                                    Model.stepOption(Model.OPTIONS[row.modelData.key], root.cfg[row.modelData.key], 1))
                                            }
                                        }
                                    }
                                }

                                // a choice: every option is a button, the current one is filled
                                Component {
                                    id: enumC
                                    Column {
                                        width: row.innerWidth
                                        spacing: Style.space(8)
                                        Loader { sourceComponent: labelsC; width: parent.width }
                                        Flow {
                                            width: parent.width
                                            spacing: Style.space(6)
                                            Repeater {
                                                model: row.modelData.options
                                                delegate: FlatButton {
                                                    id: choice
                                                    required property string modelData
                                                    outlined: true
                                                    selected: root.cfg[row.modelData.key] === choice.modelData
                                                    implicitHeight: Style.space(30)
                                                    text: root.labelFor(row.modelData, choice.modelData)
                                                    foreground: root.fg
                                                    accent: root.accent
                                                    fontFamily: root.fontFamily
                                                    pixelSize: root.fsSub
                                                    onClicked: root.widget.setValue(row.modelData.key, choice.modelData)
                                                }
                                            }
                                        }
                                    }
                                }

                                // presets: several settings at once
                                Component {
                                    id: presetC
                                    Column {
                                        width: row.innerWidth
                                        spacing: Style.space(8)
                                        Loader { sourceComponent: labelsC; width: parent.width }
                                        Flow {
                                            width: parent.width
                                            spacing: Style.space(6)
                                            Repeater {
                                                model: Model.PRESETS
                                                delegate: FlatButton {
                                                    id: presetBtn
                                                    required property var modelData
                                                    outlined: true
                                                    selected: Model.presetActive(root.cfg, presetBtn.modelData)
                                                    implicitHeight: Style.space(30)
                                                    text: presetBtn.modelData.label
                                                    foreground: root.fg
                                                    accent: root.accent
                                                    fontFamily: root.fontFamily
                                                    pixelSize: root.fsSub
                                                    onClicked: root.widget.setValues(presetBtn.modelData.values)
                                                }
                                            }
                                        }
                                    }
                                }

                                // the bar icon: typed text, saved as you type
                                Component {
                                    id: textC
                                    Column {
                                        width: row.innerWidth
                                        spacing: Style.space(8)
                                        Loader { sourceComponent: labelsC; width: parent.width }
                                        FieldBox {
                                            width: Style.space(160)
                                            height: Style.space(32)
                                            placeholderText: row.modelData.defaultValue
                                            maxLength: row.modelData.maxLength || 256
                                            foreground: root.fg
                                            accent: root.accent
                                            fontFamily: root.fontFamily
                                            pixelSize: root.fsMain
                                            text: String(root.cfg[row.modelData.key] !== undefined ? root.cfg[row.modelData.key] : "")
                                            // `edited` fires only for real typing or a bounded paste,
                                            // never when `cfg` updates the text, so nothing loops.
                                            onEdited: function(value) { root.widget.setValue(row.modelData.key, value) }
                                        }
                                    }
                                }

                                // dust colour: a few named dusts, or any hex code
                                Component {
                                    id: colorC
                                    Column {
                                        width: row.innerWidth
                                        spacing: Style.space(10)
                                        Loader { sourceComponent: labelsC; width: parent.width }
                                        Flow {
                                            width: parent.width
                                            spacing: Style.space(6)
                                            Repeater {
                                                model: Model.COLORS
                                                delegate: FlatButton {
                                                    id: dustBtn
                                                    required property var modelData
                                                    outlined: true
                                                    selected: root.cfg.dustColor === dustBtn.modelData.id
                                                    implicitHeight: Style.space(30)
                                                    text: dustBtn.modelData.label
                                                    dotColor: "#" + dustBtn.modelData.id
                                                    foreground: root.fg
                                                    accent: root.accent
                                                    fontFamily: root.fontFamily
                                                    pixelSize: root.fsSub
                                                    onClicked: root.widget.setValue("dustColor", dustBtn.modelData.id)
                                                }
                                            }
                                        }
                                        Row {
                                            width: parent.width
                                            spacing: Style.space(8)
                                            Rectangle {
                                                width: Style.space(32)
                                                height: Style.space(32)
                                                radius: Style.space(6)
                                                color: "#" + root.cfg.dustColor
                                                border.width: 1
                                                border.color: root.faint
                                            }
                                            FieldBox {
                                                width: parent.width - Style.space(40)
                                                height: Style.space(32)
                                                placeholderText: "rrggbb"
                                                foreground: root.fg
                                                accent: root.accent
                                                fontFamily: root.fontFamily
                                                pixelSize: root.fsMain
                                                maxLength: 7
                                                text: String(root.cfg.dustColor)
                                                onEdited: function(value) {
                                                    var v = value.trim()
                                                    if (/^#?[0-9a-fA-F]{6}$/.test(v))
                                                        root.widget.setValue("dustColor", v.replace("#", "").toLowerCase())
                                                }
                                            }
                                        }
                                    }
                                }

                                // custom panel colours: pick a role, then a swatch or a hex code
                                Component {
                                    id: paletteC
                                    Column {
                                        width: row.innerWidth
                                        spacing: Style.space(10)
                                        Loader { sourceComponent: labelsC; width: parent.width }

                                        Flow {
                                            width: parent.width
                                            spacing: Style.space(6)
                                            Repeater {
                                                model: root.colorRoles
                                                delegate: FlatButton {
                                                    id: roleBtn
                                                    required property var modelData
                                                    outlined: true
                                                    selected: root.colorRole === roleBtn.modelData.key
                                                    implicitHeight: Style.space(30)
                                                    text: roleBtn.modelData.label
                                                    dotColor: String(root.cfg[roleBtn.modelData.key])
                                                    foreground: root.fg
                                                    accent: root.accent
                                                    fontFamily: root.fontFamily
                                                    pixelSize: root.fsSub
                                                    // The hex field's text binding depends on root.colorRole
                                                    // and re-evaluates, so nothing else to update here.
                                                    onClicked: root.colorRole = roleBtn.modelData.key
                                                }
                                            }
                                        }

                                        Row {
                                            width: parent.width
                                            spacing: Style.space(8)
                                            Rectangle {
                                                width: Style.space(32)
                                                height: Style.space(32)
                                                radius: Style.space(6)
                                                color: String(root.cfg[root.colorRole])
                                                border.width: 1
                                                border.color: root.faint
                                            }
                                            FieldBox {
                                                width: parent.width - Style.space(40)
                                                height: Style.space(32)
                                                placeholderText: "#rrggbb"
                                                foreground: root.fg
                                                accent: root.accent
                                                fontFamily: root.fontFamily
                                                pixelSize: root.fsMain
                                                text: String(root.cfg[root.colorRole] !== undefined ? root.cfg[root.colorRole] : "")
                                                maxLength: 7
                                                onEdited: function(value) {
                                                    var v = value.trim()
                                                    if (/^#[0-9a-fA-F]{6}$/.test(v)) root.widget.setValue(root.colorRole, v.toLowerCase())
                                                }
                                            }
                                        }

                                        Flow {
                                            width: parent.width
                                            spacing: Style.space(5)
                                            Repeater {
                                                model: Settings.PALETTE
                                                delegate: Rectangle {
                                                    id: swatch
                                                    required property string modelData
                                                    width: Style.space(26)
                                                    height: Style.space(26)
                                                    radius: Style.space(6)
                                                    color: swatch.modelData
                                                    border.width: String(root.cfg[root.colorRole]).toLowerCase() === swatch.modelData ? 2 : 1
                                                    border.color: String(root.cfg[root.colorRole]).toLowerCase() === swatch.modelData
                                                        ? root.accent : root.faint
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.widget.setValue(root.colorRole, swatch.modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // never-dusted window classes: removable chips and a field to add one
                                Component {
                                    id: tagsC
                                    Column {
                                        id: tagCol
                                        width: row.innerWidth
                                        spacing: Style.space(8)
                                        property string draft: ""
                                        Loader { sourceComponent: labelsC; width: parent.width }
                                        Flow {
                                            width: parent.width
                                            spacing: Style.space(6)
                                            Repeater {
                                                model: root.cfg.exempt
                                                delegate: FlatButton {
                                                    id: tagBtn
                                                    required property string modelData
                                                    outlined: true
                                                    implicitHeight: Style.space(28)
                                                    text: tagBtn.modelData + "  \u00d7"
                                                    foreground: root.fg
                                                    accent: root.accent
                                                    fontFamily: root.fontFamily
                                                    pixelSize: root.fsSub
                                                    onClicked: root.widget.setValue("exempt", Model.toggleExempt(root.cfg.exempt, tagBtn.modelData))
                                                }
                                            }
                                            Text {
                                                visible: root.cfg.exempt.length === 0
                                                text: "Nothing is exempt."
                                                color: root.dim
                                                font.family: root.fontFamily
                                                font.pixelSize: root.fsSub
                                                textFormat: Text.PlainText
                                            }
                                        }
                                        FieldBox {
                                            id: tagField
                                            width: parent.width
                                            height: Style.space(32)
                                            placeholderText: "window class, then Enter"
                                            maxLength: 64
                                            foreground: root.fg
                                            accent: root.accent
                                            fontFamily: root.fontFamily
                                            pixelSize: root.fsMain
                                            onEdited: function(value) { tagCol.draft = value }
                                            onAccepted: {
                                                var next = Model.addExempt(root.cfg.exempt, tagCol.draft)
                                                if (next.length !== root.cfg.exempt.length)
                                                    root.widget.setValue("exempt", next)
                                                tagField.clear()
                                                tagCol.draft = ""
                                            }
                                        }
                                    }
                                }

                                // reset
                                Component {
                                    id: actionsC
                                    Item {
                                        width: row.innerWidth
                                        height: Math.max(labelBlockAct.height, Style.space(34)) + Style.space(12)
                                        Loader { id: labelBlockAct; sourceComponent: labelsC; width: parent.width - Style.space(170); anchors.verticalCenter: parent.verticalCenter }
                                        FlatButton {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            outlined: true
                                            implicitHeight: Style.space(30)
                                            text: "Reset all settings"
                                            foreground: root.fg
                                            accent: root.accent
                                            fontFamily: root.fontFamily
                                            pixelSize: root.fsSub
                                            onClicked: root.widget.resetAll()
                                        }
                                    }
                                }

                                Component {
                                    id: unknownC
                                    Item { width: row.innerWidth; height: 0 }
                                }

                                Loader {
                                    id: content
                                    width: row.innerWidth
                                    x: row.pad
                                    y: row.isHeader ? 0 : row.pad
                                    sourceComponent: row.modelData.type === "header" ? headerC
                                                   : row.modelData.type === "palette" ? paletteC
                                                   : row.modelData.type === "preset" ? presetC
                                                   : row.modelData.type === "boolean" ? boolC
                                                   : row.modelData.type === "stepper" ? stepC
                                                   : row.modelData.type === "enum" ? enumC
                                                   : row.modelData.type === "string" ? textC
                                                   : row.modelData.type === "color" ? colorC
                                                   : row.modelData.type === "tags" ? tagsC
                                                   : row.modelData.type === "actions" ? actionsC
                                                   : unknownC
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
