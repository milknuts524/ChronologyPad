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

enum ImportMode {
    case replace
    case merge
}

struct ChronologyEntry: Identifiable, Codable {
    let id: UUID
    var time: Date
    var sender: String
    var receiver: String
    var content: String
    var colorTag: String?
    var headquarters: String
    var mark: EntryMark = .none

    init(
        id: UUID = UUID(),
        time: Date,
        sender: String,
        receiver: String,
        content: String,
        headquarters: String = "記録元不明",
        mark: EntryMark = .none
    ) {
        self.id = id
        self.time = time
        self.sender = sender
        self.receiver = receiver
        self.content = content
        self.headquarters = headquarters
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
        loadTemplates()

        if chronologyTitle.isEmpty {
            chronologyTitle = defaultChronologyTitle()
        }
    }
    @Published var selectedSender = "本部"
    @Published var selectedReceiver = "自隊"
    @Published var selectedMarkFilter: EntryMark? = nil
    @Published var contentText = ""
    @Published var headquartersName = "災害対策本部ロジ"
    
    @Published var searchText = ""
    @Published var displayMode: ChronologyDisplayMode = .time
    
    @Published var customDictionary: [String: String] = [
        "dまt": "DMAT",
        "えみs": "EMIS",
        "scう": "SCU",
        "jまt": "JMAT"
    ]
    
    @Published var newDictionaryKey = ""
    @Published var newDictionaryValue = ""
    
    @Published var newPartyName = ""
    
    @Published var templates: [String] = [
        "対策本部設置",
        "指揮所立ち上げ",
        "連絡要請",
        "了解しました",
        "SCU設営開始",
        "搬送開始",
        "搬送終了",
        "到着",
        "帰着",
        "解散"
    ]

    @Published var newTemplateText = ""
    
    func saveTemplates() {

        UserDefaults.standard.set(
            templates,
            forKey: "ChronologyTemplates"
        )
    }

    func loadTemplates() {

        if let saved =
            UserDefaults.standard.stringArray(
                forKey: "ChronologyTemplates"
            ) {

            templates = saved
        }
    }
    
    func mergeJSON(from url: URL) {
        do {
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let importedEntries = try JSONDecoder().decode([ChronologyEntry].self, from: data)

            let existingIDs = Set(entries.map { $0.id })
            let newEntries = importedEntries.filter {
                !existingIDs.contains($0.id)
            }

            entries.append(contentsOf: newEntries)
            entries.sort { $0.time < $1.time }

            saveEntries()

        } catch {
            print("JSON追加エラー:", error)
        }
    }
    
    func addTemplate() {

        let text = newTemplateText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !text.isEmpty else {
            return
        }

        templates.append(text)

        saveTemplates()

        newTemplateText = ""
    }
    
    func deleteTemplate(at offsets: IndexSet) {

        templates.remove(atOffsets: offsets)

        saveTemplates()
    }

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
    
