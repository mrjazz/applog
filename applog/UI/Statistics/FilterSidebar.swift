import SwiftUI

struct FilterSidebar: View {
    @ObservedObject var viewModel: StatisticsViewModel
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var isAddingTag = false
    @State private var newTagName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Minimum Duration")
                HStack {
                    Text("Hide items under")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("", value: $viewModel.minDurationMinutes, format: .number)
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
                HStack(spacing: 6) {
                    Text(dateRangeFrom).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Text("–").foregroundStyle(.tertiary)
                    Text(dateRangeTo).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Picker("", selection: $viewModel.quickSet) {
                    ForEach(DateQuickSet.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

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

                VStack(spacing: 6) {
                    Button("Apply Tag to Node") {
                        if let nodeID = viewModel.selectedNodeID {
                            viewModel.applySelectedTag(toNode: nodeID)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.selectedNodeID == nil || viewModel.selectedTagID == nil)

                    if isRenaming {
                        HStack {
                            TextField("New name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(commitRename)
                            Button("Save", action: commitRename)
                        }
                    } else {
                        Button("Rename Tag") {
                            renameText = viewModel.tags.first(where: { $0.id == viewModel.selectedTagID })?.name ?? ""
                            isRenaming = true
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.selectedTagID == nil)
                    }
                }

                Toggle("Filter on selected tag", isOn: $viewModel.filterOnTag)
                    .font(.system(size: 12))
                    .toggleStyle(.checkbox)
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 232)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private static let dateRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private var dateRangeFrom: String {
        Self.dateRangeFormatter.string(from: viewModel.quickSet.range.from)
    }

    private var dateRangeTo: String {
        Self.dateRangeFormatter.string(from: viewModel.quickSet.range.to)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.4)
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isSelected = viewModel.selectedTagID == tag.id
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: tag.colorHex)).frame(width: 9, height: 9)
            Text(tag.name).font(.system(size: 12.5))
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor : .clear)
        .foregroundStyle(isSelected ? .white : .primary)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectedTagID = tag.id }
    }

    private func addTag() {
        guard !newTagName.isEmpty else { return }
        let palette = DefaultTagPalette.swatches
        let color = palette[viewModel.tags.count % palette.count].hex
        viewModel.createTag(name: newTagName, colorHex: color)
        newTagName = ""
        isAddingTag = false
    }

    private func commitRename() {
        viewModel.renameSelectedTag(to: renameText)
        isRenaming = false
    }
}
