import SwiftUI
import Combine
import Speech
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Model

enum EntryMark: String, Codable {
    case none
    case red
    case yellow
    case green
}

enum ChronologyDisplayMode {
    case time
    case color
}

struct ChronologyEntry: Identifiable, Codable {
    let id: UUID
    var time: Date
    var sender: String
    var receiver: String
    var content: String
    var mark: EntryMark = .none

    init(
        id: UUID = UUID(),
        time: Date,
        sender: String,
        receiver: String,
        content: String,
        mark: EntryMark = .none
    ) {
        self.id = id
        self.time = time
        self.sender = sender
        self.receiver = receiver
        self.content = content
        self.mark = mark
    }
}

// MARK: - ViewModel

final class ChronologyViewModel: ObservableObject {

    @Published var entries: [ChronologyEntry] = []
    
    @Published var chronologyTitle: String

    init() {

        chronologyTitle = ""

        loadCustomDictionary()
        loadEntries()

        if chronologyTitle.isEmpty {
            chronologyTitle = defaultChronologyTitle()
        }
    }
    @Published var selectedSender = "本部"
    @Published var selectedReceiver = "自隊"
    @Published var selectedMarkFilter: EntryMark? = nil
    @Published var contentText = ""
    @Published var headquartersName = "高知県災害対策本部"
    
    @Published var searchText = ""
    @Published var displayMode: ChronologyDisplayMode = .time
    
    @Published var customDictionary: [String: String] = [
        "いーみす": "EMIS",
        "えみす": "EMIS",
        "でぃーまっと": "DMAT",
        "えすしーゆー": "SCU"
    ]
    
    @Published var newDictionaryKey = ""
    @Published var newDictionaryValue = ""
    
    @Published var newPartyName = ""

    func addPartyName() {
        let name = newPartyName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return
        }

        if !senderOptions.contains(name) {
            senderOptions.append(name)
        }

        if !receiverOptions.contains(name) {
            receiverOptions.append(name)
        }