    func exportPDF() -> URL? {

        let title = safeFileName(chronologyTitle)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title).pdf")

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 595, height: 842)
        )

        do {

            try renderer.writePDF(to: url) { context in

                context.beginPage()

                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 22)
                ]

                let textAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14)
                ]

                chronologyTitle.draw(
                    at: CGPoint(x: 20, y: 20),
                    withAttributes: titleAttributes
                )

                var y: CGFloat = 60

                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"

                for entry in entries.sorted(by: { $0.time < $1.time }) {

                    let line =
    """
    \(formatter.string(from: entry.time))
      \(entry.sender)
    → \(entry.receiver)
      \(entry.content)
    """

                    line.draw(
                        at: CGPoint(x: 20, y: y),
                        withAttributes: textAttributes
                    )

                    y += 40

                    if y > 780 {

                        context.beginPage()

                        y = 20
                    }
                }
            }

            return url

        } catch {

            print("PDF出力エラー:", error)

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
            content: applyCustomDictionary(to: contentText),
            headquarters: headquartersName
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

    struct EditingContext: Identifiable {
        let id = UUID()
        let entry: ChronologyEntry
        let field: EditingField
        var time: Date
        var text: String
    }

    @State private var editingContext: EditingContext?
    @State private var editingTime = Date()
    @State private var editingText = ""
    @State private var showingDictionarySheet = false
    @State private var showingNewLogConfirm = false
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var showingShareFormatDialog = false
    @State private var showingPartySheet = false
    @State private var showingEntryInfo: ChronologyEntry?
    @State private var showingTemplateSheet = false
    @State private var importMode: ImportMode = .replace
    @State private var showingFileImporter = false
    @State private var showingInfoSheet = false

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
        .sheet(item: $editingContext) { ctx in
            
            ZStack {
                
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    
                    if ctx.field == .time {
                        
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
                            vm.updateTime(for: ctx.entry, newTime: editingTime)
                            editingContext = nil
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
                                saveContext(ctx)
                            }
                        
                        Button("保存") {
                            saveContext(ctx)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button("キャンセル") {
                        editingContext = nil
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
        
        .sheet(isPresented: $showingInfoSheet) {
            infoSheet
        }
        
        .sheet(isPresented: $showingPartySheet) {
            partySheet
        }
        
        .sheet(isPresented: $showingDictionarySheet) {
            dictionarySheet
        }
        
        .sheet(isPresented: $showingTemplateSheet) {
            templateSheet
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
            
            Button("PDF共有") {

                if let url = vm.exportPDF() {

                    exportURL = url

                    showingShareSheet = true
                }
            }
            
            Button("キャンセル", role: .cancel) {}
        }
        
        .popover(item: $showingEntryInfo) { entry in
            ZStack {
                Color.black
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("記録情報")
                        .font(.headline)
                    
                    Text("記録元：\(entry.headquarters)")
                }
                .foregroundColor(.white)
                .padding()
            }
            .presentationCompactAdaptation(.popover)
        }
        
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else {
                    return
                }
                
                switch importMode {
                case .replace:
                    vm.importJSON(from: url)
                    
                case .merge:
                    vm.mergeJSON(from: url)
                }
                
            } catch {
                print("JSON読込エラー:", error)
            }
        }
    }
        
    private func chronologyRow(_ entry: ChronologyEntry) -> some View {
        entryRow(entry)
            .id(entry.id)
            .listRowBackground(Color.black)
            .contextMenu {
                Button("時刻を修正") {
                    editingTime = entry.time
                    editingContext = EditingContext(entry: entry, field: .time, time: entry.time, text: "")
                }
                
                Button("発を修正") {
                    editingText = entry.sender
                    editingContext = EditingContext(entry: entry, field: .sender, time: entry.time, text: entry.sender)
                }
                
                Button("受を修正") {
                    editingText = entry.receiver
                    editingContext = EditingContext(entry: entry, field: .receiver, time: entry.time, text: entry.receiver)
                }
                
                Button("内容を修正") {
                    editingText = entry.content
                    editingContext = EditingContext(entry: entry, field: .content, time: entry.time, text: entry.content)
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
        
        private func saveContext(_ ctx: EditingContext) {
            switch ctx.field {
            case .sender:
                vm.updateSender(for: ctx.entry, newSender: editingText)
            case .receiver:
                vm.updateReceiver(for: ctx.entry, newReceiver: editingText)
            case .content:
                vm.updateContent(for: ctx.entry, newContent: editingText)
            case .time:
                vm.updateTime(for: ctx.entry, newTime: editingTime)
            }
            editingContext = nil
        }
    // MARK: Header View

    private var headerView: some View {
        
        VStack(spacing: 0) {
            
            HStack(spacing: 8) {

                TextField(
                    "タイトル",
                    text: $vm.chronologyTitle
                )
                .focused($isTitleFocused)
                .onChange(of: isTitleFocused) {
                    if isTitleFocused {
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

                Button {
                    showingInfoSheet = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
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
                    vm.saveEntries()
                }
                .buttonStyle(.bordered)

                Button("読込") {
                    importMode = .replace
                    showingFileImporter = true
                }
                .buttonStyle(.bordered)

                Button("追加") {
                    importMode = .merge
                    showingFileImporter = true
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

                TextField("例: 遠山病院", text: $vm.newPartyName)
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
    
    private var infoSheet: some View {

        ZStack {

            Color.black
                .ignoresSafeArea()

            ScrollView {

                VStack(alignment: .leading, spacing: 20) {

                    Text("ChronologyPad")
                        .font(.title)
                        .bold()

                    Text("""
    このアプリケーションは、災害現場などを中心に必要となる「経時的な記録（クロノロジー）」を支援するアプリです。

    「時刻」「発」「受」「内容」など、必要な記録を迅速に入力・閲覧できるよう設計されています。
    
    また、他のiPadやPCへcsv/json/PDF形式で出力･共有したり、他のiPadやiPhoneからのデータを統合して表示できる機能を備えています。
    """)

                    Group {

                        Text("基本操作")
                            .font(.headline)

                        Text("""
    ・内容入力後、Returnで記録
    ・長押しで編集
    ・右スワイプで色分け
    ・左スワイプで削除
    """)

                        Text("保存・共有")
                            .font(.headline)

                        Text("""
    ・保存：
    このiPad内へ保存

    ・読込：
    保存済JSONを開く

    ・追加：
    他端末JSONを現在記録へ統合

    ・共有：
    JSON / CSV / PDF出力
    """)

                        Text("略語登録")
                            .font(.headline)

                        Text("""
    d → DMAT

    のような置換登録が可能です。
    """)

                        Text("定型文")
                            .font(.headline)

                        Text("""
    頻用文章をワンタップ入力できます。
    """)
                    }

                    Button("閉じる") {
                        showingInfoSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundColor(.white)
                .padding()
            }
        }
    }
    
    private var templateSheet: some View {

        ZStack {

            Color.black
                .ignoresSafeArea()

            VStack(spacing: 16) {

                Text("定型文")
                    .font(.title2)
                    .foregroundColor(.white)

                HStack {

                    TextField(
                        "定型文追加",
                        text: $vm.newTemplateText
                    )
                    .padding(10)
                    .background(Color.gray.opacity(0.4))
                    .cornerRadius(8)
                    .foregroundColor(.white)

                    Button("追加") {
                        vm.addTemplate()
                    }
                }

                List {

                    ForEach(vm.templates, id: \.self) { template in

                        Button {

                            vm.contentText = template

                            vm.addEntry()

                            showingTemplateSheet = false

                        } label: {

                            Text(template)
                                .foregroundColor(.white)
                        }
                        .listRowBackground(Color.black)
                    }
                    .onDelete(
                        perform: vm.deleteTemplate
                    )
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)

                Button("閉じる") {
                    showingTemplateSheet = false
                }
            }
            .padding()
        }
    }

    private func entryRow(_ entry: ChronologyEntry) -> some View {

        HStack(spacing: 8) {

            Button {
                editingTime = entry.time
                editingContext = EditingContext(entry: entry, field: .time, time: entry.time, text: "")
            } label: {
                Text(vm.formattedTime(entry.time))
                    .font(Font.system(size: 16, weight: .semibold))
                    .monospaced()
                    .foregroundColor(textColor(for: entry.mark))
                    .frame(width: 60, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                editingText = entry.sender
                editingContext = EditingContext(entry: entry, field: .sender, time: entry.time, text: entry.sender)
            } label: {
                Text(entry.sender)
                    .foregroundColor(textColor(for: entry.mark))
                    .frame(width: 80, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                editingText = entry.receiver
                editingContext = EditingContext(entry: entry, field: .receiver, time: entry.time, text: entry.receiver)
            } label: {
                Text(entry.receiver)
                    .foregroundColor(textColor(for: entry.mark))
                    .frame(width: 80, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                editingText = entry.content
                editingContext = EditingContext(entry: entry, field: .content, time: entry.time, text: entry.content)
            } label: {
                Text(entry.content)
                    .font(Font.system(size: 20))
                    .foregroundColor(textColor(for: entry.mark))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            Button {
                showingEntryInfo = entry
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.gray)
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

                Text("略語登録")
                    .font(.title2)
                    .foregroundColor(.white)

                TextField(
                    "読み 例: えみs",
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

            HStack(spacing: 8) {

                Text("入力者:")
                    .font(.headline)
                    .foregroundColor(.white)

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
                    Label("略語登録", systemImage: "text.badge.plus")
                }
                .buttonStyle(.bordered)
                
                Button {
                    showingTemplateSheet = true
                } label: {
                    Label("定型文", systemImage: "text.badge.star")
                }
                .buttonStyle(.bordered)

            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.15))
    }
}

#Preview {

    ContentView()
}
