import AppKit
import UserNotifications

private let bundleID = "local.mac-battery-monitor.app"
private let serviceLabel = "local.mac-battery-monitor"
private let support = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/MacBatteryMonitor")

private struct ThresholdSettings: Equatable {
    let alert: Int
    let lowPower: Int
    let intervalMinutes: Int
    static let defaults = ThresholdSettings(alert: 30, lowPower: 20)
    var rearm: Int { min(100, max(alert, lowPower) + 6) }

    init(alert: Int, lowPower: Int, intervalMinutes: Int = 10) {
        self.alert = alert
        self.lowPower = lowPower
        self.intervalMinutes = intervalMinutes
    }

    static func parse(_ text: String) throws -> ThresholdSettings {
        var line = text
        while line.last == "\n" { line.removeLast() }
        let parts = line.split(separator: " ")
        let legacy = parts.count == 3 && parts.first == "v1"
        let modern = parts.count == 4 && parts.first == "v2"
        guard !line.contains("\n"), !line.contains("\r"), legacy || modern,
              let alert = Int(parts[1]), let lowPower = Int(parts[2]),
              (1...99).contains(alert), (1...99).contains(lowPower),
              String(alert) == parts[1], String(lowPower) == parts[2]
        else {
            throw NSError(domain: "MacBatteryMonitor.Settings", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Configuración inválida. Selecciona porcentajes de 1 a 99 y un intervalo de 1 a 120 minutos, y guarda los ajustes."])
        }
        let minutes = modern ? Int(parts[3]) : 10
        guard let minutes = minutes, (1...120).contains(minutes), !modern || String(minutes) == parts[3] else {
            throw NSError(domain: "MacBatteryMonitor.Settings", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "El intervalo debe ser un entero de 1 a 120 minutos."])
        }
        return ThresholdSettings(alert: alert, lowPower: lowPower, intervalMinutes: minutes)
    }
}

private struct CommandResult {
    let status: Int32
    let output: String
}

private func command(_ executable: String, _ arguments: [String]) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    // Leer antes de esperar evita bloquear el proceso si llena el pipe.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(status: process.terminationStatus,
                         output: String(decoding: data, as: UTF8.self))
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func appleScriptQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n") + "\""
}

private func batterySummary(_ output: String) -> String {
    guard output.contains("-InternalBattery-"),
          let range = output.range(of: #"\d{1,3}(?=%;)"#, options: .regularExpression)
    else { return "No se encontró una batería interna." }
    let source = output.contains("'AC Power'") ? "Conectado a corriente" : "Usando batería"
    return "Batería al \(output[range]) % · \(source)"
}

// El mismo bundle sirve como emisor de notificaciones en ejecuciones breves.
// Se ejecuta solo cuando hay que pedir permiso o enviar un aviso.
private final class NotificationRunner: NSObject, UNUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()
    let message: String?

    init(message: String?) {
        self.message = message
    }

    func finish(_ code: Int32, _ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
        DispatchQueue.main.async { exit(code) }
    }

    func deliver() {
        guard let message = message else { finish(0, "Notificaciones autorizadas"); return }
        let content = UNMutableNotificationContent()
        content.title = "Monitor de batería"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error = error { self.finish(1, error.localizedDescription) }
            else { self.finish(0, "Aviso aceptado por macOS") }
        }
    }

    func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        center.delegate = self
        // Límite incluso si el servicio de notificaciones no responde.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            self.finish(1, "Tiempo agotado al contactar con las notificaciones de macOS")
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliver()
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error = error { self.finish(1, error.localizedDescription) }
                    else if granted { self.deliver() }
                    else { self.finish(2, "Permiso denegado. Revisa Ajustes del Sistema → Notificaciones.") }
                }
            case .denied:
                self.finish(2, "Avisos desactivados. Revisa Ajustes del Sistema → Notificaciones → Mac Battery Monitor.")
            @unknown default:
                self.finish(1, "Estado de autorización desconocido")
            }
        }
        NSApplication.shared.run()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

private final class Card: NSView {
    init(_ content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 14
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }
}

private final class WindowBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.isSelectable = true
    return field
}

