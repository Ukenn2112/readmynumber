import SwiftUI
import UniformTypeIdentifiers
import CoreNFC
import UIKit

struct CertificateDetailView: View {
    let certificateBase64: String
    let isAuthenticationMode: Bool
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @State private var isCopied = false
    @State private var isCertificateCopied = false
    @State private var showingExportSheet = false
    @State private var copiedItemName: String = ""
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @StateObject private var nfcCardInfoManager = NFCCardInfoManager()

    // マイナンバーと基本4情報を取得
    @ObservedObject private var dataManager = CertificateDataManager.shared

    // PEM形式に変換する関数
    private func convertToPEM() -> String {
        let header = "-----BEGIN CERTIFICATE-----\n"
        let footer = "\n-----END CERTIFICATE-----"

        // Base64文字列を64文字ごとに改行を入れる
        var pemContent = ""
        var index = certificateBase64.startIndex
        while index < certificateBase64.endIndex {
            let endIndex = certificateBase64.index(index, offsetBy: 64, limitedBy: certificateBase64.endIndex) ?? certificateBase64.endIndex
            let line = certificateBase64[index..<endIndex]
            pemContent += String(line) + "\n"
            index = endIndex
        }

        return header + pemContent + footer
    }

    // ファイル保存関数
    private func exportPEM() {
        let pemContent = convertToPEM()
        let filename = isAuthenticationMode ? "authentication_certificate.pem" : "signature_certificate.pem"

        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent(filename)

            do {
                try pemContent.write(to: fileURL, atomically: false, encoding: .utf8)
                showingExportSheet = true
            } catch {
                print("ファイルの保存に失敗しました: \(error.localizedDescription)")
            }
        }
    }

    // マイナンバーを4桁ごとに区切る関数
    private func formatMyNumber(_ number: String) -> String {
        var formatted = ""
        var count = 0

        for char in number {
            if count > 0 && count % 4 == 0 {
                formatted += " "
            }
            formatted += String(char)
            count += 1
        }

        return formatted
    }

    // テキストをコピーする関数
    private func copyText(_ text: String, itemName: String) {
        UIPasteboard.general.string = text
        copiedItemName = itemName
        withAnimation {
            isCopied = true
        }

        // 2秒後にコピー状態をリセット
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
                copiedItemName = ""
            }
        }
    }

    init(certificateBase64: String, isAuthenticationMode: Bool = false) {
        self.certificateBase64 = certificateBase64
        self.isAuthenticationMode = isAuthenticationMode
    }

    var body: some View {
        ZStack {
            // 背景グラデーション（スクロール領域の外に配置）
            LinearGradient(
                gradient: Gradient(colors: [Color.white, Color(UIColor.systemGray6)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // メインのスクロール可能な領域
            ScrollView {
                VStack(spacing: 20) {
                    // タイトル
                    Text(isAuthenticationMode ? "利用者証明用証明書" : "署名用証明書")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top, 20)

                    // マイナンバーと基本4情報のカード（認証用証明書モードの場合のみ表示）
                    if isAuthenticationMode {
                        VStack(spacing: 12) {
                            // ヘッダー部分
                            HStack {
                                Image(systemName: "person.text.rectangle.fill")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundColor(Color.blue)
                                    .symbolRenderingMode(.hierarchical)

                                Text("個人情報")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Spacer()

                                Text("マイナンバーカード")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .padding(.bottom, 8)

                            Divider()
                                .background(Color.blue.opacity(0.3))

                            if dataManager.myNumber.isEmpty && dataManager.basicInfo.isEmpty {
                                // 個人情報が未取得の場合、読み取りボタンを表示
                                Button(action: {
                                    promptForPIN()
                                }) {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "creditcard.fill")
                                        Text("券面入力補助の読み取り")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                .padding(.vertical, 10)
                                .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
                            } else {
                                // マイナンバー（特別強調表示）
                                if !dataManager.myNumber.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("マイナンバー")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        HStack(spacing: 15) {
                                            Text(formatMyNumber(dataManager.myNumber))
                                                .font(.title3)
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                                .contextMenu {
                                                    Button(action: {
                                                        copyText(dataManager.myNumber, itemName: "マイナンバー")
                                                    }) {
                                                        Label("コピー", systemImage: "doc.on.doc")
                                                    }
                                                }

                                            Spacer()

                                            Image(systemName: "number.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        copyText(dataManager.myNumber, itemName: "マイナンバー")
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.blue.opacity(0.05))
                                    .cornerRadius(8)
                                    .overlay(
                                        isCopied && copiedItemName == "マイナンバー" ?
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("コピーしました")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                        .padding(6)
                                        .background(Color.white.opacity(0.9))
                                        .cornerRadius(8)
                                        .padding(4)
                                        : nil
                                    )
                                }

                                // 基本4情報のグリッドレイアウト
                                // 氏名
                                if let name = dataManager.basicInfo["name"] {
                                    InfoCardView(title: "氏名", value: name, systemImage: "person.fill")
                                }
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 16) {
                                    // 生年月日
                                    if let birthdate = dataManager.basicInfo["birthdate"] {
                                        InfoCardView(title: "生年月日", value: birthdate, systemImage: "calendar")
                                    }

                                    // 性別
                                    if let gender = dataManager.basicInfo["gender"] {
                                        InfoCardView(title: "性別", value: gender, systemImage: "person.crop.circle")
                                    }
                                }

                                // 住所（フルワイドで表示）
                                if let address = dataManager.basicInfo["address"] {
                                    InfoCardView(title: "住所", value: address, systemImage: "location.fill", isFullWidth: true)
                                }
                            }
                        }
                        .padding()
                        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                        .cornerRadius(16)
                        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    }

                    // 証明書データ表示エリア
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("証明書データ（Base64形式）")
                                .font(.headline)
                                .fontWeight(.bold)

                            Spacer()

                            Button(action: {
                                UIPasteboard.general.string = certificateBase64
                                withAnimation {
                                    isCertificateCopied = true
                                }

                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation {
                                        isCertificateCopied = false
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: isCertificateCopied ? "checkmark" : "doc.on.doc")
                                    Text(isCertificateCopied ? "コピー完了" : "コピー")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isCertificateCopied ? Color.green : (isAuthenticationMode ? Color.blue : Color.orange))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }

                        // 証明書データのテキスト表示 - スクロール可能
                        ScrollView {
                            Text(certificateBase64)
                                .font(.system(.footnote, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color.white)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .cornerRadius(8)
                        }
                        .frame(height: isAuthenticationMode ? 180 : 460)
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                    .cornerRadius(16)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                    // 操作ボタン
                    VStack(spacing: 12) {
                        // PEM形式でエクスポートするボタン
                        Button(action: exportPEM) {
                            HStack {
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                Text("PEM形式でエクスポート")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding()
                            .background(isAuthenticationMode ? Color.blue : Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .shadow(color: (isAuthenticationMode ? Color.blue : Color.orange).opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)

                        // 戻るボタン
                        Button(action: {
                            // データをクリアしてから画面を閉じる
                            dataManager.clearAllData()
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Text("メイン画面に戻る")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()

                                Image(systemName: "arrow.left.circle.fill")
                                    .font(.headline)
                            }
                            .padding()
                            .background(isAuthenticationMode ? Color.blue : Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .shadow(color: (isAuthenticationMode ? Color.blue : Color.orange).opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            
            if nfcCardInfoManager.isReadingInProgress {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                ProgressView("読み取り中...")
                    .padding()
                    .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                    .cornerRadius(10)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingExportSheet) {
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = dir.appendingPathComponent(isAuthenticationMode ? "authentication_certificate.pem" : "signature_certificate.pem")
                ShareSheet(activityItems: [fileURL])
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    private func promptForPIN() {
        let alert = UIAlertController(
            title: "マイナンバーカード認証",
            message: "券面入力補助の4桁の暗証番号を入力してください",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "暗証番号（4桁）"
            textField.keyboardType = .numberPad
            textField.isSecureTextEntry = true

            // 添加文本字段委托以限制输入4位数
            NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: textField, queue: .main) { _ in
                if let text = textField.text, text.count > 4 {
                    textField.text = String(text.prefix(4))
                }
            }
        }

        let cancelAction = UIAlertAction(title: "キャンセル", style: .cancel)

        let okAction = UIAlertAction(title: "読み取り", style: .default) { _ in
            if let pin = alert.textFields?.first?.text, pin.count == 4 {
                self.startCardInfoReading(pin: pin)
            } else {
                self.showError(title: "エラー", message: "4桁の暗証番号を入力してください")
            }
        }

        alert.addAction(cancelAction)
        alert.addAction(okAction)

        // 最新のSwiftUIとUIKitの連携方法を使用
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func startCardInfoReading(pin: String) {
        nfcCardInfoManager.startReading(pin: pin) { success, message in
            if !success {
                self.showError(title: "エラー", message: message)
            }
        }
    }
    
    private func showError(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }
}

// ShareSheet構造体の追加
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// データ保持用のシングルトンオブジェクト
class CertificateDataManager: ObservableObject {
    static let shared = CertificateDataManager()

    @Published var signatureCertificateBase64: String = ""
    @Published var authenticationCertificateBase64: String = ""
    @Published var shouldNavigateToDetail: Bool = false
    @Published var isAuthenticationMode: Bool = false // 認証モードかどうかのフラグ

    @Published var myNumber: String = ""
    @Published var basicInfo: [String: String] = [:]

    private init() {
        // UserDefaultsから保存されている値を読み込む
        if let savedMyNumber = UserDefaults.standard.string(forKey: "MyNumber") {
            self.myNumber = savedMyNumber
        }

        if let savedBasicInfo = UserDefaults.standard.dictionary(forKey: "BasicInfo") as? [String: String] {
            self.basicInfo = savedBasicInfo
        }

        // 通知の購読
        NotificationCenter.default.addObserver(self, selector: #selector(myNumberDidLoad), name: Notification.Name("MyNumberDidLoad"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(basicInfoDidLoad), name: Notification.Name("BasicInfoDidLoad"), object: nil)
    }

    @objc private func myNumberDidLoad() {
        if let savedMyNumber = UserDefaults.standard.string(forKey: "MyNumber") {
            DispatchQueue.main.async {
                self.myNumber = savedMyNumber
            }
        }
    }

    @objc private func basicInfoDidLoad() {
        if let savedBasicInfo = UserDefaults.standard.dictionary(forKey: "BasicInfo") as? [String: String] {
            DispatchQueue.main.async {
                self.basicInfo = savedBasicInfo
            }
        }
    }

    func setSignatureCertificateData(_ base64: String) {
        signatureCertificateBase64 = base64
        isAuthenticationMode = false
        shouldNavigateToDetail = true
    }

    func setAuthenticationCertificateData(_ base64: String) {
        authenticationCertificateBase64 = base64
        isAuthenticationMode = true
        shouldNavigateToDetail = true
    }

    func resetNavigation() {
        shouldNavigateToDetail = false
    }
    
    func clearAllData() {
        // メモリ上のデータをクリア
        signatureCertificateBase64 = ""
        authenticationCertificateBase64 = ""
        myNumber = ""
        basicInfo = [:]
        
        // UserDefaultsからデータを削除
        UserDefaults.standard.removeObject(forKey: "MyNumber")
        UserDefaults.standard.removeObject(forKey: "BasicInfo")
        
        print("データは全てを削除しました")
    }
}

// 個人情報のカード用の補助ビュー
struct InfoCardView: View {
    let title: String
    let value: String
    let systemImage: String
    var isFullWidth: Bool = false
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.blue)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(isFullWidth ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .contextMenu {
                    Button(action: {
                        UIPasteboard.general.string = value
                        withAnimation {
                            isCopied = true
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                isCopied = false
                            }
                        }
                    }) {
                        Label("コピー", systemImage: "doc.on.doc")
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = value
            withAnimation {
                isCopied = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isCopied = false
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            isCopied ?
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("コピーしました")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .padding(6)
            .background(Color.white.opacity(0.9))
            .cornerRadius(8)
            .padding(4)
            : nil
        )
    }
}

// NFCCardInfoManagerクラスでNFC読み取り処理を管理
class NFCCardInfoManager: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    private var completionHandler: ((Bool, String) -> Void)?
    private var session: NFCTagReaderSession?
    private var pin: String = ""
    @Published var isReadingInProgress: Bool = false  // 読み取り中かどうかを示す状態

    // 各証明書の読み取りクラスをインスタンス化
    private let authenticationReader = UserAuthenticationCertificateReader()

    func startReading(pin: String, completion: @escaping (Bool, String) -> Void) {
        self.completionHandler = completion
        self.pin = pin
        self.isReadingInProgress = true  // 読み取り開始時にフラグをON

        // 実際の環境ではこちらを使用
        if NFCTagReaderSession.readingAvailable {
            session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self)
            session?.alertMessage = "マイナンバーカードをデバイスの上部に近づけてください"
            session?.begin()
        } else {
            // NFC非対応デバイスまたはシミュレータの場合
            simulateNFCReading()
        }
    }

    private func simulateNFCReading() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // 本番環境では実際のNFCを使用するため、シミュレータでのみ表示
            DispatchQueue.main.async {
                self.isReadingInProgress = false
            }
            self.completionHandler?(true, "シミュレータ環境では実際のNFC読み取りはスキップされます。")
        }
    }

    // MARK: - NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // セッションがアクティブになった時の処理
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // エラーが発生した場合の処理
        if let readerError = error as? NFCReaderError {
            // ユーザーが手動でキャンセルした場合は何もしない
            if readerError.code == .readerSessionInvalidationErrorUserCanceled {
                // ユーザーがキャンセルした場合は何も表示せずに終了
                DispatchQueue.main.async {
                    self.isReadingInProgress = false  // 読み取りフラグをOFF
                }
                self.session = nil
                return
            }

            // ユーザーキャンセル以外のエラーの場合はエラーメッセージを表示
            if readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead {
                DispatchQueue.main.async {
                    self.isReadingInProgress = false  // 読み取りフラグをOFF
                }
                completionHandler?(false, "NFCの読み取りエラー: \(error.localizedDescription)")
            }
        }

        DispatchQueue.main.async {
            self.isReadingInProgress = false  // 読み取りフラグをOFF
        }
        self.session = nil
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        // タグが検出された場合の処理
        if tags.count > 1 {
            session.alertMessage = "複数のカードが検出されました。1枚だけにしてください。"
            return
        }

        guard let tag = tags.first else {
            session.invalidate(errorMessage: "カードが検出できませんでした。")
            return
        }

        // ISO14443タイプの場合のみ処理
        guard case .iso7816(let nfcTag) = tag else {
            session.invalidate(errorMessage: "マイナンバーカードではありません。")
            return
        }

        // タグに接続
        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: "カードへの接続エラー: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isReadingInProgress = false
                }
                return
            }

            // 券面入力補助APを使ってマイナンバーと基本4情報を読み取り
            // 認証用証明書は読み取らないのでPINを指定して直接呼び出す
            self.authenticationReader.pin = self.pin  // PINを設定
            self.authenticationReader.selectCardInputSupportAPForMyNumberAndBasicInfo(
                nfcTag: nfcTag, 
                session: session, 
                certificateCompleted: false
            )
            
            // NFCセッションが終了したらフラグをOFFにする
            // セッション終了は読み取り処理内で自動的に行われる
            DispatchQueue.main.async {
                self.isReadingInProgress = false
                // 読み取り完了後、UserDefaultsに値がセットされるのでそれを待つ
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !CertificateDataManager.shared.myNumber.isEmpty {
                        self.completionHandler?(true, "個人情報の読み取りが完了しました。")
                    } else {
                        self.completionHandler?(false, "個人情報の読み取りに失敗しました。")
                    }
                }
            }
        }
    }
}

#Preview {
    CertificateDetailView(certificateBase64: "MIICxDCCAaygAwIBAgIJAKnMDmrHiqv8MA0GCSqGSIb3DQEBBQUAMBUxEzARBgNV")
}

#Preview {
    CertificateDetailView(certificateBase64: "MIICxDCCAaygAwIBAgIJAKnMDmrHiqv8MA0GCSqGSIb3DQEBBQUAMBUxEzARBgNV", isAuthenticationMode: true)
    .onAppear {
        let dataManager = CertificateDataManager.shared
        dataManager.myNumber = "123456789012"
        dataManager.basicInfo = [
            "name": "山田 太郎",
            "birthdate": "1990年5月1日",
            "gender": "男性",
            "address": "東京都千代田区霞が関1-1-1 マイナンバーマンション101号室"
        ]
    }
}
