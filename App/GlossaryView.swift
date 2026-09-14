import SwiftUI

struct GlossaryView: View {
    @Binding var glossary: [GlossaryEntry]

    var body: some View {
        List {
            ForEach($glossary) { $entry in
                HStack {
                    TextField("中文", text: $entry.chinese)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("English", text: $entry.english)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .onDelete { glossary.remove(atOffsets: $0) }

            Button {
                glossary.append(GlossaryEntry(chinese: "", english: ""))
            } label: {
                Label("新增", systemImage: "plus")
            }
        }
        .navigationTitle("术语表")
        .toolbar { EditButton() }
    }
}
