//
//  ContentView.swift
//  isa
//
//  Created by 维安雨轩 on 2025/04/10.
//

import SwiftUI
import UIKit
import CoreNFC
import Foundation

struct ContentView: View {
    @State private var pinCode: String = ""
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @StateObject private var nfcManager = NFCManager()
    @StateObject private var certificateManager = CertificateDataManager.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [Color.white, Color(UIColor.systemGray6)]),
                                   startPoint: .top,
                                   endPoint: .bottom)
                        .ignoresSafeArea()

                    VStack(spacing: geometry.size.height * 0.03) {
                        // Logo and Title
                        VStack(spacing: geometry.size.height * 0.015) {
                            Image(systemName: "person.text.rectangle.fill")
                                .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.13, weight: .regular))
                                .foregroundColor(.blue)
                                .symbolRenderingMode(.hierarchical)

                            Text("マイナンバー証明書の読み取り")
                                .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.06, weight: .bold))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, geometry.size.height * 0.006)
                        .padding(.bottom, geometry.size.height * 0.03)

                        // Login Section
                        VStack(alignment: .leading, spacing: geometry.size.height * 0.02) {
                            HStack {
                                Text("利用者証明用")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Spacer()

                                Image(systemName: "person")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }

                            Text("利用者証明用電子証明書は、マイナンバーカードに搭載されている、インターネットのウェブサイト等にログインする際に利用する電子証明書です。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(action: {
                                // 利用者証明用電子証明書の読み取り処理を開始
                                promptForPIN()
                            }) {
                                HStack {
                                    Spacer()
                                    Text("利用者証明用証明書の読み取り")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Spacer()

                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.headline)
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
                        }
                        .padding(min(geometry.size.width, geometry.size.height) * 0.05)
                        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                        .cornerRadius(16)
                        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .frame(width: geometry.size.width * 0.9)

                        // Registration Section
                        VStack(alignment: .leading, spacing: geometry.size.height * 0.02) {
                            HStack {
                                Text("署名用")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Spacer()

                                Image(systemName: "pencil.and.scribble")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }

                            Text("署名用電子証明書とは、インターネット等で電子文書を作成・送信する際に利用する電子証明書です。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(action: {
                                // 署名用証明書の読み取り処理を開始
                                promptForSignaturePIN()
                            }) {
                                HStack {
                                    Spacer()
                                    Text("署名用証明書の読み取り")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Spacer()

                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.headline)
                                }
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .shadow(color: Color.orange.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
                        }
                        .padding(min(geometry.size.width, geometry.size.height) * 0.05)
                        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                        .cornerRadius(16)
                        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .frame(width: geometry.size.width * 0.9)

                        // Footer
                        Text("© 2025 Meikenn")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, geometry.size.height * 0.01)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)

                    if nfcManager.isReadingInProgress {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                        ProgressView("読み取り中...")
                            .padding()
                            .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                            .cornerRadius(10)
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .navigationDestination(isPresented: $certificateManager.shouldNavigateToDetail) {
                if certificateManager.isAuthenticationMode {
                    CertificateDetailView(
                        certificateBase64: certificateManager.authenticationCertificateBase64,
                        isAuthenticationMode: true
                    )
                } else {
                    CertificateDetailView(
                        certificateBase64: certificateManager.signatureCertificateBase64,
                        isAuthenticationMode: false
                    )
                }
            }
        }
        .onAppear {
            // ContentViewが表示されたときにすべてのデータをクリア
            certificateManager.clearAllData()
        }
    }

    private func promptForPIN() {
        let alert = UIAlertController(title: "マイナンバーカード認証",
                                     message: "利用者証明用電子証明書の4桁の暗証番号を入力してください",
                                     preferredStyle: .alert)

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
                self.startNFCReading(pin: pin)
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

    private func startNFCReading(pin: String) {
        nfcManager.startReading(pin: pin) { success, message in
            if !success {
                showError(title: "エラー", message: message)
            }
            // 成功の場合は画面遷移が自動的に行われるため、ここでは何もしない
        }
    }

    private func startSignatureReading(pin: String) {
        nfcManager.startSignatureReading(pin: pin) { success, message in
            if !success {
                showError(title: "エラー", message: message)
            }
            // 成功の場合は画面遷移が自動的に行われるため、ここでは何もしない
        }
    }

    private func promptForSignaturePIN() {
        let alert = UIAlertController(title: "マイナンバーカード認証",
                                     message: "署名用電子証明書の暗証番号を入力してください（6～16桁）",
                                     preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "暗証番号（6～16桁）"
            textField.keyboardType = .asciiCapable
            textField.isSecureTextEntry = true
            textField.autocapitalizationType = .allCharacters

            // 添加文本字段委托以限制输入6～16位
            NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: textField, queue: .main) { _ in
                if let text = textField.text, text.count > 16 {
                    textField.text = String(text.prefix(16))
                }
            }
        }

        let cancelAction = UIAlertAction(title: "キャンセル", style: .cancel)

        let okAction = UIAlertAction(title: "読み取り", style: .default) { _ in
            if let pin = alert.textFields?.first?.text, pin.count >= 6 && pin.count <= 16 {
                let uppercasePin = pin.uppercased()
                self.startSignatureReading(pin: uppercasePin)
            } else {
                self.showError(title: "エラー", message: "6～16桁の暗証番号を入力してください")
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

    private func showError(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }
}

// NFCManagerクラスでNFC読み取り処理を管理
class NFCManager: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    private var completionHandler: ((Bool, String) -> Void)?
    private var session: NFCTagReaderSession?
    private var pin: String = ""
    private var isSignatureMode: Bool = false  // 署名用電子証明書を読み取るモードかどうか
    @Published var isReadingInProgress: Bool = false  // 読み取り中かどうかを示す状態

    // 各証明書の読み取りクラスをインスタンス化
    private let authenticationReader = UserAuthenticationCertificateReader()
    private let signatureReader = SignatureCertificateReader()

    func startReading(pin: String, completion: @escaping (Bool, String) -> Void) {
        self.completionHandler = completion
        self.pin = pin
        self.isSignatureMode = false
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

    func startSignatureReading(pin: String, completion: @escaping (Bool, String) -> Void) {
        self.completionHandler = completion
        self.pin = pin
        self.isSignatureMode = true
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

            // マイナンバーカードの認証処理を実行
            if self.isSignatureMode {
                // 署名用証明書を読み取るモード
                self.signatureReader.readCertificate(pin: self.pin, nfcTag: nfcTag, session: session) { success, message in
                    DispatchQueue.main.async {
                        self.isReadingInProgress = false
                    }
                    self.completionHandler?(success, message)
                }
            } else {
                // 認証用証明書を読み取るモード
                self.authenticationReader.readCertificate(pin: self.pin, nfcTag: nfcTag, session: session) { success, message in
                    DispatchQueue.main.async {
                        self.isReadingInProgress = false
                    }
                    self.completionHandler?(success, message)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
