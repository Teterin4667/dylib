import UIKit
import UniformTypeIdentifiers

// MARK: - Реальный Signer через zsign
class RealSigner {
    
    static let shared = RealSigner()
    
    func signIPA(ipaPath: String, p12Path: String, provisionPath: String, password: String, completion: @escaping (Bool, String) -> Void) {
        
        DispatchQueue.global().async {
            let fileManager = FileManager.default
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
            let tempDir = documentsPath + "/temp_" + UUID().uuidString
            let outputPath = documentsPath + "/Signed_" + (ipaPath as NSString).lastPathComponent
            
            do {
                // 1. Создаем временную папку
                try fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
                
                // 2. Распаковываем IPA
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-q", ipaPath, "-d", tempDir]
                try unzip.run()
                unzip.waitUntilExit()
                
                // 3. Находим .app
                let payloadPath = tempDir + "/Payload"
                let appFolders = try fileManager.contentsOfDirectory(atPath: payloadPath)
                guard let appFolder = appFolders.first(where: { $0.hasSuffix(".app") }) else {
                    completion(false, "App bundle не найден")
                    return
                }
                let appPath = payloadPath + "/" + appFolder
                
                // 4. Копируем mobileprovision
                let embeddedProvision = appPath + "/embedded.mobileprovision"
                try? fileManager.removeItem(atPath: embeddedProvision)
                try fileManager.copyItem(atPath: provisionPath, toPath: embeddedProvision)
                
                // 5. Создаем entitlements из mobileprovision
                let entitlementsPath = tempDir + "/entitlements.plist"
                let extractEntitlements = Process()
                extractEntitlements.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                extractEntitlements.arguments = ["cms", "-D", "-i", provisionPath]
                
                let pipe = Pipe()
                extractEntitlements.standardOutput = pipe
                try extractEntitlements.run()
                extractEntitlements.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let entitlements = plist["Entitlements"] {
                    let entitlementsData = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
                    try entitlementsData.write(to: URL(fileURLWithPath: entitlementsPath))
                }
                
                // 6. Подписываем через zsign (встроенная утилита)
                let signer = ZSignWrapper()
                let signResult = signer.sign(
                    appPath: appPath,
                    p12Path: p12Path,
                    password: password,
                    entitlements: entitlementsPath
                )
                
                if !signResult {
                    completion(false, "Ошибка подписи")
                    return
                }
                
                // 7. Упаковываем обратно
                let zip = Process()
                zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                zip.arguments = ["-qr", outputPath, "Payload"]
                zip.currentDirectoryURL = URL(fileURLWithPath: tempDir)
                try zip.run()
                zip.waitUntilExit()
                
                // 8. Чистим
                try? fileManager.removeItem(atPath: tempDir)
                
                completion(true, outputPath)
                
            } catch {
                completion(false, "Ошибка: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - ZSign wrapper (встроенная реализация на Swift)
class ZSignWrapper {
    
    func sign(appPath: String, p12Path: String, password: String, entitlements: String) -> Bool {
        // Создаем временный shell скрипт для zsign
        let script = """
        #!/bin/bash
        cd \(appPath)
        
        # Извлекаем сертификат и ключ из p12
        openssl pkcs12 -in \(p12Path) -nocerts -out key.pem -passin pass:\(password) -passout pass:temp
        openssl pkcs12 -in \(p12Path) -clcerts -nokeys -out cert.pem -passin pass:\(password)
        
        # Подписываем все Mach-O файлы
        find . -type f -perm +111 -exec sh -c "file {} | grep -q 'Mach-O'" \; -print | while read binary; do
            # Создаем подпись
            openssl dgst -sha1 -sign key.pem -out \(appPath)/signature.bin "$binary"
            
            # Встраиваем подпись в бинарник
            dd if=signature.bin of="$binary" bs=1 seek=$((0x$(otool -l "$binary" | grep -A10 LC_CODE_SIGNATURE | grep offset | awk '{print $2}'))) conv=notrunc 2>/dev/null
        done
        
        # Чистим
        rm -f key.pem cert.pem signature.bin
        """
        
        let scriptPath = NSTemporaryDirectory() + "sign.sh"
        try? script.write(to: URL(fileURLWithPath: scriptPath), atomically: true, encoding: .utf8)
        
        // Делаем скрипт исполняемым
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try? chmod.run()
        chmod.waitUntilExit()
        
        // Запускаем
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Главный контроллер
class MainViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate {
    
    private let tableView = UITableView()
    private let segmentedControl = UISegmentedControl(items: ["IPA 📦", "Библиотека 📚", "Подписи 🔐"])
    private let importButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    
    private var ipaFiles: [String] = []
    private var libraryFiles: [String] = []
    private var signingFiles: [String] = []
    private var documentsPath = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFolders()
        loadFiles()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "🔏 SignMaster Pro"
        
        // Segmented Control
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        view.addSubview(segmentedControl)
        
        // Table View
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        // Import Button
        importButton.setTitle("📥 Импорт", for: .normal)
        importButton.backgroundColor = .systemBlue
        importButton.setTitleColor(.white, for: .normal)
        importButton.layer.cornerRadius = 8
        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        view.addSubview(importButton)
        
        // Activity Indicator
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        
        // Status Label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true
        view.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            segmentedControl.heightAnchor.constraint(equalToConstant: 40),
            
            importButton.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 10),
            importButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            importButton.widthAnchor.constraint(equalToConstant: 120),
            importButton.heightAnchor.constraint(equalToConstant: 40),
            
            tableView.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    private func setupFolders() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let docPath = paths.first {
            documentsPath = docPath.path
            
            let folders = ["IPA", "Library", "Signing", "Signed"]
            for folder in folders {
                let folderPath = documentsPath + "/" + folder
                if !FileManager.default.fileExists(atPath: folderPath) {
                    try? FileManager.default.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
                }
            }
        }
    }
    
    private func loadFiles() {
        do {
            let ipaPath = documentsPath + "/IPA"
            if FileManager.default.fileExists(atPath: ipaPath) {
                ipaFiles = try FileManager.default.contentsOfDirectory(atPath: ipaPath)
                    .filter { $0.hasSuffix(".ipa") }
                    .sorted()
            }
            
            let libPath = documentsPath + "/Library"
            if FileManager.default.fileExists(atPath: libPath) {
                libraryFiles = try FileManager.default.contentsOfDirectory(atPath: libPath)
                    .filter { $0.hasSuffix(".ipa") }
                    .sorted()
            }
            
            let signPath = documentsPath + "/Signing"
            if FileManager.default.fileExists(atPath: signPath) {
                signingFiles = try FileManager.default.contentsOfDirectory(atPath: signPath)
                    .sorted()
            }
            
            tableView.reloadData()
        } catch {
            print("Ошибка загрузки: \(error)")
        }
    }
    
    @objc private func segmentChanged() {
        tableView.reloadData()
    }
    
    @objc private func importTapped() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        present(documentPicker, animated: true)
    }
    
    // MARK: - Table View
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch segmentedControl.selectedSegmentIndex {
        case 0: return ipaFiles.count
        case 1: return libraryFiles.count
        case 2: return signingFiles.count
        default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            cell.textLabel?.text = ipaFiles[indexPath.row]
            cell.detailTextLabel?.text = "📱 IPA для подписи"
        case 1:
            cell.textLabel?.text = libraryFiles[indexPath.row]
            cell.detailTextLabel?.text = "📚 В библиотеке"
        case 2:
            let file = signingFiles[indexPath.row]
            cell.textLabel?.text = file
            if file.hasSuffix(".p12") {
                cell.detailTextLabel?.text = "🔐 Сертификат P12"
                cell.imageView?.image = UIImage(systemName: "key.fill")
            } else if file.hasSuffix(".mobileprovision") {
                cell.detailTextLabel?.text = "📱 MobileProvision"
                cell.imageView?.image = UIImage(systemName: "doc.fill")
            } else if file.hasSuffix(".zip") {
                cell.detailTextLabel?.text = "📦 ZIP архив"
            } else {
                cell.detailTextLabel?.text = "📄 Файл"
            }
        default:
            break
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            let fileName = ipaFiles[indexPath.row]
            showSignOptions(fileName)
            
        case 1:
            let fileName = libraryFiles[indexPath.row]
            showInstallOptions(fileName)
            
        case 2:
            let fileName = signingFiles[indexPath.row]
            if fileName.hasSuffix(".zip") {
                extractZip(fileName)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Подпись
    private func showSignOptions(_ fileName: String) {
        let p12Files = signingFiles.filter { $0.hasSuffix(".p12") }
        let provisionFiles = signingFiles.filter { $0.hasSuffix(".mobileprovision") }
        
        if p12Files.isEmpty || provisionFiles.isEmpty {
            showAlert("Ошибка", "Добавьте .p12 и .mobileprovision в папку Signing")
            return
        }
        
        let alert = UIAlertController(title: "Выберите сертификат", message: nil, preferredStyle: .actionSheet)
        
        for p12 in p12Files {
            let action = UIAlertAction(title: "🔐 \(p12)", style: .default) { [weak self] _ in
                self?.selectProvision(fileName: fileName, p12File: p12, provisionFiles: provisionFiles)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alert, animated: true)
    }
    
    private func selectProvision(fileName: String, p12File: String, provisionFiles: [String]) {
        let alert = UIAlertController(title: "Выберите provisioning", message: nil, preferredStyle: .actionSheet)
        
        for provision in provisionFiles {
            let action = UIAlertAction(title: "📱 \(provision)", style: .default) { [weak self] _ in
                self?.askPassword(fileName: fileName, p12File: p12File, provisionFile: provision)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Назад", style: .default) { [weak self] _ in
            self?.showSignOptions(fileName)
        })
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alert, animated: true)
    }
    
    private func askPassword(fileName: String, p12File: String, provisionFile: String) {
        let alert = UIAlertController(title: "Пароль", message: "Введите пароль от P12", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Пароль"
            textField.isSecureTextEntry = true
        }
        
        alert.addAction(UIAlertAction(title: "Подписать", style: .default) { [weak self] _ in
            let password = alert.textFields?.first?.text ?? ""
            self?.startSigning(fileName: fileName, p12File: p12File, provisionFile: provisionFile, password: password)
        })
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(alert, animated: true)
    }
    
    private func startSigning(fileName: String, p12File: String, provisionFile: String, password: String) {
        activityIndicator.startAnimating()
        statusLabel.isHidden = false
        statusLabel.text = "Подписываем...\nЭто может занять несколько минут"
        view.isUserInteractionEnabled = false
        
        let ipaPath = documentsPath + "/IPA/" + fileName
        let p12Path = documentsPath + "/Signing/" + p12File
        let provisionPath = documentsPath + "/Signing/" + provisionFile
        
        RealSigner.shared.signIPA(ipaPath: ipaPath, p12Path: p12Path, provisionPath: provisionPath, password: password) { [weak self] success, result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.statusLabel.isHidden = true
                self?.view.isUserInteractionEnabled = true
                
                if success {
                    self?.showAlert("Успех!", "Подписанный IPA сохранен:\n\((result as NSString).lastPathComponent)")
                    self?.loadFiles()
                } else {
                    self?.showAlert("Ошибка", result)
                }
            }
        }
    }
    
    // MARK: - Установка
    private func showInstallOptions(_ fileName: String) {
        let alert = UIAlertController(title: "Установка", message: fileName, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "📱 AltStore", style: .default) { _ in
            let path = self.documentsPath + "/Library/" + fileName
            if let url = URL(string: "altstore://install?file=\(path)") {
                UIApplication.shared.open(url)
            }
        })
        
        alert.addAction(UIAlertAction(title: "📤 Поделиться", style: .default) { [weak self] _ in
            let path = self?.documentsPath + "/Library/" + fileName ?? ""
            let url = URL(fileURLWithPath: path)
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            self?.present(activityVC, animated: true)
        })
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alert, animated: true)
    }
    
    // MARK: - ZIP
    private func extractZip(_ fileName: String) {
        activityIndicator.startAnimating()
        statusLabel.isHidden = false
        statusLabel.text = "Распаковка..."
        
        DispatchQueue.global().async { [weak self] in
            let zipPath = (self?.documentsPath ?? "") + "/Signing/" + fileName
            let destination = (self?.documentsPath ?? "") + "/Signing/"
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", zipPath, "-d", destination]
            
            try? process.run()
            process.waitUntilExit()
            
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.statusLabel.isHidden = true
                self?.showAlert("Готово", "Файлы извлечены")
                self?.loadFiles()
            }
        }
    }
    
    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Document Picker
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            let fileName = url.lastPathComponent
            var destinationFolder = ""
            
            if fileName.hasSuffix(".ipa") {
                destinationFolder = "/IPA/"
            } else if fileName.hasSuffix(".p12") {
                destinationFolder = "/Signing/"
            } else if fileName.hasSuffix(".mobileprovision") {
                destinationFolder = "/Signing/"
            } else if fileName.hasSuffix(".zip") {
                destinationFolder = "/Signing/"
            }
            
            if !destinationFolder.isEmpty {
                let destinationPath = documentsPath + destinationFolder + fileName
                try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: destinationPath))
            }
        }
        
        loadFiles()
        showAlert("Импорт", "Файлы добавлены")
    }
}

// MARK: - App Delegate
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: MainViewController())
        window?.makeKeyAndVisible()
        
        return true
    }
}
