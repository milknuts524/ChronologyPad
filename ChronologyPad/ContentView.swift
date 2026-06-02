import SwiftUI
import Combine

// MARK: - Model

struct ChronologyEntry: Identifiable {

    let id = UUID()

    var time: Date
    var sender: String
    var receiver: String
    var content: String
}

// MARK: - ViewModel

final class ChronologyViewModel: ObservableObject {

    @Published var entries: [ChronologyEntry] = []

    @Published var selectedSender = "本部"
    @Published var selectedReceiver = "自隊"
    @Published var contentText = ""
    @Published var headquartersName = "高知県災害対策本部"

    let senderOptions = [
        "本部",
        "自隊",
        "SCU",
        "救護所",
        "高知大",
        "DMAT"
    ]

    let receiverOptions = [
        "本部",
        "自隊",
        "SCU",
        "救護所",
        "高知大",
        "DMAT"
    ]

    // MARK: Add Entry

    func addEntry() {

        guard !contentText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            return
        }

        let newEntry = ChronologyEntry(
            time: Date(),
            sender: selectedSender,
            receiver: selectedReceiver,
            content: contentText
        )

        entries.append(newEntry)

        entries.sort {
            $0.time < $1.time
        }

        contentText = ""
    }

    // MARK: Delete Entry

    func deleteEntry(_ entry: ChronologyEntry) {

        entries.removeAll {
            $0.id == entry.id
        }
    }

    // MARK: Time Format

    func formattedTime(_ date: Date) -> String {

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        return formatter.string(from: date)
    }

    // MARK: Date Format

    func formattedDate(_ date: Date) -> String {

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"

        return formatter.string(from: date)
    }

    // MARK: Date Header Check

    func shouldShowDateHeader(
        current: ChronologyEntry,
        previous: ChronologyEntry?
    ) -> Bool {

        guard let previous else {
            return true
        }

        return !Calendar.current.isDate(
            current.time,
            inSameDayAs: previous.time
        )
    }

    // MARK: Mock Data

    func loadMockData() {

        entries = [

            ChronologyEntry(
                time: Date(),
                sender: "本部",
                receiver: "自隊",
                content: "EMIS更新"
            ),

            ChronologyEntry(
                time: Date().addingTimeInterval(120),
                sender: "高知大",
                receiver: "本部",
                content: "停電なし"
            ),

            ChronologyEntry(
                time: Date().addingTimeInterval(240),
                sender: "SCU",
                receiver: "自隊",
                content: "搬送開始"
            ),

            ChronologyEntry(
                time: Date().addingTimeInterval(360),
                sender: "DMAT",
                receiver: "本部",
                content: "南国IC到着"
            )
        ]
    }
}

// MARK: - Main View

struct ContentView: View {

    @StateObject private var vm = ChronologyViewModel()

    var body: some View {

        ZStack {

            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {

                headerView

                Divider()

                timelineView

                Divider()

                bottomInputArea
            }
            .foregroundColor(.white)
        }
        .onAppear {

            if vm.entries.isEmpty {
                vm.loadMockData()
            }
        }
    }

    // MARK: Header View

    private var headerView: some View {

        HStack(spacing: 8) {

            Text("時刻")
                .frame(width: 60, alignment: .leading)

            Text("発")
                .frame(width: 80, alignment: .leading)

            Text("受")
                .frame(width: 80, alignment: .leading)

            Text("内容")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.3))
    }

    // MARK: Timeline View

    private var timelineView: some View {

        ScrollViewReader { proxy in
            
            List {
                
                Section {
                    
                    ForEach(
                        Array(vm.entries.enumerated()),
                        id: \.element.id
                    ) { index, entry in
                        
                        entryRow(entry)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0,
                                    leading: 0,
                                    bottom: 0,
                                    trailing: 0
                                )
                            )
                            .listRowBackground(Color.black)
                        
                    }
                    
                } header: {
                    
                    dateHeader
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
        }
    }

    // MARK: Date Header

    private var dateHeader: some View {

        HStack {

            Text(vm.formattedDate(Date()))
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.25))
    }

    // MARK: Entry Row

    private func entryRow(
        _ entry: ChronologyEntry
    ) -> some View {

        HStack(spacing: 8) {

            Text(vm.formattedTime(entry.time))
                .font(
                    Font.system(
                        size: 16,
                        weight: .semibold
                    )
                )
                .monospaced()
                .frame(width: 60, alignment: .leading)

            Text(entry.sender)
                .frame(width: 80, alignment: .leading)

            Text(entry.receiver)
                .frame(width: 80, alignment: .leading)

            Text(entry.content)
                .font(Font.system(size: 20))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .swipeActions {

            Button(role: .destructive) {

                vm.deleteEntry(entry)

            } label: {

                Label(
                    "削除",
                    systemImage: "trash"
                )
            }
        }
    }

    // MARK: Bottom Input Area

    private var bottomInputArea: some View {

        VStack(spacing: 12) {

            // MARK: HQ Name

            HStack {

                TextField(
                    "本部名",
                    text: $vm.headquartersName
                )
                .font(.headline)
                .padding(10)
                .background(Color.gray.opacity(0.25))
                .cornerRadius(8)
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray, lineWidth: 1)
                )

                Spacer()
            }

            // MARK: Sender / Receiver

            HStack(spacing: 24) {

                HStack(spacing: 8) {

                    Text("発")
                        .font(.headline)

                    Picker(
                        "発",
                        selection: $vm.selectedSender
                    ) {

                        ForEach(
                            vm.senderOptions,
                            id: \.self
                        ) {

                            Text($0)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: 8) {

                    Text("受")
                        .font(.headline)

                    Picker(
                        "受",
                        selection: $vm.selectedReceiver
                    ) {

                        ForEach(
                            vm.receiverOptions,
                            id: \.self
                        ) {

                            Text($0)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Spacer()
            }

            // MARK: Text Input

            TextField(
                "内容を入力",
                text: $vm.contentText
            )
            .font(.system(size: 22))
            .padding(12)
            .background(Color.gray.opacity(0.25))
            .cornerRadius(8)
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray, lineWidth: 1)
            )
            .submitLabel(.done)
            .onSubmit {

                vm.addEntry()
            }

            // MARK: Buttons

            HStack(spacing: 16) {

                Button {

                    // 音声入力は後日実装

                } label: {

                    Label(
                        "音声入力",
                        systemImage: "mic.fill"
                    )
                }
                .buttonStyle(.borderedProminent)

                Button {

                    // 単語登録は後日実装

                } label: {

                    Label(
                        "単語登録",
                        systemImage: "text.badge.plus"
                    )
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {

                    vm.addEntry()

                } label: {

                    Label(
                        "記録",
                        systemImage: "plus.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.15))
    }
}

#Preview {

    ContentView()
}
