import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Font browser panel: live preview grid of monospace fonts, one-click apply
// via omarchy-font-set, and install into ~/.local/share/fonts via zenity.
Panel {
  id: root
  moduleName: "io.github.giodc.omafonts"
  ipcTarget: "io.github.giodc.omafonts"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string pluginVersion: "0.4.1"
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string uiFont: bar ? bar.fontFamily : Style.font.family

  readonly property string previewText: String(setting("previewText", "Aa Bb 123") || "Aa Bb 123")
  readonly property bool autoApplyOnInstall: setting("autoApplyOnInstall", true) !== false

  property var fonts: []
  property bool fontsLoaded: false
  property string searchText: ""
  property string currentFamily: ""
  property string applyingFamily: ""
  property bool busy: false
  property bool installHandled: false
  property string notice: ""
  property string noticeColor: "transparent"
  property int selectedIndex: 0

  property bool removeConfirmOpen: false
  property string removePendingFamily: ""
  property bool removing: false

  readonly property var filteredFonts: {
    var q = String(searchText || "").trim().toLowerCase()
    var src = fonts
    if (!q) return src
    var out = []
    for (var i = 0; i < src.length; i++) {
      var f = String(src[i].family || "").toLowerCase()
      if (f.indexOf(q) >= 0) out.push(src[i])
    }
    return out
  }

  readonly property int columns: 2
  readonly property int cellGap: Style.space(10)
  readonly property int cellHeight: Style.space(148)
  readonly property int previewPixelSize: Style.font.displayLarge

  function scriptPath(name) {
    var url = Qt.resolvedUrl("scripts/" + name)
    var s = String(url)
    if (s.indexOf("file://") === 0) s = s.substring("file://".length)
    return s
  }

  // ConfirmDialog (shell) Text uses AutoText; neutralize markup in font-file names.
  function plainLabel(value) {
    return String(value || "").replace(/</g, "\uFF1C").replace(/>/g, "\uFF1E")
  }

  function setNotice(text, isError) {
    notice = text
    noticeColor = isError ? Color.urgent : Color.accent
    noticeTimer.interval = isError ? 8000 : 6000
    noticeTimer.restart()
  }

  function notify(title, body) {
    Quickshell.execDetached([
      "omarchy-notification-send", title, body,
      "--app-name", "OmaFonts"
    ])
  }

  function refreshFonts(manual) {
    if (manual === true) {
      busy = true
      refreshBusyTimer.restart()
    }
    listProc.exec([scriptPath("fonts.sh"), "list"])
    currentProc.exec([scriptPath("fonts.sh"), "current"])
  }

  function applyFont(family) {
    if (!family || applyingFamily || root.removing) return
    applyingFamily = family
    busy = true
    setProc.exec([scriptPath("fonts.sh"), "set", family])
  }

  function requestRemove(family) {
    if (!family || root.busy || root.removing) return
    removePendingFamily = family
    removeConfirmOpen = true
  }

  function cancelRemove() {
    if (root.removing) return
    removeConfirmOpen = false
    removePendingFamily = ""
  }

  function confirmRemove() {
    if (!removePendingFamily || root.removing) return
    removing = true
    busy = true
    removeProc.exec([scriptPath("fonts.sh"), "remove", removePendingFamily])
  }

  function pickAndInstall() {
    if (busy || pickProc.running) return
    busy = true
    installHandled = false
    // Close so zenity can take focus cleanly (same idea as Tailscale file send).
    close()
    Qt.callLater(function() {
      pickProc.exec([scriptPath("fonts.sh"), "pick-install"])
    })
  }

  function parseFontList(raw) {
    try {
      var data = JSON.parse(String(raw || "[]").trim() || "[]")
      if (!Array.isArray(data)) return []
      return data
    } catch (e) {
      return []
    }
  }

  function handleInstallResult(raw) {
    if (installHandled) return
    installHandled = true

    var text = String(raw || "").trim()
    if (!text) {
      // Empty stdout — common Process race. Load the transcript fonts.sh wrote.
      installHandled = false
      busy = false
      open()
      installLogProc.exec([
        "bash", "-c",
        "cat \"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/omafonts-last-install.json\" 2>/dev/null || true"
      ])
      refreshFonts(true)
      return
    }

    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      setNotice("Install finished — refreshing list", true)
      notify("OmaFonts", "Install finished. Refreshing font list.")
      busy = false
      open()
      refreshFonts(true)
      return
    }
    if (data.cancelled) {
      busy = false
      open()
      return
    }
    if (data.ok === false) {
      setNotice(data.error || "Install failed", true)
      notify("OmaFonts", data.error || "Install failed")
      busy = false
      open()
      return
    }
    var installed = data.installed || []
    if (installed.length === 0) {
      setNotice("No font files installed", true)
      busy = false
      open()
      refreshFonts(true)
      return
    }

    var names = []
    var firstMono = ""
    var anyProp = false
    for (var i = 0; i < installed.length; i++) {
      var item = installed[i]
      if (!item.family) continue
      names.push(item.family)
      if (item.monospace) {
        if (!firstMono) firstMono = item.family
      } else {
        anyProp = true
      }
    }

    var msg = "Installed " + installed.length + " file" + (installed.length === 1 ? "" : "s")
    if (names.length) msg += ": " + names.slice(0, 3).join(", ") + (names.length > 3 ? "…" : "")
    if (anyProp && !firstMono)
      msg += " — proportional (listed; terminals prefer monospace)"

    setNotice(msg, false)
    notify("OmaFonts", msg)

    open()
    refreshFonts(true)
    if (root.autoApplyOnInstall && firstMono) {
      Qt.callLater(function() { root.applyFont(firstMono) })
    }
    busy = false
  }

  onOpenedChanged: {
    if (opened) {
      searchText = ""
      selectedIndex = 0
      refreshFonts(false)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Timer {
    id: noticeTimer
    interval: 6000
    onTriggered: {
      root.notice = ""
      root.noticeColor = "transparent"
    }
  }

  Timer {
    id: refreshBusyTimer
    interval: 800
    onTriggered: if (!listProc.running && !setProc.running && !pickProc.running) root.busy = false
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.fonts = root.parseFontList(text)
        root.fontsLoaded = true
        if (!setProc.running && !pickProc.running) root.busy = false
      }
    }
    stderr: StdioCollector {}
  }

  Process {
    id: currentProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.currentFamily = String(text || "").trim()
      }
    }
    stderr: StdioCollector {}
  }

  Process {
    id: setProc
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      var family = root.applyingFamily
      root.applyingFamily = ""
      root.busy = false
      if (exitCode === 0) {
        root.currentFamily = family
        for (var i = 0; i < root.fonts.length; i++) {
          root.fonts[i].current = root.fonts[i].family === family
        }
        root.fonts = root.fonts.slice(0)
        root.setNotice("Active: " + family, false)
      } else {
        root.setNotice("Failed to set font", true)
      }
    }
  }

  Process {
    id: pickProc
    stdout: StdioCollector {
      id: pickOut
      onStreamFinished: root.handleInstallResult(text)
    }
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      // Fallback when streamFinished saw nothing (race) or cancel with no JSON.
      Qt.callLater(function() {
        if (!root.installHandled)
          root.handleInstallResult(pickOut.text)
      })
    }
  }

  // Reads last-install transcript when stdout was empty / unreadable.
  Process {
    id: installLogProc
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(text || "").trim()
        if (!t) return
        root.installHandled = false
        root.handleInstallResult(t)
      }
    }
    stderr: StdioCollector {}
  }

  Process {
    id: removeProc
    stdout: StdioCollector {
      id: removeOut
      onStreamFinished: {
        var raw = String(text || "").trim()
        var data = {}
        try { data = JSON.parse(raw || "{}") } catch (e) { data = {} }
        var family = root.removePendingFamily
        root.removing = false
        root.busy = false
        root.removeConfirmOpen = false
        root.removePendingFamily = ""
        if (data.ok) {
          var n = (data.removed && data.removed.length) ? data.removed.length : 0
          var msg = "Removed " + family + (n ? (" (" + n + " file" + (n === 1 ? "" : "s") + ")") : "")
          root.setNotice(msg, false)
          root.notify("OmaFonts", msg)
          if (root.currentFamily === family) root.currentFamily = ""
          root.refreshFonts(true)
        } else {
          var err = data.error || "Remove failed"
          root.setNotice(err, true)
          root.notify("OmaFonts", err)
        }
      }
    }
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.removing) {
        Qt.callLater(function() {
          if (!root.removing) return
          var text = String(removeOut.text || "").trim()
          var data = {}
          try { data = JSON.parse(text || "{}") } catch (e) { data = {} }
          root.removing = false
          root.busy = false
          root.removeConfirmOpen = false
          root.removePendingFamily = ""
          root.setNotice(data.error || "Remove failed", true)
        })
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refreshFonts(true) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(Style.space(640), Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || root.removeConfirmOpen
      onCloseRequested: {
        if (root.removeConfirmOpen) root.cancelRemove()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Keys.onPressed: function(event) {
        if (root.removeConfirmOpen) {
          if (removeConfirm.handleKey(event)) event.accepted = true
          return
        }
        if (searchField.activeFocus) return
        var count = root.filteredFonts.length
        if (count === 0) return
        if (event.key === Qt.Key_Right) {
          root.selectedIndex = Math.min(count - 1, root.selectedIndex + 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          root.selectedIndex = Math.max(0, root.selectedIndex - 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.selectedIndex = Math.min(count - 1, root.selectedIndex + root.columns)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.selectedIndex = Math.max(0, root.selectedIndex - root.columns)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          var row = root.filteredFonts[root.selectedIndex]
          if (row) root.applyFont(row.family)
          event.accepted = true
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
          var del = root.filteredFonts[root.selectedIndex]
          if (del && del.user) root.requestRemove(del.family)
          event.accepted = true
        } else if (event.key === Qt.Key_Slash) {
          searchField.forceActiveFocus()
          event.accepted = true
        }
      }

      Column {
        id: panelColumn
        anchors.fill: parent
        anchors.margins: Style.space(4)
        spacing: Style.space(10)

        // ---- Header ----
        Item {
          id: headerRow
          width: parent.width
          height: Math.max(headerLeft.implicitHeight, headerRight.implicitHeight)

          Row {
            id: headerLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              text: "󰛖"
              color: root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.heading
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              textFormat: Text.PlainText
              text: "OMAFONTS"
              color: root.dim
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              textFormat: Text.PlainText
              text: "v" + root.pluginVersion
              color: root.dim
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            id: headerRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              visible: root.busy
              text: "…"
              color: Color.accent
              font.family: root.uiFont
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              width: Style.space(28)
              height: Style.space(28)
              radius: Math.min(4, Style.cornerRadius)
              color: refreshArea.containsMouse || root.busy
                ? Style.hoverFillFor(root.fg, Color.accent)
                : "transparent"
              anchors.verticalCenter: parent.verticalCenter
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: ""
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: Style.font.body
              }
              MouseArea {
                id: refreshArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refreshFonts(true)
              }
            }

            Rectangle {
              width: addLabel.implicitWidth + Style.space(18)
              height: Style.space(28)
              radius: Math.min(4, Style.cornerRadius)
              color: addArea.containsMouse
                ? Style.hoverFillFor(root.fg, Color.accent)
                : Style.hoverFillFor(root.fg, root.fg)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                id: addLabel
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "+ Add"
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              MouseArea {
                id: addArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickAndInstall()
              }
            }
          }
        }

        // ---- Search ----
        TextField {
          id: searchField
          width: parent.width
          foreground: root.fg
          placeholderText: "Search fonts  (/)"
          text: root.searchText
          onTextChanged: {
            root.searchText = text
            root.selectedIndex = 0
          }
          Keys.onEscapePressed: {
            if (text.length) text = ""
            else keyCatcher.forceActiveFocus()
          }
          Keys.onDownPressed: keyCatcher.forceActiveFocus()
        }

        // ---- Status / current ----
        Text {
          id: statusLine
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          color: root.notice !== "" ? root.noticeColor : root.dim
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          text: root.notice !== ""
            ? root.notice
            : (root.currentFamily
              ? ("Current: " + root.currentFamily + "  ·  " + root.filteredFonts.length + " fonts")
              : (root.fontsLoaded ? (root.filteredFonts.length + " fonts") : "Loading…"))
        }

        // ---- Grid (fills remaining panel height) ----
        Item {
          id: gridHost
          width: parent.width
          height: Math.max(
            Style.space(200),
            panelColumn.height
              - headerRow.height
              - searchField.height
              - statusLine.height
              - panelColumn.spacing * 3
          )

          GridView {
            id: grid
            anchors.fill: parent
            clip: true
            cellWidth: Math.max(Style.space(120), Math.floor(width / root.columns))
            cellHeight: root.cellHeight + root.cellGap
            model: root.filteredFonts
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            onCountChanged: if (root.selectedIndex >= count) root.selectedIndex = Math.max(0, count - 1)
            Connections {
              target: root
              function onSelectedIndexChanged() {
                if (root.selectedIndex >= 0 && root.selectedIndex < grid.count)
                  grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
              }
            }

            delegate: Item {
              width: grid.cellWidth
              height: grid.cellHeight

              readonly property bool isSelected: index === root.selectedIndex
              readonly property bool isCurrent: modelData.current === true
                || modelData.family === root.currentFamily
              readonly property bool isApplying: root.applyingFamily === modelData.family
              readonly property bool isMono: modelData.monospace !== false
              readonly property bool isUser: modelData.user === true
              readonly property bool hovered: cardArea.containsMouse
                || activateArea.containsMouse || deleteArea.containsMouse
              readonly property string extLabel: {
                var e = String(modelData.ext || "")
                if (!e) return ""
                return e.split(",").join(" · ")
              }

              Rectangle {
                id: card
                anchors.fill: parent
                anchors.rightMargin: root.cellGap
                anchors.bottomMargin: root.cellGap
                radius: Math.min(6, Style.cornerRadius)
                color: {
                  if (isCurrent) return Style.hoverFillFor(root.fg, Color.accent)
                  if (isSelected || hovered) return Style.hoverFillFor(root.fg, root.fg)
                  return "transparent"
                }
                border.width: isCurrent || isSelected || hovered ? Math.max(1, Style.space(1)) : 0
                border.color: isCurrent ? Color.accent : root.dim

                MouseArea {
                  id: cardArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.ArrowCursor
                  onEntered: root.selectedIndex = index
                  // Card click only selects — activate via the hover button / Enter.
                  onClicked: root.selectedIndex = index
                }

                Column {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(10)
                  anchors.bottomMargin: Style.space(36)
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: root.previewText
                    color: root.fg
                    font.family: modelData.family
                    font.pixelSize: root.previewPixelSize
                    elide: Text.ElideRight
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: modelData.family
                    color: root.dim
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Row {
                    id: metaRow
                    spacing: Style.space(6)

                    Text {
                      textFormat: Text.PlainText
                      visible: extLabel !== ""
                      text: extLabel
                      color: root.dim
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: !isMono
                      text: "proportional"
                      color: root.dim
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: isUser && isMono
                      text: "user"
                      color: root.dim
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: isCurrent && !isApplying
                      text: "Active"
                      color: Color.accent
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: isApplying
                      text: "Applying…"
                      color: Color.accent
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }

                Rectangle {
                  id: deleteBtn
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  anchors.margins: Style.space(10)
                  visible: isUser && (hovered || isSelected) && !root.removing
                  width: deleteLabel.implicitWidth + Style.space(14)
                  height: Style.space(22)
                  radius: Math.min(4, Style.cornerRadius)
                  color: deleteArea.containsMouse
                    ? Style.hoverFillFor(root.fg, Color.urgent)
                    : Style.hoverFillFor(root.fg, root.fg)
                  border.width: Math.max(1, Style.space(1))
                  border.color: Color.urgent
                  z: 2

                  Text {
                    id: deleteLabel
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "Delete"
                    color: root.fg
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  MouseArea {
                    id: deleteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestRemove(modelData.family)
                  }
                }

                Rectangle {
                  id: activateBtn
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.margins: Style.space(10)
                  visible: (hovered || isSelected) && !isCurrent && !isApplying
                  width: activateLabel.implicitWidth + Style.space(14)
                  height: Style.space(22)
                  radius: Math.min(4, Style.cornerRadius)
                  color: activateArea.containsMouse
                    ? Style.hoverFillFor(root.fg, Color.accent)
                    : Style.hoverFillFor(root.fg, root.fg)
                  border.width: Math.max(1, Style.space(1))
                  border.color: Color.accent
                  z: 2

                  Text {
                    id: activateLabel
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "Activate"
                    color: root.fg
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  MouseArea {
                    id: activateArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applyFont(modelData.family)
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: root.fontsLoaded && root.filteredFonts.length === 0
            text: root.searchText ? "No matches" : "No monospace fonts found"
            color: root.dim
            font.family: root.uiFont
            font.pixelSize: Style.font.body
          }
        }

        ConfirmDialog {
          id: removeConfirm
          anchors.fill: parent
          z: 100
          opened: root.removeConfirmOpen
          message: root.removePendingFamily
            ? ("Remove \"" + root.plainLabel(root.removePendingFamily) + "\" from ~/.local/share/fonts?")
            : "Remove this font?"
          cancelText: "Cancel"
          confirmText: root.removing ? "Removing…" : "Delete"
          background: Color.popups.background
          foreground: root.fg
          selectedText: Color.urgent
          fontFamily: root.uiFont
          onCanceled: root.cancelRemove()
          onConfirmed: root.confirmRemove()
        }
      }
    }
  }
}