        newPartyName = ""
    }
    
    private let dictionaryKey = "CustomDictionary"
    
    private let entriesFileName = "chronology_entries.json"

    private var entriesFileURL: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(entriesFileName)
    }
    
    @Published var senderOptions = [
        "本部",
        "自隊",
        "災害拠点病院",
        "SCU",
        "避難所",
        "DMAT",
        "本部長",
        "院長",
        "県庁",
        "市役所",
        "指揮所",
        "救護班"
    ]

    @Published var receiverOptions = [
        "本部",
        "自隊",
        "災害拠点病院",
        "SCU",
        "避難所",
        "DMAT",
        "本部長",
        "院長",
        "県庁",
        "市役所",
        "指揮所",
        "救護班"
    ]
    
    
    
    var displayedEntries: [ChronologyEntry] {
        let filtered = entries.filter { entry in
            searchText.isEmpty ||
            entry.sender.localizedCaseInsensitiveContains(searchText) ||
            entry.receiver.localizedCaseInsensitiveContains(searchText) ||
            entry.content.localizedCaseInsensitiveContains(searchText)
        }

        if let selectedMarkFilter {

            return filtered
                .filter { $0.mark == selectedMarkFilter }
                .sorted { $0.time < $1.time }

        } else {

            return filtered.sorted { $0.time < $1.time }
        }
    }

    private func markPriority(_ mark: EntryMark) -> Int {
        switch mark {
        case .red:
            return 0
        case .yellow:
            return 1
        case .green:
            return 2
        case .none:
            return 3
        }
    }
    
    var sortedEntries: [ChronologyEntry] {
        entries.sorted { $0.time < $1.time }
    }

    // MARK: Add Entry
    
    func safeFileName(_ text: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return text.components(separatedBy: invalid).joined(separator: "_")
    }
    
    func toggleMarkFilter(_ mark: EntryMark) {

        if selectedMarkFilter == mark {

            selectedMarkFilter = nil

        } else {

            selectedMarkFilter = mark
        }
    }
    
    func importJSON(from url: URL) {
        do {
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            entries = try JSONDecoder().decode([ChronologyEntry].self, from: data)
            entries.sort { $0.time < $1.time }
            saveEntries()

        } catch {
            print("JSON読込エラー:", error)
        }
    }
    
    func exportJSON() -> URL? {

        let title = safeFileName(chronologyTitle)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title).json")

        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            print("JSON出力エラー:", error)
            return nil
        }
    }
    
    func exportCSV() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"

        var csv = "時刻,発,受,内容,マーク\n"

        for entry in entries.sorted(by: { $0.time < $1.time }) {
            let line = [
                formatter.string(from: entry.time),
                entry.sender,
                entry.receiver,
                entry.content,
                entry.mark.rawValue
            ]
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: ",")

            csv += line + "\n"
        }

        let title = safeFileName(chronologyTitle)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title).csv")

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("CSV出力エラー:", error)
            return nil
        }
    }
    
    func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: entriesFileURL, options: [.atomic])
        } catch {
            print("JSON保存エラー:", error)
        }
    }

    func loadEntries() {
        do {
            let data = try Data(contentsOf: entriesFileURL)
            entries = try JSONDecoder().decode([ChronologyEntry].self, from: data)
        } catch {
            print("JSON読み込みなし、または失敗:", error)
        }
    }
    
    func saveCustomDictionary() {

        UserDefaults.standard.set(
            customDictionary,
            forKey: dictionaryKey
        )
    }
    
    func loadCustomDictionary() {

        if let saved = UserDefaults.standard.dictionary(
            forKey: dictionaryKey
        ) as? [String: String] {

            customDictionary = saved
        }
    }
    
    func addCustomDictionaryWord() {
        let key = newDictionaryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = newDictionaryValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !key.isEmpty, !value.isEmpty else {
            return
        }

        customDictionary[key] = value
        saveCustomDictionary()

        print("辞書登録:", key, "→", value)
        print(customDictionary)

        newDictionaryKey = ""
        newDictionaryValue = ""
    }
    
    func applyCustomDictionary(
        to text: String
    ) -> String {

        var converted = text

        for (key, value) in customDictionary {

            converted = converted.replacingOccurrences(
                of: key,
                with: value
            )
        }

        return converted
    }
    
    func swapSenderReceiver() {

        let temp = selectedSender

        selectedSender = selectedReceiver

        selectedReceiver = temp
    }

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
            content: applyCustomDictionary(to: contentText)
        )

        entries.append(newEntry)

        entries.sort {
            $0.time < $1.time
        }

        contentText = ""
        saveEntries()
    }
    
    func setMark(
        _ mark: EntryMark,
        for entry: ChronologyEntry
    ) {

        guard let index = entries.firstIndex(
            where: { $0.id == entry.id }
        ) else {
            return
        }

        if entries[index].mark == mark {

            entries[index].mark = .none

        } else {

            entries[index].mark = mark
        }
        saveEntries()
    }
    
    func updateSender(for entry: ChronologyEntry, newSender: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].sender = newSender
        saveEntries()
    }

    func updateReceiver(for entry: ChronologyEntry, newReceiver: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].receiver = newReceiver
        saveEntries()
    }

    func updateContent(for entry: ChronologyEntry, newContent: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].content = newContent
        saveEntries()
    }

    // MARK: Delete Entry

    func deleteEntry(_ entry: ChronologyEntry) {

        entries.removeAll {
            $0.id == entry.id
        }
    }
    
    func updateTime(
        for entry: ChronologyEntry,
        newTime: Date
    ) {

        guard let index = entries.firstIndex(
            where: { $0.id == entry.id }
        ) else {
            return
        }

        entries[index].time = newTime

        entries.sort {
            $0.time < $1.time
        }
    }

    // MARK: Time Format
    
    func defaultChronologyTitle() -> String {

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"

        return "\(formatter.string(from: Date()))_Chronology"
    }

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
}

// MARK: - Main View

struct ContentView: View {
    
    enum EditingField {
        case time
        case sender
        case receiver
        case content
    }

    @State private var editingField: EditingField?
    @State private var editingEntry: ChronologyEntry?
    @State private var editingTime = Date()
    @State private var editingText = ""
    @State private var showingDictionarySheet = false
    @State private var showingNewLogConfirm = false
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var showingJSONImporter = false
    @State private var showingShareFormatDialog = false
    @State private var showingSaveFormatDialog = false
    @State private var showingPartySheet = false

