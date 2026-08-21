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
  readonly property color foreground: Color.bar.text
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

    visible: activeItem ? activeItem.visible : false
    implicitWidth: visible && activeItem ? activeItem.implicitWidth : 0
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

    function focus(workspaceId) {
      root.run("hyprctl dispatch " + root.shellQuote("hl.dsp.focus({ workspace = \\\"" + workspaceId + "\\\" })"))
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: 3

      Repeater {
        model: 8

        Item {
          required property int index
          readonly property int workspaceId: index + 1
          readonly property var workspace: dots.workspaceById(workspaceId)
          readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
          readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === workspaceId

          width: focused ? 18 : 12
          height: 24

          Rectangle {
            anchors.centerIn: parent
            width: parent.focused ? 16 : 6
            height: parent.focused ? 16 : 6
            radius: width / 2
            color: parent.focused ? root.foreground : "transparent"
            border.width: parent.focused ? 0 : 1
            border.color: root.foreground
            opacity: parent.focused || parent.occupied ? 1 : 0.45

            Rectangle {
              visible: parent.parent.focused
              anchors.centerIn: parent
              width: 5
              height: 5
              radius: 3
              color: root.background
            }

            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dots.focus(parent.workspaceId)
          }
        }
      }
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
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      anchors.topMargin: 2
      anchors.bottomMargin: 2
      radius: height / 2
      color: root.background

      Row {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Rectangle {
          implicitWidth: menuSlot.implicitWidth + 10
          implicitHeight: 27
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

          WidgetSlot {
            id: menuSlot
            anchors.centerIn: parent
            widgetId: "omarchy.menu"
          }
        }

        WidgetSlot {
          widgetId: "omarchy.active-window"
          settings: ({ maxWidth: 220 })
        }
      }

      Row {
        anchors.centerIn: parent
        spacing: 4

        Rectangle {
          implicitWidth: mediaSlot.implicitWidth + 10
          implicitHeight: 27
          radius: 12
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

          WidgetSlot {
            id: mediaSlot
            anchors.centerIn: parent
            widgetId: "omarchy.media"
          }
        }

        Rectangle {
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
            WidgetSlot { widgetId: "omarchy.indicators" }
            WidgetSlot { widgetId: "omarchy.system-update" }
          }
        }
      }

      Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: rightModules.implicitWidth + 10
        implicitHeight: 27
        radius: 12
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

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
