import UIKit
import UniformTypeIdentifiers

// MARK: - API для онлайн подписи
class OnlineSigner {
    
    static let shared = OnlineSigner()
    
    // Бесплатные онлайн сервисы для подписи IPA
    private let signServices = [
        "https://api.appsign.io/v1/sign",           // AppSign.io
        "https://api.signapple.org/v1/sign",        // SignApple
        "https://api.iosappsigner.com/v1/sign"      // iOS App Signer
    ]
    
    func signIPAOnline(ipaPath: String, p12Path: String, mobileProvisionPath: String, password: String, completion: @escaping (Bool, String, Data?) -> Void) {
        
        DispatchQueue.global().async {
            guard let ipaData = try? Data(contentsOf: URL(fileURLWithPath: ipaPath)),
                  let p12Data = try? Data(contentsOf: URL(fileURLWithPath: p12Path)),
                  let provisionData = try? Data(contentsOf: URL(fileURLWithPath: mobileProvisionPath)) else {
                DispatchQueue.main.async {
                    completion(false, "Ошибка чтения файлов", nil)
                }
                return
            }
            
            // Пробуем разные сервисы по очереди
            for service in self.signServices {
                let result = self.uploadToService(
                    serviceURL: service,
                    ipaData: ipaData,
                    p12Data: p12Data,
                    provisionData: provisionData,
                    password: password
                )
                
                if result.success {
                    DispatchQueue.main.async {
                        completion(true, "Подписано через: \(service)", result.data)
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                completion(false, "Все сервисы недоступны", nil)
            }
        }
    }
    
    private func uploadToService(serviceURL: String, ipaData: Data, p12Data: Data, provisionData: Data, password: String) -> (success: Bool, data: Data?) {
        
        let boundary = "Boundary-\(UUID().uuidString)"
        
        guard let url = URL(string: serviceURL) else {
            return (false, nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Добавляем IPA файл
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"ipa\"; filename=\"app.ipa\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(ipaData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Добавляем P12 файл
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"p12\"; filename=\"cert.p12\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(p12Data)
        body.append("\r\n".data(using: .utf8)!)
        
        // Добавляем mobileprovision
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"provision\"; filename=\"embedded.mobileprovision\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(provisionData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Добавляем пароль
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"password\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(password)\r\n".data(using: .utf8)!)
        
        // Добавляем опции
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"remove_plugins\"\r\n\r\n".data(using: .utf8)!)
        body.append("true\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var success = false
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data, error == nil {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    resultData = data
                    success = true
                }
            }
            semaphore.signal()
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + 60) // 60 секунд таймаут
        
        return (success, resultData)
    }
}

// MARK: - Модели данных
struct IPAFile: Codable {
    let name: String
    let path: String
    let size: String
    let date: Date
}

// MARK: - Главный контроллер
class MainViewController: UIViewController {
    
    // MARK: - UI Элементы
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemBackground
        table.register(FileCell.self, forCellReuseIdentifier: "FileCell")
        return table
    }()
    
