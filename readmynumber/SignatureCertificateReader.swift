import Foundation
import CoreNFC

class SignatureCertificateReader: NSObject {
    private var completionHandler: ((Bool, String) -> Void)?
    private var pin: String = ""
    
    func readCertificate(pin: String, nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, completion: @escaping (Bool, String) -> Void) {
        self.completionHandler = completion
        self.pin = pin
        
        // 公的個人認証APを選択
        selectJPKIAP(nfcTag: nfcTag, session: session)
    }
    
    // 公的個人認証APを選択
    private func selectJPKIAP(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        let selectJPKIAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x04,
            p2Parameter: 0x0C,
            data: Data([0xD3, 0x92, 0xF0, 0x00, 0x26, 0x01, 0x00, 0x00, 0x00, 0x01]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectJPKIAPDU) { data, sw1, sw2, error in
            // エラー処理
            if let error = error {
                session.invalidate(errorMessage: "公的個人認証APの選択に失敗: \(error.localizedDescription)")
                return
            }
            
            // ステータスワードチェック
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "公的個人認証APの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                return
            }
            
            // 署名用PINを選択
            self.selectSignaturePIN(nfcTag: nfcTag, session: session)
        }
    }
    
    // 署名用PINを選択
    private func selectSignaturePIN(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        // 署名用PINを選択 (ファイル識別子が認証用と異なる 00 1B)
        let selectPINAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x1B]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectPINAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "署名用PINの選択に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "署名用PINの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                return
            }
            
            // PINによる認証
            self.verifySignaturePIN(nfcTag: nfcTag, session: session)
        }
    }
    
    // 署名用PINによる認証
    private func verifySignaturePIN(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        // PINをASCII文字列に変換
        let pinData = self.pin.data(using: .ascii)!
        
        // VERIFY PINコマンド作成
        let verifyPINAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0x20,
            p1Parameter: 0x00,
            p2Parameter: 0x80,
            data: pinData,
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: verifyPINAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "PIN検証に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 == 0x90 && sw2 == 0x00 {
                // PIN認証成功
                // 署名用証明書の読み取り
                self.selectSignatureCertificate(nfcTag: nfcTag, session: session)
            } else if sw1 == 0x63 && (sw2 & 0xF0) == 0xC0 {
                // PIN間違い、残りリトライ回数表示
                let retryCount = sw2 & 0x0F
                session.invalidate(errorMessage: "暗証番号が間違っています。残り\(retryCount)回試行できます。")
                self.completionHandler?(false, "暗証番号が間違っています。残り\(retryCount)回試行できます。")
            } else {
                session.invalidate(errorMessage: "PIN検証に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                self.completionHandler?(false, "暗証番号検証に失敗しました。")
            }
        }
    }
    
    // 署名用証明書を選択
    private func selectSignatureCertificate(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        // 署名用証明書を選択 (ファイル識別子が認証用と異なる 00 01)
        let selectCertAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x01]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectCertAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "署名用証明書の選択に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "署名用証明書の選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                return
            }
            
            // 証明書サイズの取得
            self.readSignatureCertificateSize(nfcTag: nfcTag, session: session)
        }
    }
    
    // 署名用証明書サイズの取得
    private func readSignatureCertificateSize(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        // 証明書サイズを読み取る（最初の4バイト）
        let readSizeAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 4)
        
        nfcTag.sendCommand(apdu: readSizeAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "証明書サイズの読み取りに失敗: \(error.localizedDescription)")
                self.completionHandler?(false, "証明書サイズの読み取りに失敗しました。")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 || data.count < 4 {
                session.invalidate(errorMessage: "証明書サイズの読み取りに失敗")
                self.completionHandler?(false, "証明書サイズの読み取りに失敗しました。")
                return
            }
            
            // DER証明書のサイズを計算（ASN.1形式）
            var certificateSize = 0
            if data[0] == 0x30 && data[1] == 0x82 {
                // 長さ部の長さが2バイトの場合
                certificateSize = (Int(data[2]) << 8) | Int(data[3])
                certificateSize += 4  // ヘッダ部分も含める
            } else {
                session.invalidate(errorMessage: "証明書フォーマットが正しくありません")
                self.completionHandler?(false, "証明書フォーマットが正しくありません。")
                return
            }
            
            // 証明書の読み取りを開始
            session.alertMessage = "署名用証明書を読み取り中..."
            self.readSignatureCertificate(nfcTag: nfcTag, session: session, size: certificateSize)
        }
    }
    
    // 署名用証明書の読み取り
    private func readSignatureCertificate(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, size: Int) {
        // 証明書データを格納する変数
        var certificateData = Data()
        let blockSize = 256
        
        // 再帰的に証明書のすべてのブロックを読み取る関数
        func readNextBlock(blockIndex: Int) {
            // ブロックのオフセットを計算
            let blockOffset = blockIndex * blockSize
            
            // 全ブロックを読み終わったら処理を完了
            if blockOffset >= size {
                // 証明書の読み取りが完了
                processSignatureCertificate(certificateData)
                return
            }
            
            // ブロックサイズを調整（最後のブロックは256バイト未満の可能性）
            let requestSize = min(blockSize, size - blockOffset)
            
            // READ BINARYコマンドを作成
            let readBlockAPDU = NFCISO7816APDU(
                instructionClass: 0x00,
                instructionCode: 0xB0,
                p1Parameter: UInt8(blockIndex),
                p2Parameter: 0x00,
                data: Data(),
                expectedResponseLength: requestSize)
            
            nfcTag.sendCommand(apdu: readBlockAPDU) { data, sw1, sw2, error in
                if let error = error {
                    session.invalidate(errorMessage: "証明書の読み取りに失敗: \(error.localizedDescription)")
                    self.completionHandler?(false, "証明書の読み取りに失敗しました。")
                    return
                }
                
                if sw1 != 0x90 || sw2 != 0x00 {
                    session.invalidate(errorMessage: "証明書の読み取りに失敗: ブロック \(blockIndex)")
                    self.completionHandler?(false, "証明書の読み取りに失敗しました。")
                    return
                }
                
                // データを追加
                certificateData.append(data)
                
                // 次のブロックを読み取る
                readNextBlock(blockIndex: blockIndex + 1)
            }
        }
        
        // 署名用証明書を処理する関数
        func processSignatureCertificate(_ certificateData: Data) {
            // コンソールに証明書データを出力
            print("=== 署名用証明書データ（HEX形式） ===")
            print(certificateData.map { String(format: "%02X", $0) }.joined(separator: " "))
            
            // 証明書データをBase64エンコードして出力
            print("=== 署名用証明書データ（Base64形式） ===")
            let base64String = certificateData.base64EncodedString()
            print(base64String)
            
            // 証明書の基本情報（サイズなど）を出力
            print("=== 署名用証明書情報 ===")
            print("サイズ: \(certificateData.count) バイト")
            
            // ASN.1構造の簡易解析
            if certificateData.count > 4 && certificateData[0] == 0x30 {
                print("ASN.1 シーケンス構造を検出")
                if certificateData[1] == 0x82 {
                    let length = (Int(certificateData[2]) << 8) | Int(certificateData[3])
                    print("証明書の長さ: \(length) バイト")
                }
            }
            
            // PKCS#1形式の公開鍵からPKCS#8形式への変換を行う場合のサンプルコード
            print("=== PKCS#1からPKCS#8への変換 ===")
            print("公開鍵変換には、以下のヘッダを追加する必要があります:")
            print("30820122300d06092a864886f70d01010105000382010f00")
            
            // 成功メッセージを表示し、セッションを閉じる
            session.alertMessage = "署名用証明書の読み取りに成功しました。"
            session.invalidate()
            
            // データマネージャーに証明書データを保存して画面遷移をトリガー
            DispatchQueue.main.async {
                CertificateDataManager.shared.setSignatureCertificateData(base64String)
            }
        }
        
        // 最初のブロックから読み取りを開始
        readNextBlock(blockIndex: 0)
    }
    
    // リトライ回数を確認するメソッド
    func checkRetryCount(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        // リトライ回数確認コマンド
        let checkRetryAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0x20,
            p1Parameter: 0x00,
            p2Parameter: 0x80,
            data: Data(),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: checkRetryAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "リトライ回数の確認に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 == 0x63 && (sw2 & 0xF0) == 0xC0 {
                let retryCount = sw2 & 0x0F
                session.alertMessage = "残り試行回数: \(retryCount)回"
            } else {
                session.alertMessage = "リトライ回数の確認に失敗"
            }
        }
    }
} 