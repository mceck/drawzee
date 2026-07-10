import SwiftUI
import AppKit

struct ToolbarView: View {
    @ObservedObject var coordinator: DrawSessionCoordinator
    @State private var showColorPicker = false
    @State private var showSizePicker = false

    var body: some View {
        VStack(spacing: 16) {
            colorSwatch

            if !coordinator.isSidebarCollapsed {
                Group {
                    sizeSwatch

                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 30, height: 1)

                    toolButton(.pen, systemName: "pencil.tip")
                    toolButton(.highlighter, systemName: "paintbrush.pointed.fill")
                    shapeButton
                    toolButton(.spotlight, systemName: "flashlight.on.fill")
                    toolButton(.text, systemName: "textformat")

                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 30, height: 1)

                    Button {
                        coordinator.beginRegionScreenshotSelection()
                    } label: {
                        iconLabel(systemName: "camera.fill", selected: coordinator.isSelectingRegion)
                    }
                    .buttonStyle(.plain)
                    Button {
                        coordinator.toggleFreezeBackground()
                    } label: {
                        iconLabel(systemName: "snowflake", selected: coordinator.isBackgroundFrozen)
                    }
                    .buttonStyle(.plain)
                    actionButton(systemName: "trash.fill") {
                        coordinator.document.clear()
                    }
                }
                .transition(.opacity)
            }

            collapseButton

            if !coordinator.isSidebarCollapsed {
                actionButton(systemName: "xmark.circle.fill", tint: .red) {
                    coordinator.disableDrawMode()
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        // `NSHostingView` centers content that's smaller than its own bounds by
        // default. While collapsing/expanding, the panel's actual frame briefly
        // lags behind (or leads) the VStack's own ideal size, and without pinning
        // to the top here the whole toolbar would visibly drift toward the
        // panel's vertical center during that gap instead of staying anchored
        // at the color swatch, which is what made the resize read as a glitch.
        .frame(maxHeight: .infinity, alignment: .top)
        // Placed last so it wraps every modifier above, including the frame/
        // alignment change — `DrawSessionCoordinator.toggleSidebarCollapsed`
        // also wraps its own mutation in `withAnimation` for the branch that
        // isn't already covered by an async dispatch.
        .animation(.easeInOut(duration: DrawSessionCoordinator.sidebarAnimationDuration), value: coordinator.isSidebarCollapsed)
    }

    private var collapseButton: some View {
        Button {
            coordinator.toggleSidebarCollapsed()
        } label: {
            iconLabel(systemName: "chevron.up", selected: false)
                .rotationEffect(.degrees(coordinator.isSidebarCollapsed ? 180 : 0))
                // Image's default hit area hugs the glyph itself (thin for a
                // chevron), not the 36x36 frame around it — same class of issue
                // as the brush-size dot below; widen it to the whole square.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var colorSwatch: some View {
        Button {
            showColorPicker.toggle()
        } label: {
            Circle()
                .fill(Color(nsColor: coordinator.toolState.color))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showColorPicker, arrowEdge: .trailing) {
            ColorPickerPopover(coordinator: coordinator)
        }
    }

    private var sizeSwatch: some View {
        Button {
            showSizePicker.toggle()
        } label: {
            Circle()
                .fill(Color.white)
                .frame(width: max(4, min(20, coordinator.toolState.lineWidth)), height: max(4, min(20, coordinator.toolState.lineWidth)))
                .frame(width: 26, height: 26)
                // A `Circle` only hit-tests inside its own path by default, so at
                // small brush sizes the dot is a near-unclickable few points wide.
                // Widening the content shape to the full frame makes the whole
                // 26x26 button area clickable, not just the visible dot.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSizePicker, arrowEdge: .trailing) {
            VStack(spacing: 8) {
                Text("Brush size").font(.caption).foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { coordinator.toolState.lineWidth }, set: { coordinator.setLineWidth($0) }),
                    in: 1...40
                )
                .frame(width: 160)
            }
            .padding()
        }
    }

    private var shapeButton: some View {
        // `Menu`'s own label rendering doesn't reliably show a background applied
        // inside the label (the accent highlight silently didn't show up there) —
        // applying it to the `Menu` itself instead, behind its native control,
        // works around that and matches the other tool buttons.
        Menu {
            ForEach(ShapeKind.allCases, id: \.self) { shape in
                Button(shape.displayName) {
                    coordinator.setShape(shape)
                }
            }
        } label: {
            Image(systemName: coordinator.toolState.selectedShape.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 36, height: 36)
        .background(coordinator.toolState.selectedTool == .shape ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toolButton(_ tool: DrawingTool, systemName: String) -> some View {
        Button {
            coordinator.selectTool(tool)
        } label: {
            iconLabel(systemName: systemName, selected: coordinator.toolState.selectedTool == tool)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(systemName: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }

    private func iconLabel(systemName: String, selected: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(selected ? Color.accentColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ColorPickerPopover: View {
    @ObservedObject var coordinator: DrawSessionCoordinator

    private let presets: [NSColor] = [
        .systemYellow, .systemRed, .systemOrange, .systemGreen,
        .systemBlue, .systemPurple, .white, .black,
    ]

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24)), count: 4), spacing: 10) {
                ForEach(presets.indices, id: \.self) { index in
                    Circle()
                        .fill(Color(nsColor: presets[index]))
                        .frame(width: 24, height: 24)
                        .onTapGesture { coordinator.setColor(presets[index]) }
                }
            }
            ColorPicker(
                "Custom",
                selection: Binding(
                    get: { Color(nsColor: coordinator.toolState.color) },
                    set: { coordinator.setColor(NSColor($0)) }
                )
            )
        }
        .padding()
        .frame(width: 160)
    }
}