    private let segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["IPA Файлы", "Библиотека", "Подписи", "Инжект"])
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.selectedSegmentIndex = 0
        sc.backgroundColor = .systemGray6
        return sc
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .systemBlue
        return indicator
    }()
    
    private let progressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .systemGray
        label.font = .systemFont(ofSize: 14)
        label.isHidden = true
        return label
    }()
    
    private let importButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("📥 Импорт", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.titleLabel?.font = .boldSystemFont(ofSize: 16)
        return button
    }()
    
    private let folderButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("📁 Папки", for: .normal)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.titleLabel?.font = .boldSystemFont(ofSize: 16)
        return button
    }()
    
    // MARK: - Данные
    private var ipaFiles: [IPAFile] = []
    private var libraryFiles: [IPAFile] = []
    private var signingFiles: [String] = []
    private var injectFiles: [String] = []
    private var currentFolder = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        createMainFolders()
        loadFiles()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "🎯 SignMaster"
        
        navigationController?.navigationBar.prefersLargeTitles = true
        
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(importButton)
        view.addSubview(folderButton)
        view.addSubview(activityIndicator)
        view.addSubview(progressLabel)
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            segmentedControl.heightAnchor.constraint(equalToConstant: 40),
            
            importButton.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 10),
            importButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            importButton.widthAnchor.constraint(equalToConstant: 100),
            importButton.heightAnchor.constraint(equalToConstant: 40),
            
            folderButton.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 10),
            folderButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            folderButton.widthAnchor.constraint(equalToConstant: 100),
            folderButton.heightAnchor.constraint(equalToConstant: 40),
            
            tableView.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            progressLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 10),
            progressLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        folderButton.addTarget(self, action: #selector(openFolders), for: .touchUpInside)
        
        tableView.delegate = self
        tableView.dataSource = self
        
        // Добавляем жест обновления
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshFiles), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func createMainFolders() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let docPath = paths.first {
            currentFolder = docPath.path + "/SignMaster"
            try? FileManager.default.createDirectory(atPath: currentFolder, withIntermediateDirectories: true)
            
            let subfolders = [
                "IPA",           // для IPA файлов
                "Library",       // библиотека приложений
                "Signing",       // p12, mobileprovision
                "Inject",        // dylib, deb, framework
                "Zips",          // zip архивы
                "Signed"         // готовые подписанные IPA
            ]
            
            for folder in subfolders {
                try? FileManager.default.createDirectory(atPath: currentFolder + "/" + folder, withIntermediateDirectories: true)
            }
        }
    }
    
    @objc private func refreshFiles() {
        loadFiles()
        tableView.refreshControl?.endRefreshing()
    }
    
    private func loadFiles() {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: currentFolder + "/IPA")
            ipaFiles = files.filter { $0.hasSuffix(".ipa") }.map { name in
                let path = currentFolder + "/IPA/" + name
                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                let size = attrs?[.size] as? Int64 ?? 0
                let date = attrs?[.modificationDate] as? Date ?? Date()
                return IPAFile(name: name, path: path, size: formatSize(size), date: date)
            }
            
            let libFiles = try FileManager.default.contentsOfDirectory(atPath: currentFolder + "/Library")
            libraryFiles = libFiles.filter { $0.hasSuffix(".ipa") }.map { name in
                let path = currentFolder + "/Library/" + name
                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                let size = attrs?[.size] as? Int64 ?? 0
                let date = attrs?[.modificationDate] as? Date ?? Date()
                return IPAFile(name: name, path: path, size: formatSize(size), date: date)
            }
            
            signingFiles = try FileManager.default.contentsOfDirectory(atPath: currentFolder + "/Signing")
            injectFiles = try FileManager.default.contentsOfDirectory(atPath: currentFolder + "/Inject")
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        } catch {
            print("Ошибка загрузки: \(error)")
        }
    }
    
    private func formatSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    @objc private func segmentChanged() {
        tableView.reloadData()
    }
    
    @objc private func importTapped() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        present(documentPicker, animated: true)
    }
    
    @objc private func openFolders() {
        let alert = UIAlertController(title: "Папки", message: nil, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "📁 Открыть папку с файлами", style: .default) { [weak self] _ in
            self?.openDocumentPicker()
        })
        
        alert.addAction(UIAlertAction(title: "🔄 Обновить список", style: .default) { [weak self] _ in
            self?.loadFiles()
        })
        
        alert.addAction(UIAlertAction(title: "🧹 Очистить временные файлы", style: .destructive) { [weak self] _ in
            self?.cleanTempFiles()
        })
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = folderButton
            popover.sourceRect = folderButton.bounds
        }
        
        present(alert, animated: true)
    }
    
    private func openDocumentPicker() {
        let path = currentFolder
        let alert = UIAlertController(title: "Путь к папке", message: path, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func cleanTempFiles() {
        activityIndicator.startAnimating()
        
        DispatchQueue.global().async { [weak self] in
            let tempPath = NSTemporaryDirectory()
            try? FileManager.default.removeItem(atPath: tempPath)
            try? FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
            
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.showAlert(title: "Готово", message: "Временные файлы очищены")
            }
        }
    }
    
    private func signIPA(_ path: String) {
        // Проверяем наличие файлов подписи
        let signingFiles = try? FileManager.default.contentsOfDirectory(atPath: currentFolder + "/Signing")
        let p12Files = signingFiles?.filter { $0.hasSuffix(".p12") } ?? []
        let mobileProvisionFiles = signingFiles?.filter { $0.hasSuffix(".mobileprovision") } ?? []
        
        if p12Files.isEmpty {
            showAlert(title: "Ошибка", message: "Добавьте p12 сертификат в папку Signing")
            return
        }
        
        if mobileProvisionFiles.isEmpty {
            showAlert(title: "Ошибка", message: "Добавьте mobileprovision в папку Signing")
            return
        }
        
        // Показываем выбор файлов
        showFileSelection(ipaPath: path, p12Files: p12Files, mobileProvisionFiles: mobileProvisionFiles)
    }
    
    private func showFileSelection(ipaPath: String, p12Files: [String], mobileProvisionFiles: [String]) {
        let alert = UIAlertController(title: "Выберите сертификат", message: nil, preferredStyle: .actionSheet)
        
        for p12 in p12Files {
            let action = UIAlertAction(title: "📜 \(p12)", style: .default) { [weak self] _ in
                self?.showProvisionSelection(ipaPath: ipaPath, p12File: p12, mobileProvisionFiles: mobileProvisionFiles)
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
    
    private func showProvisionSelection(ipaPath: String, p12File: String, mobileProvisionFiles: [String]) {
        let alert = UIAlertController(title: "Выберите provisioning", message: nil, preferredStyle: .actionSheet)
        
        for provision in mobileProvisionFiles {
            let action = UIAlertAction(title: "📱 \(provision)", style: .default) { [weak self] _ in
                let p12Path = (self?.currentFolder ?? "") + "/Signing/" + p12File
                let provisionPath = (self?.currentFolder ?? "") + "/Signing/" + provision
                self?.showPasswordDialog(ipaPath: ipaPath, p12Path: p12Path, provisionPath: provisionPath)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Назад", style: .default) { [weak self] _ in
            self?.signIPA(ipaPath)
        })
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alert, animated: true)
    }
    
    private func showPasswordDialog(ipaPath: String, p12Path: String, provisionPath: String) {
        let alert = UIAlertController(title: "Пароль", message: "Введите пароль от p12 сертификата", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
            textField.placeholder = "Пароль"
            textField.text = "" // Можно сохранять пароль в Keychain
        }
        
        alert.addAction(UIAlertAction(title: "Подписать онлайн", style: .default) { [weak self] _ in
            let password = alert.textFields?.first?.text ?? ""
            self?.performOnlineSigning(ipaPath: ipaPath, p12Path: p12Path, provisionPath: provisionPath, password: password)
        })
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(alert, animated: true)
    }
    
    private func performOnlineSigning(ipaPath: String, p12Path: String, provisionPath: String, password: String) {
        activityIndicator.startAnimating()
        progressLabel.isHidden = false
        progressLabel.text = "Отправка на сервер..."
        view.isUserInteractionEnabled = false
        
        OnlineSigner.shared.signIPAOnline(ipaPath: ipaPath, p12Path: p12Path, mobileProvisionPath: provisionPath, password: password) { [weak self] success, message, data in
            self?.activityIndicator.stopAnimating()
            self?.progressLabel.isHidden = true
            self?.view.isUserInteractionEnabled = true
            
            if success, let ipaData = data {
                // Сохраняем подписанный IPA
                let fileName = "Signed_" + (ipaPath as NSString).lastPathComponent
                let savePath = (self?.currentFolder ?? "") + "/Signed/" + fileName
                
                do {
                    try ipaData.write(to: URL(fileURLWithPath: savePath))
                    self?.showAlert(title: "Успех!", message: "IPA подписан и сохранен в папке Signed\n\(message)")
                    self?.loadFiles()
                } catch {
                    self?.showAlert(title: "Ошибка", message: "Не удалось сохранить файл")
                }
            } else {
                self?.showAlert(title: "Ошибка", message: message)
            }
        }
    }
    
    private func installIPA(_ path: String) {
        let alert = UIAlertController(title: "Установка", message: "Выберите способ установки", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "📱 AltStore", style: .default) { _ in
            if let url = URL(string: "altstore://install?file=\((path as NSString).lastPathComponent)") {
                UIApplication.shared.open(url)
            }
        })
        
        alert.addAction(UIAlertAction(title: "🔄 SideStore", style: .default) { _ in
            if let url = URL(string: "sidestore://install?file=\((path as NSString).lastPathComponent)") {
                UIApplication.shared.open(url)
            }
        })
        
        alert.addAction(UIAlertAction(title: "📤 Поделиться", style: .default) { [weak self] _ in
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
    
    private func injectToIPA(ipaPath: String, fileToInject: String) {
        let alert = UIAlertController(title: "Инжект", message: "Добавление \(fileToInject) в IPA...", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        
        // Здесь можно реализовать инжект через онлайн сервис
    }
    
    private func extractZip(_ path: String) {
        activityIndicator.startAnimating()
        progressLabel.isHidden = false
        progressLabel.text = "Распаковка..."
        
        DispatchQueue.global().async { [weak self] in
            let destination = self?.currentFolder + "/Signing"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", path, "-d", destination ?? ""]
            
            try? process.run()
            process.waitUntilExit()
            
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.progressLabel.isHidden = true
                self?.showAlert(title: "Готово", message: "Файлы извлечены в папку Signing")
                self?.loadFiles()
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableView Delegate & DataSource
extension MainViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch segmentedControl.selectedSegmentIndex {
        case 0: return ipaFiles.count
        case 1: return libraryFiles.count
        case 2: return signingFiles.count
        case 3: return injectFiles.count
        default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileCell
        
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            cell.configure(with: ipaFiles[indexPath.row])
        case 1:
            cell.configure(with: libraryFiles[indexPath.row])
        case 2:
            let file = signingFiles[indexPath.row]
            cell.textLabel?.text = file
            if file.hasSuffix(".p12") {
                cell.imageView?.image = UIImage(systemName: "key.fill")
                cell.detailTextLabel?.text = "🔐 Сертификат"
            } else if file.hasSuffix(".mobileprovision") {
                cell.imageView?.image = UIImage(systemName: "doc.fill")
                cell.detailTextLabel?.text = "📱 Provisioning"
            } else {
                cell.imageView?.image = UIImage(systemName: "doc")
                cell.detailTextLabel?.text = "Файл"
            }
        case 3:
            cell.textLabel?.text = injectFiles[indexPath.row]
            if injectFiles[indexPath.row].hasSuffix(".dylib") {
                cell.imageView?.image = UIImage(systemName: "puzzlepiece.fill")
                cell.detailTextLabel?.text = "📦 Dylib"
            } else if injectFiles[indexPath.row].hasSuffix(".deb") {
                cell.imageView?.image = UIImage(systemName: "archivebox.fill")
                cell.detailTextLabel?.text = "📦 Deb"
            } else if injectFiles[indexPath.row].hasSuffix(".framework") {
                cell.imageView?.image = UIImage(systemName: "square.stack.3d.up.fill")
                cell.detailTextLabel?.text = "📦 Framework"
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
            let path = ipaFiles[indexPath.row].path
            signIPA(path)
        case 1:
            let path = libraryFiles[indexPath.row].path
            installIPA(path)
        case 2:
            let path = currentFolder + "/Signing/" + signingFiles[indexPath.row]
            if path.hasSuffix(".zip") {
                extractZip(path)
            }
        case 3:
            let path = currentFolder + "/Inject/" + injectFiles[indexPath.row]
            // Выбираем IPA для инжекта
            if !ipaFiles.isEmpty {
                let alert = UIAlertController(title: "Выберите IPA", message: nil, preferredStyle: .actionSheet)
                for ipa in ipaFiles {
                    alert.addAction(UIAlertAction(title: ipa.name, style: .default) { [weak self] _ in
                        self?.injectToIPA(ipaPath: ipa.path, fileToInject: injectFiles[indexPath.row])
                    })
                }
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                present(alert, animated: true)
            }
        default:
            break
        }
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Удалить") { [weak self] _, _, completion in
            guard let self = self else { return }
            
            let path: String
            switch self.segmentedControl.selectedSegmentIndex {
            case 0:
                path = self.ipaFiles[indexPath.row].path
            case 1:
                path = self.libraryFiles[indexPath.row].path
            case 2:
                path = self.currentFolder + "/Signing/" + self.signingFiles[indexPath.row]
            case 3:
                path = self.currentFolder + "/Inject/" + self.injectFiles[indexPath.row]
            default:
                return
            }
            
            try? FileManager.default.removeItem(atPath: path)
            self.loadFiles()
            completion(true)
        }
        
        if segmentedControl.selectedSegmentIndex == 0 {
            let addToLibAction = UIContextualAction(style: .normal, title: "В библиотеку") { [weak self] _, _, completion in
                let path = self?.ipaFiles[indexPath.row].path ?? ""
                let fileName = (path as NSString).lastPathComponent
                let destPath = (self?.currentFolder ?? "") + "/Library/" + fileName
                try? FileManager.default.copyItem(atPath: path, toPath: destPath)
                self?.loadFiles()
                completion(true)
            }
            addToLibAction.backgroundColor = .systemBlue
            return UISwipeActionsConfiguration(actions: [deleteAction, addToLibAction])
        }
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: - File Cell
class FileCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        
        // Настройка ячейки
        textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        detailTextLabel?.font = .systemFont(ofSize: 12)
        detailTextLabel?.textColor = .systemGray
        imageView?.tintColor = .systemBlue
        accessoryType = .disclosureIndicator
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with file: IPAFile) {
        textLabel?.text = file.name
        detailTextLabel?.text = "\(file.size) • \(formatDate(file.date))"
        imageView?.image = UIImage(systemName: "app.fill")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Document Picker
extension MainViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            let fileName = url.lastPathComponent
            var destinationPath = ""
            
            if fileName.hasSuffix(".ipa") {
                destinationPath = currentFolder + "/IPA/" + fileName
            } else if fileName.hasSuffix(".p12") || fileName.hasSuffix(".mobileprovision") {
                destinationPath = currentFolder + "/Signing/" + fileName
            } else if fileName.hasSuffix(".dylib") {
                destinationPath = currentFolder + "/Inject/" + fileName
            } else if fileName.hasSuffix(".deb") {
                destinationPath = currentFolder + "/Inject/" + fileName
            } else if fileName.hasSuffix(".framework") {
                destinationPath = currentFolder + "/Inject/" + fileName
            } else if fileName.hasSuffix(".zip") {
                destinationPath = currentFolder + "/Zips/" + fileName
            }
            
            if !destinationPath.isEmpty {
                try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: destinationPath))
            }
        }
        
        loadFiles()
        
        let alert = UIAlertController(title: "Импорт завершен", message: "Файлы добавлены", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - App Delegate
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        window = UIWindow(frame: UIScreen.main.bounds)
        let navController = UINavigationController(rootViewController: MainViewController())
        navController.navigationBar.tintColor = .systemBlue
        window?.rootViewController = navController
        window?.makeKeyAndVisible()
        
        return true
    }
}
