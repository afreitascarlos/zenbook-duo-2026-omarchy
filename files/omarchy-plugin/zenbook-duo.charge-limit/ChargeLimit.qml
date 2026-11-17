import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Battery charge limit widget for the Omarchy bar (written for Omarchy 4.5).
// Needs /usr/local/bin/battery-charge-limit and its sudoers rule (install.sh charge-limit).
BarWidget {
  id: root
  moduleName: "zenbook-duo.charge-limit"

  property int limit: 80
  property int boostUntil: 0
  property bool available: false
  readonly property bool boosting: boostUntil > 0
  // Like Omarchy's indicators: hidden until the pointer is over the bar centre,
  // but always shown while the full-charge boost is on.
  readonly property bool revealed: boosting
    || (bar && bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true)

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (!toggleProc.running) toggleProc.running = true
  }

  function boostEndText() {
    return new Date(boostUntil * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat)
  }

  visible: available
  implicitWidth: available && (revealed || vertical) ? button.implicitWidth : 0
  implicitHeight: available && (revealed || !vertical) ? button.implicitHeight : 0
  clip: true

  Process {
    id: statusProc
    command: ["battery-charge-limit", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(text)
          root.limit = s.limit
          root.boostUntil = s.boostUntil
          root.available = true
        } catch (e) {
          root.available = false
        }
      }
    }
  }

  Process {
    id: toggleProc
    command: ["sudo", "-n", "/usr/local/bin/battery-charge-limit", "toggle"]
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.bar)
        root.bar.run("notify-send -u critical 'Battery' 'Could not change the charge limit'")
      root.broadcast("refresh")
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    width: implicitWidth
    height: implicitHeight
    bar: root.bar
    concealed: !root.revealed
    // nf-md-battery_charging_100 while boosting, nf-md-battery_80 otherwise
    text: String.fromCodePoint(root.boosting ? 0xf0085 : 0xf0081)
    active: root.boosting
    dimmed: !root.boosting
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.boosting
      ? "Full charge until " + root.boostEndText() + "\nClick to go back to the " + root.limit + "% limit"
      : "Charge limited to " + root.limit + "%\nClick to charge to 100% for the next 24 hours"
    onPressed: root.toggle()
  }
}
