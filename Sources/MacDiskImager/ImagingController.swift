import Foundation
import AppKit

@MainActor
final class ImagingController: ObservableObject {
    enum Mode: String { case write = "WRITE", read = "READ", verify = "VERIFY" }
    static let helperPath = "/Library/PrivilegedHelperTools/pl.madejak.MacDiskImagerHelper"

    @Published var disks: [DiskDevice] = []
    @Published var selectedDisk: DiskDevice?
    @Published var imageURL: URL?
    @Published var isBusy = false
    @Published var progress = 0.0
    @Published var statusText = "Gotowy"
    @Published var detailText = ""
    @Published var logText = ""
    @Published var verifyAfterWrite = true
    @Published var readAllocatedOnly = true
    @Published var helperInstalled = false
    @Published var showHelperInstallPrompt = false

    private let service = DiskService()
    private var process: Process?
    private var startedAt = Date()

    var canStart: Bool { !isBusy && helperInstalled && selectedDisk != nil && imageURL != nil }
    var canWrite: Bool { canStart && selectedDisk?.readOnly == false }

    func refresh() {
        helperInstalled = FileManager.default.isExecutableFile(atPath: Self.helperPath)
        do {
            let old = selectedDisk?.id
            disks = try service.externalPhysicalDisks()
            selectedDisk = disks.first(where: { $0.id == old }) ?? disks.first
            statusText = disks.isEmpty ? "Nie wykryto dysków zewnętrznych" : "Gotowy"
        } catch { append("Błąd listy dysków: \(error.localizedDescription)") }
    }


    func startup() {
        refresh()
        if !helperInstalled {
            showHelperInstallPrompt = true
        }
    }

    func installHelper() {
        guard let bundled = Bundle.main.url(forResource: "MacDiskImagerHelper", withExtension: nil)?.path else {
            append("Brak helpera w pakiecie aplikacji."); return
        }
        let cmd = "/bin/mkdir -p /Library/PrivilegedHelperTools; /bin/cp \(Shell.shellQuote(bundled)) \(Shell.shellQuote(Self.helperPath)); /usr/sbin/chown root:wheel \(Shell.shellQuote(Self.helperPath)); /bin/chmod 4755 \(Shell.shellQuote(Self.helperPath))"
        let script = "do shell script \"\(Shell.appleScriptQuote(cmd))\" with administrator privileges"
        do {
            let r = try Shell.run("/usr/bin/osascript", ["-e", script])
            if r.status == 0 { append("Helper zainstalowany.") } else { append(r.error) }
        } catch { append(error.localizedDescription) }
        refresh()
    }

    func chooseImage() {
        let p = NSOpenPanel(); p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.message = "Wybierz surowy obraz IMG/BIN/ISO"
        if p.runModal() == .OK { imageURL = p.url; statusText = "Wybrano obraz" }
    }
    func chooseDestination() {
        let p = NSSavePanel(); p.nameFieldStringValue = "emmc-backup.img"
        if p.runModal() == .OK { imageURL = p.url; statusText = "Wybrano plik docelowy" }
    }

    func startWrite() {
        guard let d = selectedDisk else { return }
        let a = NSAlert(); a.alertStyle = .critical; a.messageText = "Nadpisać cały \(d.id)?"
        a.informativeText = "Wszystkie dane na \(d.displayName) zostaną usunięte."
        a.addButton(withTitle: "ZAPISZ"); a.addButton(withTitle: "Anuluj")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        run(.write)
    }
    func startRead() { run(.read) }
    func startVerify() { run(.verify) }
    func cancel() { process?.terminate(); append("Anulowanie…") }

    private func run(_ mode: Mode) {
        guard let disk = selectedDisk, let image = imageURL else { return }
        isBusy = true; progress = 0; logText = ""; detailText = ""; startedAt = Date()
        statusText = "\(mode.rawValue) — przygotowanie…"

        let total: UInt64
        if mode == .read && readAllocatedOnly {
            if let compactSize = try? service.allocatedPartitionSpan(for: disk), compactSize < disk.size {
                total = compactSize
                append("Tryb skrócony: kopiuję od sektora 0 do końca ostatniej partycji: \(ByteCountFormatter.string(fromByteCount: Int64(compactSize), countStyle: .file)) z \(ByteCountFormatter.string(fromByteCount: Int64(disk.size), countStyle: .file)).")
            } else {
                total = disk.size
                append("Nie udało się wyznaczyć końca partycji — wykonywana jest pełna kopia nośnika.")
            }
        } else {
            total = mode == .read ? disk.size : UInt64((try? image.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: Self.helperPath)
        p.arguments = [mode.rawValue.lowercased(), disk.devicePath, disk.rawPath, String(total)]
        let progressPipe = Pipe(); p.standardError = progressPipe
        var imageHandle: FileHandle?
        do {
            switch mode {
            case .write, .verify:
                imageHandle = try FileHandle(forReadingFrom: image); p.standardInput = imageHandle
                p.standardOutput = FileHandle.nullDevice
            case .read:
                FileManager.default.createFile(atPath: image.path, contents: nil)
                imageHandle = try FileHandle(forWritingTo: image); p.standardOutput = imageHandle
                p.standardInput = FileHandle.nullDevice
            }
            progressPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let data = h.availableData; guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor in self?.consume(text, total: total) }
            }
            let handleToClose = imageHandle
            p.terminationHandler = { [weak self, handleToClose] proc in
                try? handleToClose?.close()
                Task { @MainActor in
                    guard let self else { return }
                    progressPipe.fileHandleForReading.readabilityHandler = nil
                    self.isBusy = false
                    if proc.terminationStatus == 0 {
                        self.progress = 1; self.statusText = "\(mode.rawValue) zakończony"
                        self.append("Operacja zakończona pomyślnie.")
                        if mode == .write && self.verifyAfterWrite { self.run(.verify); return }
                    } else {
                        self.statusText = "Błąd (kod \(proc.terminationStatus))"
                    }
                    self.refresh()
                }
            }
            process = p; try p.run()
        } catch {
            try? imageHandle?.close(); isBusy = false; append("Nie można uruchomić: \(error.localizedDescription)")
        }
    }

    private func consume(_ text: String, total: UInt64) {
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            if line.hasPrefix("PROGRESS "), let bytes = UInt64(line.dropFirst(9)) {
                progress = total > 0 ? min(Double(bytes) / Double(total), 1) : 0
                let elapsed = max(Date().timeIntervalSince(startedAt), 0.01)
                let speed = Double(bytes) / elapsed
                statusText = "Przeniesiono \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
                detailText = String(format: "%.1f%% • %@/s", progress * 100,
                                    ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))
            } else { append(line) }
        }
    }
    private func append(_ s: String) { guard !s.isEmpty else { return }; logText += (logText.isEmpty ? "" : "\n") + s }
}
