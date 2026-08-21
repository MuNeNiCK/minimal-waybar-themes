import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: ""
  property var barWidgetRegistry: null
  property var barConfig: ({})
  property var shell: null
  property var manifest: null

  property string position: "top"
  readonly property bool vertical: false
  readonly property int barSize: 35
  readonly property int iconSlot: Style.bar.iconSlot
  readonly property int statusSlot: Style.bar.statusSlot
  readonly property real menuOpticalOffsetX: -0.5
  readonly property color foreground: Color.bar.text
  readonly property color mutedColor: Color.muted
  readonly property color barForeground: foreground
  readonly property color background: Color.bar.background
  readonly property color urgent: Color.bar.active
  readonly property string fontFamily: Style.font.family
  property bool foregroundAnimationEnabled: true
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property var activePopout: null
  property var tooltipTarget: null
  property string tooltipText: ""
  property var moduleSlots: []
  property string home: Quickshell.env("HOME")
  property bool barHidden: false
  property int cpuPercent: 0
  property int memoryPercent: 0
  property string mediaTitle: ""
  property string activeWindowClass: "Desktop"
  property string activeWindowTitle: "Workspace"
  property bool gameModeEnabled: false

  readonly property var layoutConfig: ({
    left: ["omarchy.menu", "omarchy.active-window"],
    center: ["omarchy.media", "omarchy.workspaces", "omarchy.clock", "omarchy.indicators", "omarchy.system-update"],
    right: ["omarchy.tray", "omarchy.audio", "omarchy.bluetooth", "omarchy.network", "omarchy.power"]
  })

  function run(command) {
    Quickshell.execDetached(["bash", "-lc", String(command || "")])
  }

  function shellQuote(value) {
    return Util.shellQuote(String(value || ""))
  }

  function registerSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterSlot(slot) {
    moduleSlots = moduleSlots.filter(function(candidate) { return candidate !== slot })
  }

  function moduleWidgets(widgetId) {
    var result = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.widgetId === widgetId && slot.activeItem) result.push(slot.activeItem)
    }
    return result
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if (typeof activePopout.closeForPopoutSwitch === "function") activePopout.closeForPopoutSwitch()
      else if (typeof activePopout.close === "function") activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  function showTooltip(target, text) {
    tooltipTarget = target
    tooltipText = String(text || "")
  }

  function hideTooltip(target) {
    if (!target || tooltipTarget === target) {
      tooltipTarget = null
      tooltipText = ""
    }
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  Process {
    id: hiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: function(line) { root.barHidden = String(line).trim() === "yes" }
    }
  }

  function usageIcon(percent) {
    var icons = ["󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥"]
    return icons[Math.max(0, Math.min(7, Math.floor(Number(percent || 0) * 8 / 101)))]
  }

  function toggleGameMode() {
    var effectsEnabled = gameModeEnabled
    var lua = "hl.config({ animations = { enabled = " + (effectsEnabled ? "true" : "false") + " }, decoration = { blur = { enabled = " + (effectsEnabled ? "true" : "false") + " } } })"
    var stateFile = root.shellQuote(root.home + "/.cache/hypr_gamemode")
    var updateState = effectsEnabled ? "rm -f " + stateFile : "touch " + stateFile
    root.run("hyprctl eval " + root.shellQuote(lua) + " && " + updateState)
    gameModeEnabled = !effectsEnabled
  }

  Process {
    id: v4StatusProbe
    command: ["bash", "-c", "read _ u n s i w q x y z < /proc/stat; a=$((u+n+s+i+w+q+x+y)); b=$((u+n+s+q+x+y)); sleep 0.12; read _ u n s i w q x y z < /proc/stat; c=$((u+n+s+i+w+q+x+y)); d=$((u+n+s+q+x+y)); dt=$((c-a)); db=$((d-b)); cpu=0; ((dt>0)) && cpu=$((100*db/dt)); mem=$(free | awk '/^Mem:/ {printf \"%d\", 100*$3/$2}'); title=$(playerctl metadata title 2>/dev/null | head -n1 | tr '\\t' ' '); printf \"%s\\t%s\\t%s\\n\" \"$cpu\" \"$mem\" \"$title\""]
    stdout: SplitParser {
      onRead: function(line) {
        var fields = String(line).replace(/\r$/, "").split("\t")
        root.cpuPercent = Number(fields[0] || 0)
        root.memoryPercent = Number(fields[1] || 0)
        root.mediaTitle = fields.slice(2).join(" ").slice(0, 25)
      }
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!v4StatusProbe.running) v4StatusProbe.running = true
  }

  Process {
    id: gameModeProbe
    command: ["bash", "-c", "[[ -f $HOME/.cache/hypr_gamemode ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: function(line) { root.gameModeEnabled = String(line).trim() === "yes" }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!gameModeProbe.running) gameModeProbe.running = true
  }

  Process {
    id: activeWindowProbe
    command: ["bash", "-c", "window=$(hyprctl activewindow -j 2>/dev/null); address=$(jq -r '.address // empty' <<<\"$window\"); if [[ -z $address || $address == null ]]; then ws=$(hyprctl activeworkspace -j | jq -r '.id'); printf \"Desktop\\tWorkspace %s\\n\" \"$ws\"; else jq -r '[.class // \"Unknown\", .title // \"\"] | @tsv' <<<\"$window\"; fi"]
    stdout: SplitParser {
      onRead: function(line) {
        var fields = String(line).replace(/\r$/, "").split("\t")
        root.activeWindowClass = fields[0] || "Desktop"
        var title = fields.slice(1).join(" ")
        var appClass = root.activeWindowClass.toLowerCase()
        if (appClass.indexOf("discord") !== -1 || appClass.indexOf("vesktop") !== -1) {
          title = title.replace(/^\([0-9]+\)\s*/, "").replace(/^Discord\s*\|\s*/, "")
        }
        root.activeWindowTitle = title || root.activeWindowClass
      }
    }
  }

  Timer {
    interval: 500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!activeWindowProbe.running) activeWindowProbe.running = true
  }

  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: hiddenProbe.running = true
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarSurface {
        required property var modelData
        screen: modelData
      }
    }
  }

  component WidgetSlot: Item {
    id: slot

    required property string widgetId
    property var settings: ({})
    readonly property var registryEntry: {
      var widgets = root.barWidgetRegistry ? root.barWidgetRegistry.widgets : ({})
      return widgets && widgets[widgetId] ? widgets[widgetId] : null
    }
    readonly property var activeItem: loader.item

    visible: registryEntry !== null
    implicitWidth: activeItem ? activeItem.implicitWidth : 0
    implicitHeight: root.barSize
    width: implicitWidth
    height: root.barSize

    Component.onCompleted: root.registerSlot(slot)
    Component.onDestruction: root.unregisterSlot(slot)

    Loader {
      id: loader
      anchors.verticalCenter: parent.verticalCenter
      sourceComponent: slot.registryEntry ? slot.registryEntry.component : null

      onLoaded: {
        slot.inject()
        Qt.callLater(slot.inject)
      }
    }

    onSettingsChanged: inject()
    onActiveItemChanged: Qt.callLater(inject)

    function inject() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = root
      if ("moduleName" in target) target.moduleName = widgetId
      if ("settings" in target) target.settings = settings
    }
  }

  component WorkspaceDots: Item {
    id: dots

    implicitWidth: row.implicitWidth
    implicitHeight: root.barSize

    function workspaceById(workspaceId) {
      var values = Hyprland.workspaces.values
      for (var i = 0; i < values.length; i++) {
        if (values[i].id === workspaceId) return values[i]
      }
      return null
    }

    function focusWorkspace(workspaceId) {
      root.run("hyprctl dispatch " + root.shellQuote("hl.dsp.focus({ workspace = \"" + workspaceId + "\" })"))
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: 1.5

      Repeater {
        model: 8

        Item {
          id: workspaceButton
          required property int index
          readonly property int workspaceId: index + 1
          readonly property var workspace: dots.workspaceById(workspaceId)
          readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
          readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === workspaceId

          width: focused ? 25 : 24
          height: 28

          Rectangle {
            anchors.centerIn: parent
            width: parent.focused ? 22 : parent.width
            height: parent.focused ? 20 : parent.height
            radius: 18
            color: parent.focused ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.20) : "transparent"

            Rectangle {
              anchors.centerIn: parent
              width: 6
              height: 6
              radius: 3
              color: parent.parent.occupied || parent.parent.focused ? root.foreground : "transparent"
              border.width: parent.parent.occupied || parent.parent.focused ? 0 : 1
              border.color: root.foreground
              opacity: parent.parent.focused || parent.parent.occupied ? 1 : 0.5
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dots.focusWorkspace(workspaceButton.workspaceId)
          }
        }
      }
    }
  }

  component OmarchyButton: Item {
    implicitWidth: 27
    implicitHeight: 27

    Text {
      id: menuGlyph
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: -(menuGlyphMetrics.tightBoundingRect.x + menuGlyphMetrics.tightBoundingRect.width / 2 - implicitWidth / 2) + root.menuOpticalOffsetX
      anchors.verticalCenterOffset: -(baselineOffset + menuGlyphMetrics.tightBoundingRect.y + menuGlyphMetrics.tightBoundingRect.height / 2 - implicitHeight / 2)
      text: ""
      color: root.foreground
      font.family: "JetBrainsMono Nerd Font Propo"
      font.pixelSize: 17
    }

    TextMetrics {
      id: menuGlyphMetrics
      font: menuGlyph.font
      text: menuGlyph.text
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.run("xdg-terminal-exec")
        else root.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
      }
    }
  }

  component V4ActiveWindow: Item {
    id: activeWindow
    readonly property string appClass: root.activeWindowClass
    readonly property string fullTitle: root.activeWindowTitle
    readonly property string shortTitle: fullTitle.length > 20 ? fullTitle.slice(0, 17) + "..." : fullTitle
    implicitWidth: Math.max(classLabel.implicitWidth, titleLabel.implicitWidth) + 12
    implicitHeight: 29

    Column {
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      spacing: -2

      Text {
        id: classLabel
        text: activeWindow.appClass
        color: root.mutedColor
        font.family: "JetBrainsMono Nerd Font Propo"
        font.pixelSize: 10
      }
      Text {
        id: titleLabel
        text: activeWindow.shortTitle
        color: root.foreground
        font.family: "JetBrainsMono Nerd Font Propo"
        font.pixelSize: 12
        font.bold: true
      }
    }
  }

  component GameModeButton: Item {
    implicitWidth: gameModeGlyph.implicitWidth + 8
    implicitHeight: root.barSize

    Text {
      id: gameModeGlyph
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: ""
      color: root.foreground
      opacity: root.gameModeEnabled ? 1 : 0.8
      font.family: "JetBrainsMono Nerd Font Propo"
      font.pixelSize: 12
      font.bold: true
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleGameMode()
    }
  }

  component BarSurface: PanelWindow {
    id: barWindow

    visible: true
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Auto
    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: root.barSize
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "minimal-v4-bar"
    WlrLayershell.layer: WlrLayer.Top

    margins.top: root.barHidden ? -root.barSize : 0

    Rectangle {
      anchors.fill: parent
      anchors.leftMargin: 6
      anchors.rightMargin: 6
      anchors.topMargin: 2
      anchors.bottomMargin: 2
      radius: height / 2
      color: root.background

      Row {
        anchors.left: parent.left
        anchors.leftMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: 27
          implicitHeight: 27
          radius: width / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

          OmarchyButton { anchors.centerIn: parent }
        }

        V4ActiveWindow { }
      }

      Row {
        anchors.centerIn: parent
        spacing: 4

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: center3Row.implicitWidth + 10
          implicitHeight: 27
          radius: 12
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

          Row {
            id: center3Row
            anchors.centerIn: parent
            spacing: 2

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.usageIcon(root.cpuPercent) + " "
              color: root.foreground
              font.family: "JetBrainsMono Nerd Font Propo"
              font.pixelSize: 18

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.run("omarchy-launch-or-focus-tui btop")
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.usageIcon(root.memoryPercent) + "  "
              color: root.foreground
              font.family: "JetBrainsMono Nerd Font Propo"
              font.pixelSize: 18

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.run("omarchy-launch-or-focus-tui btop")
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.mediaTitle !== "" ? "  " + root.mediaTitle + " " : "         No media           "
              color: root.foreground
              font.family: "JetBrainsMono Nerd Font Propo"
              font.pixelSize: 12
              font.bold: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.run("playerctl play-pause")
              }
            }
          }
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: workspaces.implicitWidth + 10
          implicitHeight: 27
          radius: 12
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

          WorkspaceDots {
            id: workspaces
            anchors.centerIn: parent
          }
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: infoRow.implicitWidth + 10
          implicitHeight: 27
          radius: 12
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

          Row {
            id: infoRow
            anchors.centerIn: parent
            spacing: 1

            WidgetSlot {
              widgetId: "omarchy.clock"
              settings: ({ format: "hh:mm AP • ddd, dd/MM", formatAlt: "dddd, d MMMM yyyy" })
            }
            GameModeButton { }
            WidgetSlot { widgetId: "omarchy.indicators" }
            WidgetSlot { widgetId: "omarchy.system-update" }
          }
        }
      }

      Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: rightModules.implicitWidth + 10
        implicitHeight: 27
        radius: 12
        color: "transparent"

        Row {
          id: rightModules
          anchors.centerIn: parent
          spacing: 1

          WidgetSlot { widgetId: "omarchy.tray" }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: 4
            radius: 2
            color: root.foreground
            opacity: 0.75
          }
          WidgetSlot { widgetId: "omarchy.audio" }
          WidgetSlot { widgetId: "omarchy.bluetooth" }
          WidgetSlot { widgetId: "omarchy.network" }
          WidgetSlot { widgetId: "omarchy.power" }
        }
      }
    }

    PopupWindow {
      id: tooltipWindow
      visible: root.tooltipTarget !== null && root.tooltipText !== "" && root.targetWindow(root.tooltipTarget) === barWindow
      color: "transparent"
      implicitWidth: tooltipBubble.implicitWidth
      implicitHeight: tooltipBubble.implicitHeight

      anchor {
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          if (!root.tooltipTarget || root.targetWindow(root.tooltipTarget) !== barWindow) return
          var point = barWindow.contentItem.mapFromItem(root.tooltipTarget, root.tooltipTarget.width / 2 - tooltipWindow.implicitWidth / 2, root.tooltipTarget.height + 6)
          rect.x = Math.round(point.x)
          rect.y = Math.round(point.y)
        }
      }

      Rectangle {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: Color.tooltip.background
        radius: Style.cornerRadius
        border.width: 1
        border.color: Color.tooltip.border

        Text {
          id: tooltipLabel
          anchors.centerIn: parent
          text: root.tooltipText
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
