import QtQuick
import qs.Ui
import qs.Commons

// Two-handle slider for the adaptive brightness bounds, styled after
// qs.Ui.PanelSlider (same track/fill/knob treatment). Drag the nearest
// handle; handles keep a 5-point gap. Keyboard users press Enter on the
// row to pick which handle h/l edits (activeHandle).
Item {
  id: root

  property QtObject bar: null
  property int minValue: 0
  property int maxValue: 100
  property int gap: 5
  property int minimum: 1
  property int maximum: 100
  property int activeHandle: 0     // 0 = low, 1 = high (keyboard target)
  property bool dragging: false
  property int liveMin: minValue
  property int liveMax: maxValue
  // Live backlight level (daemon output) shown as a non-interactive marker.
  property int currentValue: 0

  readonly property int step: 1

  signal moved()
  signal releasedMin(int value)
  signal releasedMax(int value)

  onMinValueChanged: if (!dragging) liveMin = minValue
  onMaxValueChanged: if (!dragging) liveMax = maxValue

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(Style.space(22), knobSize + Style.spacing.md)

  readonly property real trackHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
  readonly property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
  readonly property real range: Math.max(0.0001, maximum - minimum)

  function frac(v) { return Math.max(0, Math.min(1, (v - minimum) / range)) }
  function snap(v) {
    v = Math.round(v)
    if (v < minimum) v = minimum
    if (v > maximum) v = maximum
    return v
  }

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.trackHeight
    radius: height / 2
    color: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "#333"
  }

  Rectangle {
    id: fill
    anchors.verticalCenter: track.verticalCenter
    height: track.height
    radius: track.radius
    color: root.bar ? root.bar.foreground : Color.foreground
    x: track.width * root.frac(root.liveMin)
    width: Math.max(0, track.width * (root.frac(root.liveMax) - root.frac(root.liveMin)))

    Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  }

  // Current applied brightness: thin accent bar + live percentage above it.
  // Purely informative — no MouseArea, never intercepts slider input.
  Item {
    id: levelMarker
    x: Math.max(0, Math.min(track.width - width, track.width * root.frac(root.currentValue) - width / 2))
    width: Math.max(levelText.implicitWidth, Style.space(10))
    height: parent.height
    z: 1
    Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    Text {
      id: levelText
      textFormat: Text.PlainText
      text: Math.round(root.currentValue) + "%"
      color: Color.accent
      font.family: root.bar ? root.bar.fontFamily : ""
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
    }

    Rectangle {
      width: Math.max(2, Style.space(2))
      height: track.height + Style.space(10)
      radius: 1
      color: Color.accent
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: track.verticalCenter
    }

    Canvas {
      width: Style.space(8)
      height: Style.space(5)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: levelText.bottom
      onPaint: {
        var c = getContext2D()
        c.reset()
        c.fillStyle = Color.accent
        c.beginPath()
        c.moveTo(0, 0)
        c.lineTo(width, 0)
        c.lineTo(width / 2, height)
        c.closePath()
        c.fill()
      }
    }
  }

  component Handle: BorderSurface {
    required property int index
    width: root.knobSize
    height: root.knobSize
    radius: root.knobSize / 2
    color: root.bar ? root.bar.foreground : Color.foreground
    borderSpec: Border.flat(root.bar ? root.bar.background : "#101315", Math.max(1, Style.space(2)))
    anchors.verticalCenter: track.verticalCenter
    readonly property bool isActive: index === root.activeHandle
    scale: (root.dragging && isActive) || mouseArea.containsMouse
           ? 1.15
           : (isActive ? 1.1 : 1.0)
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
  }

  Handle {
    id: lowHandle
    index: 0
    x: Math.max(0, Math.min(track.width - width, track.width * root.frac(root.liveMin) - width / 2))
    Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  }

  Handle {
    id: highHandle
    index: 1
    x: Math.max(0, Math.min(track.width - width, track.width * root.frac(root.liveMax) - width / 2))
    Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    property int grabbed: -1

    function valueFromX(x) {
      var clamped = Math.max(0, Math.min(track.width, x))
      return root.snap(root.minimum + (clamped / track.width) * root.range)
    }

    onPressed: function(mouse) {
      var v = valueFromX(mouse.x)
      // grab the nearest handle
      grabbed = Math.abs(v - root.liveMin) <= Math.abs(v - root.liveMax) ? 0 : 1
      root.dragging = true
      root.activeHandle = grabbed
      moveGrabbed(v)
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      moveGrabbed(valueFromX(mouse.x))
    }
    onReleased: {
      if (!root.dragging) return
      root.dragging = false
      if (grabbed === 0) root.releasedMin(root.liveMin)
      else root.releasedMax(root.liveMax)
      grabbed = -1
    }

    function moveGrabbed(v) {
      if (grabbed === 0) {
        var hi = root.liveMax - root.gap
        if (v > hi) v = hi
        if (v < root.minimum) v = root.minimum
        root.liveMin = v
      } else {
        var lo = root.liveMin + root.gap
        if (v < lo) v = lo
        if (v > root.maximum) v = root.maximum
        root.liveMax = v
      }
      root.moved()
    }
  }
}
