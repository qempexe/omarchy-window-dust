import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.qempexe.window-dust"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string dustTab: "windows"

  readonly property var dustCfg: hostWidget ? hostWidget.dustConfig : Model.normalizeConfig({})
  readonly property var dustRows: hostWidget
    ? hostWidget.dustEntries.filter(function (e) { return e.step > 0 }).slice(0, 8)
    : []
  readonly property string dustFont: root.bar ? root.bar.fontFamily : Style.font.family

  function open() {
    if (root.hostWidget) root.hostWidget.reloadConfig()
    root.controller.show()
  }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function setDust(patch) { if (root.hostWidget) root.hostWidget.setConfig(patch) }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Style.space(26)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Window Dust"
            color: root.barForeground
            font.family: root.dustFont
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Chip {
              text: "Windows"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustTab === "windows"
              onClicked: root.dustTab = "windows"
            }
            Chip {
              text: "Settings"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustTab === "settings"
              onClicked: root.dustTab = "settings"
            }
          }
        }

        // ---- windows tab ---------------------------------------------------
        Column {
          id: windowsTab
          visible: root.dustTab === "windows"
          width: parent.width
          spacing: Style.space(6)

          Text {
            visible: root.dustRows.length === 0
            width: parent.width
            text: root.dustCfg.enabled ? "Everything is clean." : "Window Dust is paused."
            color: root.barForeground
            opacity: 0.7
            font.family: root.dustFont
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.dustRows

            delegate: Item {
              width: windowsTab.width
              height: Style.space(28)

              Rectangle {
                anchors.fill: parent
                radius: Style.space(4)
                color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b,
                               area.containsMouse ? 0.12 : 0)
              }

              Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: Style.space(2)
                width: parent.width * modelData.level
                color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.45)
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: idleLabel.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.cls + (modelData.title ? "  " + modelData.title : "")
                elide: Text.ElideRight
                color: root.barForeground
                font.family: root.dustFont
                font.pixelSize: Style.font.body
              }

              Text {
                id: idleLabel
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                text: Model.formatIdle(modelData.idleSec)
                color: root.barForeground
                opacity: 0.7
                font.family: root.dustFont
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function (mouse) {
                  if (mouse.button === Qt.RightButton) {
                    root.hostWidget.toggleExempt(modelData.cls)
                  } else {
                    root.hostWidget.scatterAt(modelData.address)
                    root.hostWidget.focusWindow(modelData.address)
                    root.close()
                  }
                }
              }
            }
          }

          Row {
            spacing: Style.space(6)

            Chip {
              visible: root.dustRows.length > 0
              text: "Dust everything off"
              fg: root.barForeground
              fontFamily: root.dustFont
              onClicked: root.hostWidget.wipeAll()
            }
            Chip {
              text: root.dustCfg.enabled ? "Pause" : "Resume"
              fg: root.barForeground
              fontFamily: root.dustFont
              onClicked: root.setDust({ enabled: !root.dustCfg.enabled })
            }
          }

          Text {
            visible: root.dustRows.length > 0
            width: parent.width
            text: "Click a window to focus it. Right-click to never dust that app."
            wrapMode: Text.WordWrap
            color: root.barForeground
            opacity: 0.55
            font.family: root.dustFont
            font.pixelSize: Style.font.caption
          }
        }

        // ---- settings tab --------------------------------------------------
        Column {
          id: settingsTab
          visible: root.dustTab === "settings"
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "Preset"
            color: root.barForeground
            opacity: 0.6
            font.family: root.dustFont
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.PRESETS
              delegate: Chip {
                text: modelData.label
                fg: root.barForeground
                fontFamily: root.dustFont
                selected: Model.presetActive(root.dustCfg, modelData)
                onClicked: root.setDust(modelData.values)
              }
            }
          }

          SettingStepper {
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Dust starts after"
            valueText: Model.formatDuration(root.dustCfg.dustAfterMinutes * 60)
            onDecrement: root.setDust({ dustAfterMinutes:
              Model.stepOption(Model.OPTIONS.dustAfterMinutes, root.dustCfg.dustAfterMinutes, -1) })
            onIncrement: root.setDust({ dustAfterMinutes:
              Model.stepOption(Model.OPTIONS.dustAfterMinutes, root.dustCfg.dustAfterMinutes, 1) })
          }

          SettingStepper {
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Settles fully over"
            valueText: Model.formatDuration(root.dustCfg.settleMinutes * 60)
            onDecrement: root.setDust({ settleMinutes:
              Model.stepOption(Model.OPTIONS.settleMinutes, root.dustCfg.settleMinutes, -1) })
            onIncrement: root.setDust({ settleMinutes:
              Model.stepOption(Model.OPTIONS.settleMinutes, root.dustCfg.settleMinutes, 1) })
          }

          SettingStepper {
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Fades down to"
            valueText: Math.round(root.dustCfg.minOpacity * 100) + "%"
            onDecrement: root.setDust({ minOpacity:
              Model.stepOption(Model.OPTIONS.minOpacity, root.dustCfg.minOpacity, -1) })
            onIncrement: root.setDust({ minOpacity:
              Model.stepOption(Model.OPTIONS.minOpacity, root.dustCfg.minOpacity, 1) })
          }

          SettingStepper {
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Stages (smoothness)"
            valueText: String(root.dustCfg.stages)
            onDecrement: root.setDust({ stages:
              Model.stepOption(Model.OPTIONS.stages, root.dustCfg.stages, -1) })
            onIncrement: root.setDust({ stages:
              Model.stepOption(Model.OPTIONS.stages, root.dustCfg.stages, 1) })
          }

          Text {
            text: "How dust settles"
            color: root.barForeground
            opacity: 0.6
            font.family: root.dustFont
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.CURVES
              delegate: Chip {
                text: modelData.label
                fg: root.barForeground
                fontFamily: root.dustFont
                selected: root.dustCfg.curve === modelData.id
                onClicked: root.setDust({ curve: modelData.id })
              }
            }
          }

          Text {
            text: "Dust colour"
            color: root.barForeground
            opacity: 0.6
            font.family: root.dustFont
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.COLORS
              delegate: Chip {
                text: modelData.label
                swatch: modelData.id
                fg: root.barForeground
                fontFamily: root.dustFont
                selected: root.dustCfg.dustColor === modelData.id
                onClicked: root.setDust({ dustColor: modelData.id })
              }
            }

            Chip {
              text: root.dustCfg.tintBorder ? "Border tint: on" : "Border tint: off"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.tintBorder
              onClicked: root.setDust({ tintBorder: !root.dustCfg.tintBorder })
            }
          }

          // ---- particles ----
          Text {
            text: "Particles"
            color: root.barForeground
            opacity: 0.6
            font.family: root.dustFont
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Chip {
              text: root.dustCfg.particles ? "Particles: on" : "Particles: off"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.particles
              onClicked: root.setDust({ particles: !root.dustCfg.particles })
            }
            Chip {
              text: root.dustCfg.particleTwinkle ? "Twinkle: on" : "Twinkle: off"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.particleTwinkle
              onClicked: root.setDust({ particleTwinkle: !root.dustCfg.particleTwinkle })
            }
            Chip {
              text: root.dustCfg.scatterOnFocus ? "Scatter on focus: on" : "Scatter on focus: off"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.scatterOnFocus
              onClicked: root.setDust({ scatterOnFocus: !root.dustCfg.scatterOnFocus })
            }
          }

          // ---- effect kinds ----
          Text {
            text: "Effect types"
            color: root.barForeground
            opacity: 0.6
            font.family: root.dustFont
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Chip {
              text: "Motes"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.effectMotes
              onClicked: root.setDust({ effectMotes: !root.dustCfg.effectMotes })
            }
            Chip {
              text: "Grain"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.effectGrain
              onClicked: root.setDust({ effectGrain: !root.dustCfg.effectGrain })
            }
            Chip {
              text: "Smudges"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.effectSmudges
              onClicked: root.setDust({ effectSmudges: !root.dustCfg.effectSmudges })
            }
            Chip {
              text: "Streaks"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.effectStreaks
              onClicked: root.setDust({ effectStreaks: !root.dustCfg.effectStreaks })
            }
            Chip {
              text: "Cobwebs"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.effectCobwebs
              onClicked: root.setDust({ effectCobwebs: !root.dustCfg.effectCobwebs })
            }
          }

          SettingStepper {
            visible: root.dustCfg.particles
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Density"
            valueText: root.dustCfg.particleDensity.toFixed(2) + " / kpx²"
            onDecrement: root.setDust({ particleDensity:
              Model.stepOption(Model.OPTIONS.particleDensity, root.dustCfg.particleDensity, -1) })
            onIncrement: root.setDust({ particleDensity:
              Model.stepOption(Model.OPTIONS.particleDensity, root.dustCfg.particleDensity, 1) })
          }

          SettingStepper {
            visible: root.dustCfg.particles
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Max per window"
            valueText: String(root.dustCfg.particleMax)
            onDecrement: root.setDust({ particleMax:
              Model.stepOption(Model.OPTIONS.particleMax, root.dustCfg.particleMax, -1) })
            onIncrement: root.setDust({ particleMax:
              Model.stepOption(Model.OPTIONS.particleMax, root.dustCfg.particleMax, 1) })
          }

          SettingStepper {
            visible: root.dustCfg.particles
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Speck size (max)"
            valueText: root.dustCfg.particleSizeMax.toFixed(1) + " px"
            onDecrement: root.setDust({ particleSizeMax:
              Model.stepOption(Model.OPTIONS.particleSizeMax, root.dustCfg.particleSizeMax, -1) })
            onIncrement: root.setDust({ particleSizeMax:
              Model.stepOption(Model.OPTIONS.particleSizeMax, root.dustCfg.particleSizeMax, 1) })
          }

          SettingStepper {
            visible: root.dustCfg.particles
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Drift speed"
            valueText: root.dustCfg.particleDrift.toFixed(1) + " px/s"
            onDecrement: root.setDust({ particleDrift:
              Model.stepOption(Model.OPTIONS.particleDrift, root.dustCfg.particleDrift, -1) })
            onIncrement: root.setDust({ particleDrift:
              Model.stepOption(Model.OPTIONS.particleDrift, root.dustCfg.particleDrift, 1) })
          }

          SettingStepper {
            visible: root.dustCfg.particles
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Brightness"
            valueText: Math.round(root.dustCfg.particleOpacity * 100) + "%"
            onDecrement: root.setDust({ particleOpacity:
              Model.stepOption(Model.OPTIONS.particleOpacity, root.dustCfg.particleOpacity, -1) })
            onIncrement: root.setDust({ particleOpacity:
              Model.stepOption(Model.OPTIONS.particleOpacity, root.dustCfg.particleOpacity, 1) })
          }

          // ---- away / exempt ----
          Text {
            text: "Away from the machine"
            color: root.barForeground
            opacity: 0.6
            font.family: root.dustFont
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Chip {
              text: root.dustCfg.pauseWhenAway ? "Pause dust while away: on" : "Pause dust while away: off"
              fg: root.barForeground
              fontFamily: root.dustFont
              selected: root.dustCfg.pauseWhenAway
              onClicked: root.setDust({ pauseWhenAway: !root.dustCfg.pauseWhenAway })
            }
          }

          SettingStepper {
            visible: root.dustCfg.pauseWhenAway
            width: parent.width
            fg: root.barForeground
            fontFamily: root.dustFont
            label: "Away after"
            valueText: root.dustCfg.awayMinutes + "m"
            onDecrement: root.setDust({ awayMinutes:
              Model.stepOption(Model.OPTIONS.awayMinutes, root.dustCfg.awayMinutes, -1) })
            onIncrement: root.setDust({ awayMinutes:
              Model.stepOption(Model.OPTIONS.awayMinutes, root.dustCfg.awayMinutes, 1) })
          }

          Text {
            width: parent.width
            text: "Never dusted: " + (root.dustCfg.exempt.length > 0 ? root.dustCfg.exempt.join(", ") : "nothing")
            wrapMode: Text.WordWrap
            color: root.barForeground
            opacity: 0.7
            font.family: root.dustFont
            font.pixelSize: Style.font.bodySmall
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Chip {
              text: "Clear list"
              fg: root.barForeground
              fontFamily: root.dustFont
              onClicked: root.setDust({ exempt: [] })
            }
            Chip {
              text: "Reset all settings"
              fg: root.barForeground
              fontFamily: root.dustFont
              onClicked: root.setDust(Model.DEFAULTS)
            }
          }

          Text {
            width: parent.width
            text: "Changes apply instantly. Saved to ~/.config/omarchy/window-dust.json"
            wrapMode: Text.WordWrap
            color: root.barForeground
            opacity: 0.5
            font.family: root.dustFont
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
