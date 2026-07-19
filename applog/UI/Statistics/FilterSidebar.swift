import SwiftUI

struct FilterSidebar: View {
    @ObservedObject var viewModel: StatisticsViewModel
    @State private var renamingTagID: Int64?
    @State private var renameText = ""
    @State private var isAddingTag = false
    @State private var newTagName = ""
    @State private var colorPickerTagID: Int64?
    @State private var selectedTagColor = Color.clear

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            tagsSection

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Minimum Duration")
                HStack {
                    Text("Hide items under")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("0", text: minDurationText)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    Text("min").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Name Contains")
                TextField("Substring…", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Date Range")
                Picker("", selection: $viewModel.quickSet) {
                    ForEach(DateQuickSet.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if viewModel.quickSet == .custom {
                    customRangeCalendars
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 232)
        .background(Color.appSidebarBackground)
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Tags")
            VStack(spacing: 1) {
                ForEach(viewModel.tags) { tag in
                    tagRow(tag)
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator))

            if isAddingTag {
                HStack {
                    TextField("Tag name", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTag)
                    Button("Add", action: addTag).disabled(newTagName.isEmpty)
                }
            } else {
                Button {
                    isAddingTag = true
                } label: {
                    Label("New Tag", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            Button("Apply Tag to Node") {
                if let nodeID = viewModel.selectedNodeID {
                    viewModel.applySelectedTag(toNode: nodeID)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(viewModel.selectedNodeID == nil || viewModel.selectedTagID == nil)

            Toggle("Filter on selected tag", isOn: $viewModel.filterOnTag)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
        }
    }

    /// Backs the "Hide items under" field with text rather than a numeric
    /// binding — an emptied field should mean "no minimum" (show everything),
    /// not silently keep the last committed number.
    private var minDurationText: Binding<String> {
        Binding(
            get: {
                viewModel.minDurationMinutes == 0 ? "" : String(format: "%g", viewModel.minDurationMinutes)
            },
            set: { newValue in
                viewModel.minDurationMinutes = Double(newValue) ?? 0
            }
        )
    }

    /// Standard macOS month-grid calendars for picking a custom range,
    /// shown only while "Custom Range" is selected.
    private var customRangeCalendars: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("From").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                DatePicker(
                    "", selection: Binding(get: { viewModel.customFrom }, set: viewModel.setCustomFrom),
                    in: ...viewModel.customTo, displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("To").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                DatePicker(
                    "", selection: Binding(get: { viewModel.customTo }, set: viewModel.setCustomTo),
                    in: viewModel.customFrom...Date(), displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.4)
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isSelected = viewModel.selectedTagID == tag.id
        let isRenaming = renamingTagID == tag.id
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: tag.colorHex))
                .frame(width: 9, height: 9)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    selectedTagColor = Color(hex: tag.colorHex)
                    colorPickerTagID = tag.id
                }
                .popover(
                    isPresented: Binding(
                        get: { colorPickerTagID == tag.id },
                        set: { if !$0 { colorPickerTagID = nil } }
                    ),
                    arrowEdge: .leading
                ) {
                    ColorPicker("Tag color", selection: $selectedTagColor, supportsOpacity: false)
                        .labelsHidden()
                        .padding()
                        .onChange(of: selectedTagColor) { newColor in
                            viewModel.updateTagColor(id: tag.id, to: newColor.hexString)
                        }
                }
            if isRenaming {
                TextField("Tag name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .onSubmit { commitRename(tag) }
            } else {
                Text(tag.name)
                    .font(.system(size: 12.5))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        renameText = tag.name
                        renamingTagID = tag.id
                    }
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor : .clear)
        .foregroundStyle(isSelected ? .white : .primary)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { viewModel.selectedTagID = tag.id }
    }

    private func addTag() {
        guard !newTagName.isEmpty else { return }
        let palette = DefaultTagPalette.swatches
        let color = palette[viewModel.tags.count % palette.count].hex
        viewModel.createTag(name: newTagName, colorHex: color)
        newTagName = ""
        isAddingTag = false
    }

    private func commitRename(_ tag: Tag) {
        viewModel.renameTag(id: tag.id, to: renameText)
        renamingTagID = nil
    }
}