private func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 10) -> NSStackView {
    let view = NSStackView(views: views)
    view.orientation = vertical ? .vertical : .horizontal
    view.alignment = vertical ? .leading : .centerY
    view.spacing = spacing
    if vertical {
        for child in views { child.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true }
    }
    return view
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let previewPath: String?
    private var window: NSWindow!
    private let stateText = label("Comprobando…", size: 16, weight: .semibold)
    private let batteryText = label("", color: .secondaryLabelColor)
    private let permissionText = label("", color: .secondaryLabelColor)
    private let feedback = label("Instala el monitor para recibir avisos aunque cierres esta ventana.", color: .secondaryLabelColor)
    private let alertMetric = label("30 %", size: 27, weight: .bold, color: .systemGreen)
    private let powerMetric = label("20 %", size: 27, weight: .bold, color: .systemGreen)
    private let intervalMetric = label("10 min", size: 27, weight: .bold, color: .systemGreen)
    private let settingsHint = label("", size: 12, color: .secondaryLabelColor)
    private let alertChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private let powerChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private let intervalChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private var currentSettings = ThresholdSettings.defaults
    private var unsavedThresholds = false
    private var buttons: [NSButton] = []
    private var installButton: NSButton!
    private var permissionButton: NSButton!
    private var busy = false

    private var permissionPath: String { "/private/etc/sudoers.d/mac-battery-monitor-\(getuid())" }
    private var hasRule: Bool { FileManager.default.fileExists(atPath: permissionPath) }
    private var scriptDirectory: URL { Bundle.main.resourceURL!.appendingPathComponent("scripts") }

    init(previewPath: String? = nil) {
        self.previewPath = previewPath
        super.init()
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let result = NSButton(title: title, target: self, action: action)
        result.bezelStyle = .rounded
        result.bezelColor = .controlBackgroundColor
        result.controlSize = .large
        buttons.append(result)
        return result
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Acerca de Mac Battery Monitor", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApplication.shared.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 790),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Mac Battery Monitor"
        window.isReleasedWhenClosed = false
        window.contentView = makeContent()
        window.center()
        if let path = previewPath {
            // Vista de revisión: no consulta batería ni instala el monitor.
            stateText.stringValue = "○  Monitor listo para instalar"
            batteryText.stringValue = "Las comprobaciones comenzarán al instalar el monitor."
            permissionText.stringValue = "Opcional. macOS requiere autorización para cambiar el modo de energía."
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.savePreview(path) }
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        refresh()
    }

    private func savePreview(_ path: String) {
        guard let content = window.contentView else { exit(1) }
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
        content.effectiveAppearance.performAsCurrentDrawingAppearance {
            content.cacheDisplay(in: content.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: path)); print("Vista previa: \(path)") }
        catch { fputs("\(error)\n", stderr); exit(1) }
        NSApplication.shared.terminate(nil)
    }

    private func makeContent() -> NSView {
        let art = NSImageView()
        art.image = NSImage(contentsOf: Bundle.main.url(forResource: "banner", withExtension: "png")!)
        art.imageScaling = .scaleProportionallyUpOrDown
        art.translatesAutoresizingMaskIntoConstraints = false
        art.widthAnchor.constraint(equalToConstant: 120).isActive = true
        art.heightAnchor.constraint(equalToConstant: 120).isActive = true
        art.wantsLayer = true
        art.layer?.cornerRadius = 22
        art.layer?.masksToBounds = true

        let heading = stack([
            label("MAC BATTERY MONITOR", size: 11, weight: .bold, color: .secondaryLabelColor),
            label("Tu batería, bajo control.", size: 26, weight: .bold),
            label("Avisos a tiempo y bajo consumo cuando lo necesitas. Sin mantener la app abierta.", size: 14, color: .secondaryLabelColor)
        ], spacing: 10)
        let hero = stack([heading, art], vertical: false, spacing: 20)
        hero.distribution = .fill

        func metric(_ value: NSTextField, _ detail: String) -> NSView {
            Card(stack([value,
                        label(detail, size: 12, color: .secondaryLabelColor)], spacing: 3))
        }
        let metrics = stack([metric(alertMetric, "Aviso de batería"), metric(powerMetric, "Bajo consumo"),
                             metric(intervalMetric, "Entre comprobaciones")], vertical: false, spacing: 12)
        metrics.distribution = .fillEqually

        for choice in [alertChoice, powerChoice] {
            choice.addItems(withTitles: (1...99).map { "\($0) %" })
            choice.controlSize = .large
            choice.target = self
            choice.action = #selector(thresholdEdited)
        }
        alertChoice.setAccessibilityLabel("Porcentaje del aviso de batería")
        powerChoice.setAccessibilityLabel("Porcentaje para activar bajo consumo")
        alertChoice.selectItem(at: currentSettings.alert - 1)
        powerChoice.selectItem(at: currentSettings.lowPower - 1)
        intervalChoice.addItems(withTitles: (1...120).map { "\($0) min" })
        intervalChoice.controlSize = .large
        intervalChoice.target = self
        intervalChoice.action = #selector(thresholdEdited)
        intervalChoice.setAccessibilityLabel("Minutos entre comprobaciones")
        intervalChoice.selectItem(at: currentSettings.intervalMinutes - 1)
        settingsHint.stringValue = "Porcentajes de 1 a 99 · Intervalo de 1 a 120 min.\nRearme al \(currentSettings.rearm) %."
        let choices = stack([
            stack([label("Avisar al llegar a", size: 12), alertChoice], spacing: 4),
            stack([label("Activar bajo consumo al", size: 12), powerChoice], spacing: 4),
            stack([label("Comprobar cada", size: 12), intervalChoice], spacing: 4)
        ], vertical: false, spacing: 12)
        choices.distribution = .fillEqually
        let settings = Card(stack([
            label("Personalizar monitor", size: 15, weight: .semibold), choices,
            stack([settingsHint, button("Guardar ajustes", action: #selector(saveThresholds))], vertical: false, spacing: 12)
        ], spacing: 8))

        installButton = button("Instalar monitor", action: #selector(installMonitor))
        installButton.bezelColor = .systemGreen
        let refreshButton = button("Actualizar estado", action: #selector(refresh))
        let monitor = Card(stack([stateText, batteryText,
                                  stack([installButton, refreshButton], vertical: false)], spacing: 10))
        permissionButton = button("Autorizar bajo consumo…", action: #selector(configurePermission))
        let permission = Card(stack([
            label("Bajo consumo automático", size: 15, weight: .semibold),
            permissionText,
            permissionButton
        ], spacing: 8))
        let actions = stack([
            button("Probar aviso", action: #selector(testNotification)),
            button("Ver logs", action: #selector(openLogs)),
            button("Desinstalar monitor…", action: #selector(uninstallMonitor))
        ], vertical: false, spacing: 8)
        let root = stack([hero, metrics, settings, monitor, permission, actions, feedback], spacing: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        let content = WindowBackground()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        for view in [hero, metrics, settings, monitor, permission, actions, feedback] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        return content
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if window != nil && !busy && previewPath == nil { refresh() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func perform(_ executable: String, _ arguments: [String], completion: @escaping (CommandResult) -> Void) {
        guard !busy else { return }
        busy = true
        buttons.forEach { $0.isEnabled = false }
        alertChoice.isEnabled = false
        powerChoice.isEnabled = false
        intervalChoice.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async {
            let result: CommandResult
            do { result = try command(executable, arguments) }
            catch { result = CommandResult(status: 1, output: error.localizedDescription) }
            DispatchQueue.main.async {
                self.busy = false
                self.buttons.forEach { $0.isEnabled = true }
                self.alertChoice.isEnabled = true
                self.powerChoice.isEnabled = true
                self.intervalChoice.isEnabled = true
                completion(result)
            }
        }
    }

    private func report(_ result: CommandResult, success: String) {
        if result.status == 0 { feedback.stringValue = success }
        else {
            feedback.stringValue = "No se pudo completar la operación."
            let alert = NSAlert()
            alert.messageText = "Revisa la operación"
            alert.informativeText = String(result.output.suffix(6000))
            alert.alertStyle = .warning
            alert.runModal()
        }
        refresh()
    }

    @objc private func refresh() {
        guard !busy else { return }
        loadThresholds()
        permissionText.stringValue = hasRule
            ? "Autorización instalada para activar el modo al \(currentSettings.lowPower) %."
            : "Opcional. macOS requiere autorización para cambiar el modo de energía."
        permissionButton.title = hasRule ? "Retirar autorización…" : "Autorizar bajo consumo…"
        let service = "gui/\(getuid())/\(serviceLabel)"
        perform("/bin/launchctl", ["print", service]) { result in
            let installed = result.status == 0
            self.stateText.stringValue = installed ? "●  Monitor activo · cada \(self.currentSettings.intervalMinutes) min" : "○  Monitor sin instalar o desactivado"
            self.stateText.textColor = installed ? .systemGreen : .labelColor
            self.installButton.title = installed ? "Actualizar monitor" : "Instalar monitor"
            // Solo consulta al abrir, activar la ventana o pulsar Actualizar.
            self.perform("/usr/bin/pmset", ["-g", "batt"]) { battery in
                self.batteryText.stringValue = battery.status == 0
                    ? batterySummary(battery.output)
                    : "No se pudo consultar la batería."
            }
        }
    }

    private func loadThresholds() {
        let file = support.appendingPathComponent("settings")
        do {
            currentSettings = FileManager.default.fileExists(atPath: file.path)
                ? try ThresholdSettings.parse(String(contentsOf: file, encoding: .utf8)) : .defaults
            alertMetric.stringValue = "\(currentSettings.alert) %"
            powerMetric.stringValue = "\(currentSettings.lowPower) %"
            intervalMetric.stringValue = "\(currentSettings.intervalMinutes) min"
            settingsHint.stringValue = "Porcentajes de 1 a 99 · Intervalo de 1 a 120 min.\nRearme al \(currentSettings.rearm) %."
            if !unsavedThresholds {
                alertChoice.selectItem(at: currentSettings.alert - 1)
                powerChoice.selectItem(at: currentSettings.lowPower - 1)
                intervalChoice.selectItem(at: currentSettings.intervalMinutes - 1)
            }
        } catch {
            feedback.stringValue = error.localizedDescription
        }
    }

    @objc private func thresholdEdited() {
        unsavedThresholds = true
        feedback.stringValue = "Cambios sin guardar. Pulsa Guardar ajustes para aplicarlos."
    }

    @objc private func saveThresholds() {
        let alert = alertChoice.indexOfSelectedItem + 1
        let power = powerChoice.indexOfSelectedItem + 1
        let minutes = intervalChoice.indexOfSelectedItem + 1
        guard (1...99).contains(alert), (1...99).contains(power), (1...120).contains(minutes) else { return }
        let script = scriptDirectory.appendingPathComponent("battery-monitor.sh").path
        let installed = support.appendingPathComponent("battery-monitor.sh")
        if FileManager.default.fileExists(atPath: installed.path)
            && !FileManager.default.contentsEqual(atPath: installed.path, andPath: script) {
            feedback.stringValue = "Pulsa Actualizar monitor antes de guardar estos ajustes. Se conservará la configuración actual."
            return
        }
        perform("/bin/bash", [script, "--configure", String(alert), String(power), String(minutes)]) { result in
            if result.status == 0 { self.unsavedThresholds = false }
            let success: String
            if !FileManager.default.fileExists(atPath: installed.path) {
                success = "Ajustes guardados. Pulsa Instalar monitor para comenzar las comprobaciones."
            } else {
                success = "Ajustes guardados: aviso al \(alert) %, bajo consumo al \(power) % y comprobaciones cada \(minutes) min."
            }
            self.report(result, success: success)
        }
    }

    @objc private func installMonitor() {
        feedback.stringValue = "Instalando el monitor para tu usuario…"
        let script = scriptDirectory.appendingPathComponent("install.sh").path
        perform("/bin/bash", [script, "--app-bundle", Bundle.main.bundlePath]) { result in
            if result.status != 0 { self.report(result, success: ""); return }
            let executable = support.appendingPathComponent("Notifier.app/Contents/MacOS/MacBatteryMonitor").path
            self.perform(executable, ["--request-notifications"]) { authorization in
                self.report(authorization, success: self.unsavedThresholds
                    ? "Monitor actualizado. Pulsa Guardar ajustes para aplicar los cambios pendientes."
                    : "Monitor instalado. Puedes cerrar la app; launchd se encarga de las comprobaciones.")
            }
        }
    }

    @objc private func testNotification() {
        let installed = support.appendingPathComponent("Notifier.app/Contents/MacOS/MacBatteryMonitor").path
        let executable = FileManager.default.isExecutableFile(atPath: installed)
            ? installed : Bundle.main.executablePath!
        perform(executable, ["--notify", "Prueba del monitor de batería."]) { result in
            self.report(result, success: "Aviso enviado a macOS. Concentración puede ocultarlo.")
        }
    }

    @objc private func configurePermission() {
        let removing = hasRule
        let alert = NSAlert()
        alert.messageText = removing ? "Retirar autorización de bajo consumo" : "Autorizar bajo consumo automático"
        alert.informativeText = removing
            ? "Se necesita administrador para eliminar la regla de /etc/sudoers.d. El modo de energía actual se conserva. Después de continuar, macOS pedirá autenticación."
            : "Se necesita administrador porque macOS reserva los cambios de energía a root. Se añadirá una regla para tu usuario que permite únicamente activar bajo consumo con batería: /usr/bin/pmset -b lowpowermode 1. El ajuste permanece activo hasta que lo cambies en Ajustes del Sistema. Después de continuar, macOS pedirá autenticación."
        alert.addButton(withTitle: "Continuar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let script = scriptDirectory.appendingPathComponent("power-permission.sh").path
        let shell = "/bin/bash \(shellQuote(script)) \(removing ? "remove" : "install") \(getuid())"
        let source = "do shell script \(appleScriptQuote(shell)) with administrator privileges"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            if (error[NSAppleScript.errorNumber] as? Int) == -128 {
                feedback.stringValue = "Autorización cancelada."
            } else {
                report(CommandResult(status: 1, output: error.description), success: "")
            }
        } else if result != nil {
            feedback.stringValue = removing ? "Autorización retirada." : "Autorización instalada. Se aplicará al detectar \(currentSettings.lowPower) % o menos."
        }
        refresh()
    }

    @objc private func openLogs() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacBatteryMonitor")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { report(CommandResult(status: 1, output: error.localizedDescription), success: ""); return }
        NSWorkspace.shared.open(directory)
    }

    @objc private func uninstallMonitor() {
        let alert = NSAlert()
        alert.messageText = "Desinstalar el monitor"
        alert.informativeText = "Se detendrán las comprobaciones y se eliminarán el estado y los ajustes guardados. Los logs y esta app se conservan."
            + (hasRule ? " La autorización opcional sigue instalada: puedes retirarla con el botón Retirar autorización." : "")
        alert.addButton(withTitle: "Desinstalar monitor")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("/bin/bash", [scriptDirectory.appendingPathComponent("uninstall.sh").path]) { result in
            self.report(result, success: "Monitor desinstalado. Puedes eliminar esta app desde Finder.")
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--self-test"] {
    let custom = try? ThresholdSettings.parse("v1 45 25\n")
    let independent = try? ThresholdSettings.parse("v1 20 60\n")
    let maximum = try? ThresholdSettings.parse("v1 99 99\n")
    let scheduled = try? ThresholdSettings.parse("v2 45 25 17\n")
    let shortest = try? ThresholdSettings.parse("v2 30 20 1\n")
    let longest = try? ThresholdSettings.parse("v2 30 20 120\n")
    let invalidSettings = ["v1 0 20", "v1 30 100", "v1 3.5 20", "v1 030 20", "v1 30 20 extra",
                           "v2 30 20", "v1 30\n20", "\nv1 30 20", "v1 $(touch injected) 20",
                           "v2 30 20 0", "v2 30 20 121", "v2 30 20 1.5", "v2 30 20 01", "v2 30 20 5 extra"]
    guard shellQuote("a'b") == "'a'\\''b'",
          custom == ThresholdSettings(alert: 45, lowPower: 25), custom?.rearm == 51,
          custom?.intervalMinutes == 10,
          scheduled == ThresholdSettings(alert: 45, lowPower: 25, intervalMinutes: 17),
          shortest?.intervalMinutes == 1, longest?.intervalMinutes == 120,
          independent?.lowPower == 60, independent?.alert == 20,
          maximum?.rearm == 100,
          invalidSettings.allSatisfy({ (try? ThresholdSettings.parse($0)) == nil }),
          appleScriptQuote("a\"b\\c") == "\"a\\\"b\\\\c\"",
          batterySummary("Now drawing from 'AC Power'\n -InternalBattery-0 (id=123) 95%; discharging;")
            == "Batería al 95 % · Conectado a corriente",
          Bundle.main.bundleIdentifier == bundleID,
          let resource = Bundle.main.resourceURL,
          FileManager.default.fileExists(atPath: resource.appendingPathComponent("scripts/install.sh").path),
          FileManager.default.fileExists(atPath: resource.appendingPathComponent("banner.png").path)
    else { fputs("Bundle o escape de argumentos inválido\n", stderr); exit(1) }
    print("App verificada: bundle, recursos, argumentos, porcentajes e intervalo. No se abrió la interfaz ni se modificó el sistema.")
    exit(0)
} else if arguments == ["--request-notifications"] {
    let runner = NotificationRunner(message: nil)
    withExtendedLifetime(runner) { runner.start() }
} else if arguments.count == 2 && arguments[0] == "--notify" {
    let runner = NotificationRunner(message: arguments[1])
    withExtendedLifetime(runner) { runner.start() }
} else if arguments.count == 2 && arguments[0] == "--preview" {
    let application = NSApplication.shared
    let delegate = AppDelegate(previewPath: arguments[1])
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
} else if !arguments.isEmpty {
    fputs("Argumentos no válidos\n", stderr)
    exit(2)
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
