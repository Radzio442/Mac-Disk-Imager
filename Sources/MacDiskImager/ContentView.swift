import SwiftUI

struct ContentView: View {
    @StateObject private var c = ImagingController()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "externaldrive.fill.badge.plus").font(.system(size: 34))
                VStack(alignment: .leading) {
                    Text("Mac Disk Imager").font(.title.bold())
                    Text("READ / WRITE / VERIFY dla USB, SD i eMMC").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Odśwież") { c.refresh() }.disabled(c.isBusy)
            }

            if !c.helperInstalled {
                HStack {
                    Label("Helper administratora nie jest zainstalowany", systemImage: "lock.shield")
                    Spacer()
                    Button("Zainstaluj helper…") { c.installHelper() }
                }.padding(10).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            }

            GroupBox("Plik obrazu") {
                HStack {
                    Text(c.imageURL?.path ?? "Nie wybrano pliku").lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Otwórz obraz…") { c.chooseImage() }.disabled(c.isBusy)
                    Button("Nowa kopia…") { c.chooseDestination() }.disabled(c.isBusy)
                }.padding(6)
            }

            GroupBox("Dysk fizyczny") {
                HStack {
                    Picker("Urządzenie:", selection: $c.selectedDisk) {
                        Text("Wybierz dysk").tag(DiskDevice?.none)
                        ForEach(c.disks) { Text($0.displayName).tag(Optional($0)) }
                    }.pickerStyle(.menu).disabled(c.isBusy)
                    if let d = c.selectedDisk {
                        Text(d.readOnly ? "Tylko odczyt" : "Zapisywalny")
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(d.readOnly ? .red.opacity(0.15) : .green.opacity(0.15), in: Capsule())
                    }
                }.padding(6)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Weryfikuj po zapisie", isOn: $c.verifyAfterWrite).disabled(c.isBusy)
                Toggle("READ: kopiuj tylko zakres zajęty przez partycje", isOn: $c.readAllocatedOnly).disabled(c.isBusy)
                if c.readAllocatedOnly {
                    Text("Obraz kończy się za ostatnią wykrytą partycją, zamiast mieć rozmiar całego eMMC.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ProgressView(value: c.progress)
                HStack {
                    Text(c.statusText)
                    Spacer()
                    Text(c.detailText).monospacedDigit()
                }.font(.callout).foregroundStyle(.secondary)
            }

            ScrollView {
                Text(c.logText.isEmpty ? "Gotowy." : c.logText)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 125).padding(8).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            Spacer()
            HStack {
                Label("Dyski wewnętrzne są ukryte.", systemImage: "shield.checkered").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if c.isBusy { Button("ANULUJ") { c.cancel() } }
                Button("READ") { c.startRead() }.disabled(!c.canStart)
                Button("VERIFY") { c.startVerify() }.disabled(!c.canStart)
                Button("WRITE") { c.startWrite() }.buttonStyle(.borderedProminent).disabled(!c.canWrite)
            }
        }
        .padding(22)
        .onAppear { c.startup() }
        .alert("Instalacja komponentu systemowego", isPresented: $c.showHelperInstallPrompt) {
            Button("Zainstaluj…") { c.installHelper() }
            Button("Później", role: .cancel) { }
        } message: {
            Text("Mac Disk Imager potrzebuje jednorazowej instalacji helpera administratora, aby odczytywać i zapisywać fizyczne nośniki USB, SD i eMMC.")
        }
    }
}