    @StateObject private var vm = ChronologyViewModel()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @FocusState private var isContentFocused: Bool
    @FocusState private var isHeadquartersFocused: Bool
    @FocusState private var isTitleFocused: Bool

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
            speechRecognizer.requestAuthorization()
        }
        .sheet(item: $editingEntry) { entry in
            
            ZStack {
                
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    
                    if editingField == .time {
                        
                        Text("時刻を修正")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        DatePicker(
                            "時刻",
                            selection: $editingTime,
                            displayedComponents: [.hourAndMinute]
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .colorScheme(.light)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        
                        Button("保存") {
                            saveEditingEntry(entry)
                        }
                        .buttonStyle(.borderedProminent)
                        
                    } else {
                        
                        Text("内容を修正")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        TextField("修正", text: $editingText)
                            .padding(12)
                            .background(Color.gray.opacity(0.4))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .submitLabel(.done)
                            .onSubmit {
                                saveEditingEntry(entry)
                            }
                        
                        Button("保存") {
                            switch editingField {
                            case .sender:
                                vm.updateSender(for: entry, newSender: editingText)
                            case .receiver:
                                vm.updateReceiver(for: entry, newReceiver: editingText)
                            case .content:
                                vm.updateContent(for: entry, newContent: editingText)
                            default:
                                break
                            }
                            
                            editingEntry = nil
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button("キャンセル") {
                        editingEntry = nil
                    }
                }
                .padding()
                .foregroundColor(.white)
            }
        }
        
        .sheet(isPresented: $showingShareSheet) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .fileImporter(
            isPresented: $showingJSONImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else {
                    return
                }
                
                vm.importJSON(from: url)
                
            } catch {
                print("JSON読込エラー:", error)
            }
        }
        .alert("新規クロノロジーを開始しますか？", isPresented: $showingNewLogConfirm) {
            Button("現在のデータをCSV保存して開始") {
                if let url = vm.exportCSV() {
                    exportURL = url
                    showingShareSheet = true
                }
                
                vm.entries.removeAll()
                vm.saveEntries()
            }
            
            Button("保存せず新規開始", role: .destructive) {
                vm.entries.removeAll()
                vm.saveEntries()
            }
            
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在のクロノロジーは消去されます。必要ならCSV保存してください。")
        }
        
        .confirmationDialog(
            "共有形式を選択",
            isPresented: $showingShareFormatDialog
        ) {

            Button("JSON共有") {

                if let url = vm.exportJSON() {
                    exportURL = url
                    showingShareSheet = true
                }
            }

            Button("CSV共有") {

                if let url = vm.exportCSV() {
                    exportURL = url
                    showingShareSheet = true
                }
            }

            Button("キャンセル", role: .cancel) {}
        }
        
        .confirmationDialog(
            "保存形式を選択",
            isPresented: $showingSaveFormatDialog
        ) {

            Button("JSON保存") {

                if let url = vm.exportJSON() {
                    exportURL = url
                    showingShareSheet = true
                }
            }

            Button("CSV保存") {

                if let url = vm.exportCSV() {
                    exportURL = url
                    showingShareSheet = true
                }
            }

            Button("キャンセル", role: .cancel) {}
        }
    }
        
    private func chronologyRow(_ entry: ChronologyEntry) -> some View {
        entryRow(entry)
            .id(entry.id)
            .listRowBackground(Color.black)
            .contextMenu {
                Button("時刻を修正") {
                    editingField = .time
                    editingTime = entry.time
                    editingEntry = entry
                }
                
                Button("発を修正") {
                    editingField = .sender
                    editingText = entry.sender
                    editingEntry = entry
                }
                
                Button("受を修正") {
                    editingField = .receiver
                    editingText = entry.receiver
                    editingEntry = entry
                }
                
                Button("内容を修正") {
                    editingField = .content
                    editingText = entry.content
                    editingEntry = entry
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    vm.setMark(.red, for: entry)
                } label: {
                    Label("赤", systemImage: "tag.fill")
                }
                .tint(.red)
                
                Button {
                    vm.setMark(.yellow, for: entry)
                } label: {
                    Label("黄", systemImage: "tag.fill")
                }
                .tint(.yellow)
                
                Button {
                    vm.setMark(.green, for: entry)
                } label: {
                    Label("緑", systemImage: "tag.fill")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    vm.deleteEntry(entry)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
    }
        
        private func saveEditingEntry(_ entry: ChronologyEntry) {
            
            switch editingField {
                
            case .sender:
                vm.updateSender(for: entry, newSender: editingText)
                
            case .receiver:
                vm.updateReceiver(for: entry, newReceiver: editingText)
                
            case .content:
                vm.updateContent(for: entry, newContent: editingText)
                
            case .time:
                vm.updateTime(for: entry, newTime: editingTime)
                
            default:
                break
            }
            
            editingEntry = nil
        }
    // MARK: Header View

    private var headerView: some View {
        
        VStack(spacing: 0) {
            
            TextField(
                "タイトル",
                text: $vm.chronologyTitle
            )
            .focused($isTitleFocused)
            .onChange(of: isTitleFocused) {
                if isTitleFocused && vm.chronologyTitle == "無題のクロノロジー" {
                    vm.chronologyTitle = ""
                }
            }
            .font(.headline)
            .padding(10)
            .background(Color.gray.opacity(0.4))
            .cornerRadius(8)
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            HStack(spacing: 8) {
                
                Text("時刻")
                    .frame(width: 60, alignment: .leading)
                
                Text("発")
                    .frame(width: 80, alignment: .leading)
                
                Text("受")
                    .frame(width: 80, alignment: .leading)
                
                Text("内容")
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button {
                    vm.toggleMarkFilter(.green)
                } label: {
                    Text("🟢")
                }
                .buttonStyle(.bordered)

                Button {
                    vm.toggleMarkFilter(.yellow)
                } label: {
                    Text("🟡")
                }
                .buttonStyle(.bordered)

                Button {
                    vm.toggleMarkFilter(.red)
                } label: {
                    Text("🔴")
                }
                .buttonStyle(.bordered)
            }
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.3))


            HStack(spacing: 8) {

                ZStack(alignment: .leading) {

                    if vm.searchText.isEmpty {
                        Text("検索")
                            .foregroundColor(.gray)
                            .padding(.leading, 12)
                    }

                    TextField("", text: $vm.searchText)
                        .padding(8)
                        .foregroundColor(.white)
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray, lineWidth: 1)
                )

                Button("新規") {
                    showingNewLogConfirm = true
                }
                .buttonStyle(.bordered)

                Button("保存") {
                    showingSaveFormatDialog = true
                }
                .buttonStyle(.bordered)

                Button("読込") {
                    showingJSONImporter = true
                }
                .buttonStyle(.bordered)

                Button("共有") {
                    showingShareFormatDialog = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black)
        }
    }

    // MARK: Timeline View

    private var timelineView: some View {

        ScrollViewReader { proxy in
            
            List {
                Section {
                    ForEach(vm.displayedEntries) { entry in
                        chronologyRow(entry)
                    }
                } header: {
                    dateHeader
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .onChange(of: vm.entries.count) {

                guard let last = vm.sortedEntries.last else {
                    return
                }

                DispatchQueue.main.async {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Color.black)
        }
    }

    // MARK: Date Header
    
    struct ShareSheet: UIViewControllerRepresentable {
        let items: [Any]

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(
                activityItems: items,
                applicationActivities: nil
            )
        }

        func updateUIViewController(
            _ uiViewController: UIActivityViewController,
            context: Context
        ) {}
    }

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
    
    private var partySheet: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Text("発・受 登録")
                    .font(.title2)
                    .foregroundColor(.white)

                TextField("例: 高知県庁", text: $vm.newPartyName)
                    .padding(12)
                    .background(Color.gray.opacity(0.4))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                    .submitLabel(.done)
                    .onSubmit {
                        vm.addPartyName()
                    }

                Button("登録") {
                    vm.addPartyName()
                }
                .buttonStyle(.borderedProminent)

                Button("閉じる") {
                    showingPartySheet = false
                }

                List {
                    ForEach(vm.senderOptions, id: \.self) { name in
                        Text(name)
                            .foregroundColor(.white)
                            .listRowBackground(Color.black)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .padding()
        }
    }

    // MARK: Entry Row

    private func entryRow(_ entry: ChronologyEntry) -> some View {

        HStack(spacing: 8) {

            Button {
                editingEntry = entry
                editingField = .time
                editingTime = entry.time
            } label: {
                Text(vm.formattedTime(entry.time))
                    .font(Font.system(size: 16, weight: .semibold))
                    .monospaced()
                    .foregroundColor(textColor(for: entry.mark))
                    .frame(width: 60, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                editingEntry = entry
                editingField = .sender
                editingText = entry.sender
            } label: {
                Text(entry.sender)
                    .foregroundColor(textColor(for: entry.mark))
                    .frame(width: 80, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                editingEntry = entry
                editingField = .receiver
                editingText = entry.receiver
            } label: {
                Text(entry.receiver)
                    .foregroundColor(textColor(for: entry.mark))
                    .frame(width: 80, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                editingEntry = entry
                editingField = .content
                editingText = entry.content
            } label: {
                Text(entry.content)
                    .font(Font.system(size: 20))
                    .foregroundColor(textColor(for: entry.mark))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    
    private func textColor(for mark: EntryMark) -> Color {

        switch mark {

        case .none:
            return .white

        case .red:
            return .red

        case .yellow:
            return .yellow

        case .green:
            return .green
        }
    }

    // MARK: Bottom Input Area
    
    private var dictionarySheet: some View {

        ZStack {

            Color.black
                .ignoresSafeArea()

            VStack(spacing: 16) {

                Text("単語登録")
                    .font(.title2)
                    .foregroundColor(.white)

                TextField(
                    "読み 例: いーみす",
                    text: $vm.newDictionaryKey
                )
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray, lineWidth: 1)
                )

                TextField(
                    "変換後 例: EMIS",
                    text: $vm.newDictionaryValue
                )
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray, lineWidth: 1)
                )
                .submitLabel(.done)
                .onSubmit {

                    vm.addCustomDictionaryWord()
                }

                Button("登録") {
                    vm.addCustomDictionaryWord()
                }
                .buttonStyle(.borderedProminent)

                Button("閉じる") {
                    showingDictionarySheet = false
                }

                List {
                    ForEach(
                        vm.customDictionary.sorted(by: { $0.key < $1.key }),
                        id: \.key
                    ) { key, value in

                        HStack {

                            Text(key)
                                .foregroundColor(.white)

                            Spacer()

                            Text(value)
                                .foregroundColor(.white)
                        }
                        .listRowBackground(Color.black)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .padding()
        }
    }

    private var bottomInputArea: some View {

        VStack(spacing: 12) {

            // MARK: HQ Name

            HStack {

                TextField(
                    "本部名",
                    text: $vm.headquartersName
                )
                .focused($isHeadquartersFocused)
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
                
                Button {

                    vm.swapSenderReceiver()

                } label: {

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title2)
                }
                .buttonStyle(.bordered)

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
                
                Button("発受登録") {
                    showingPartySheet = true
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showingPartySheet) {
                    partySheet
                }

                Spacer()
            }

            // MARK: Text Input

            TextField(
                "内容を入力",
                text: $vm.contentText
            )
            .focused($isContentFocused)
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

                    if speechRecognizer.isRecording {

                        speechRecognizer.stopRecording()

                        vm.contentText = vm.applyCustomDictionary(
                            to: speechRecognizer.transcribedText
                        )

                    } else {

                        do {
                            try speechRecognizer.startRecording()
                        } catch {
                            print("音声入力開始エラー:", error)
                        }
                    }

                } label: {

                    Label(
                        speechRecognizer.isRecording ? "停止" : "音声入力",
                        systemImage: speechRecognizer.isRecording ? "stop.fill" : "mic.fill"
                    )
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingDictionarySheet = true
                } label: {
                    Label("単語登録", systemImage: "text.badge.plus")
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showingDictionarySheet) {
                    dictionarySheet
                }

                Spacer()

                Button {
                    vm.addEntry()
                } label: {
                    Label("記録", systemImage: "plus.circle.fill")
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
