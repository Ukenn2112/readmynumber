import Foundation
import CoreNFC

class UserAuthenticationCertificateReader: NSObject {
    private var completionHandler: ((Bool, String) -> Void)?
    private var myNumberCompletionHandler: ((Bool, String) -> Void)?
    private var basicInfoCompletionHandler: ((Bool, [String: String]) -> Void)?
    var pin: String = ""
    
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
            
            // 認証用PINを選択
            self.selectAuthenticationPIN(nfcTag: nfcTag, session: session)
        }
    }
    
    // 認証用PINを選択
    private func selectAuthenticationPIN(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        let selectPINAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x18]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectPINAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "認証用PINの選択に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "認証用PINの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                return
            }
            
            // PINによる認証
            self.verifyPIN(nfcTag: nfcTag, session: session)
        }
    }
    
    // PINによる認証
    private func verifyPIN(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        // PINを数値からASCII文字列に変換
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
                // 認証用証明書の読み取り
                self.selectAuthenticationCertificate(nfcTag: nfcTag, session: session)
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
    
    // 認証用証明書を選択
    private func selectAuthenticationCertificate(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        let selectCertAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x0A]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectCertAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "認証用証明書の選択に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "認証用証明書の選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                return
            }
            
            // 証明書サイズの取得
            self.readCertificateSize(nfcTag: nfcTag, session: session)
        }
    }
    
    // 証明書サイズの取得
    private func readCertificateSize(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
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
            session.alertMessage = "認証情報を読み取り中..."
            self.readCertificate(nfcTag: nfcTag, session: session, size: certificateSize)
        }
    }
    
    // 証明書の読み取り
    private func readCertificate(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, size: Int) {
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
                processCertificate(certificateData)
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
        
        // 証明書を処理する関数
        func processCertificate(_ certificateData: Data) {
            // コンソールに証明書データを出力
            print("=== 証明書データ（HEX形式） ===")
            print(certificateData.map { String(format: "%02X", $0) }.joined(separator: " "))
            
            // 証明書データをBase64エンコードして出力
            print("=== 証明書データ（Base64形式） ===")
            let base64String = certificateData.base64EncodedString()
            print(base64String)
            
            // 証明書の基本情報（サイズなど）を出力
            print("=== 証明書情報 ===")
            print("サイズ: \(certificateData.count) バイト")
            
            // ASN.1構造の簡易解析（実際のアプリではより詳細な解析が必要）
            if certificateData.count > 4 && certificateData[0] == 0x30 {
                print("ASN.1 シーケンス構造を検出")
                if certificateData[1] == 0x82 {
                    let length = (Int(certificateData[2]) << 8) | Int(certificateData[3])
                    print("証明書の長さ: \(length) バイト")
                }
            }
            
            // 証明書の読取り成功を通知して処理を終了
            session.alertMessage = "認証用証明書の読み取りに成功しました。"
            session.invalidate()
            
            // データマネージャーに証明書データを保存
            DispatchQueue.main.async {
                CertificateDataManager.shared.setAuthenticationCertificateData(base64String)
            }
            
            // // 証明書読取り後にマイナンバーと基本4情報も読み取り
            // session.alertMessage = "マイナンバーと基本情報を読み取り中..."
            
            // // 券面入力補助APを選択してマイナンバーを読み取る
            // self.selectCardInputSupportAPForMyNumberAndBasicInfo(nfcTag: nfcTag, session: session, certificateCompleted: true)
        }
        
        // 最初のブロックから読み取りを開始
        readNextBlock(blockIndex: 0)
    }
    
    // マイナンバーと基本4情報を連続して読み取るための処理
    func selectCardInputSupportAPForMyNumberAndBasicInfo(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, certificateCompleted: Bool) {
        // 券面入力補助APを選択
        let selectAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x04,
            p2Parameter: 0x0C,
            data: Data([0xD3, 0x92, 0x10, 0x00, 0x31, 0x00, 0x01, 0x01, 0x04, 0x08]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectAPDU) { data, sw1, sw2, error in
            if let error = error {
                if certificateCompleted {
                    // 証明書は既に読み取り済みなので、エラーでも続行
                    print("券面入力補助APの選択に失敗: \(error.localizedDescription)")
                    session.invalidate(errorMessage: "認証用証明書の読み取りに成功しました。")
                } else {
                    session.invalidate(errorMessage: "券面入力補助APの選択に失敗: \(error.localizedDescription)")
                }
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                if certificateCompleted {
                    // 証明書は既に読み取り済みなので、エラーでも続行
                    print("券面入力補助APの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                    session.invalidate(errorMessage: "認証用証明書の読み取りに成功しました。")
                } else {
                    session.invalidate(errorMessage: "券面入力補助APの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                }
                return
            }
            
            // 券面入力補助用PINを選択
            self.selectCardInputSupportPINForContinuousRead(nfcTag: nfcTag, session: session, certificateCompleted: certificateCompleted)
        }
    }
    
    // 券面入力補助用PINを選択（連続読み取り用）
    private func selectCardInputSupportPINForContinuousRead(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, certificateCompleted: Bool) {
        let selectPINAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x11]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectPINAPDU) { data, sw1, sw2, error in
            if let error = error {
                if certificateCompleted {
                    print("券面入力補助用PINの選択に失敗: \(error.localizedDescription)")
                    session.invalidate(errorMessage: "認証用証明書の読み取りに成功しました。")
                } else {
                    session.invalidate(errorMessage: "券面入力補助用PINの選択に失敗: \(error.localizedDescription)")
                }
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                if certificateCompleted {
                    print("券面入力補助用PINの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                    session.invalidate(errorMessage: "認証用証明書の読み取りに成功しました。")
                } else {
                    session.invalidate(errorMessage: "券面入力補助用PINの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                }
                return
            }
            
            // 券面入力補助用PINによる認証
            self.verifyCardInputSupportPINForContinuousRead(nfcTag: nfcTag, session: session, certificateCompleted: certificateCompleted)
        }
    }
    
    // 券面入力補助用PINによる認証（連続読み取り用）
    private func verifyCardInputSupportPINForContinuousRead(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, certificateCompleted: Bool) {
        // PINを数値からASCII文字列に変換
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
                if certificateCompleted {
                    print("PIN検証に失敗: \(error.localizedDescription)")
                    session.invalidate(errorMessage: "認証用証明書の読み取りに成功しました。")
                } else {
                    session.invalidate(errorMessage: "PIN検証に失敗: \(error.localizedDescription)")
                }
                return
            }
            
            if sw1 == 0x90 && sw2 == 0x00 {
                // PIN認証成功 - まずマイナンバーを読み取り、次に基本4情報を読み取る
                self.selectMyNumberFileForContinuousRead(nfcTag: nfcTag, session: session, certificateCompleted: certificateCompleted)
            } else if sw1 == 0x63 && (sw2 & 0xF0) == 0xC0 {
                // PIN間違い、残りリトライ回数表示
                let retryCount = sw2 & 0x0F
                if certificateCompleted {
                    print("暗証番号が間違っています。残り\(retryCount)回試行できます。")
                    session.invalidate(errorMessage: "認証用証明書の読み取りに成功しました。")
                } else {
                    session.invalidate(errorMessage: "暗証番号が間違っています。残り\(retryCount)回試行できます。")
                }
            } else {
                if certificateCompleted {
                    print("PIN検証に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                    session.invalidate(errorMessage: "認証用証明書の読み取りに成功しました。")
                } else {
                    session.invalidate(errorMessage: "PIN検証に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                }
            }
        }
    }
    
    // マイナンバーファイルを選択（連続読み取り用）
    private func selectMyNumberFileForContinuousRead(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, certificateCompleted: Bool) {
        let selectFileAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x01]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectFileAPDU) { data, sw1, sw2, error in
            if let error = error {
                if certificateCompleted {
                    print("マイナンバーファイルの選択に失敗: \(error.localizedDescription)")
                    session.invalidate(errorMessage: "認証用証明書の読み取りに成功しました。")
                } else {
                    session.invalidate(errorMessage: "マイナンバーファイルの選択に失敗: \(error.localizedDescription)")
                }
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                if certificateCompleted {
                    print("マイナンバーファイルの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                    session.invalidate(errorMessage: "認証用証明書の読み取りに成功しました。")
                } else {
                    session.invalidate(errorMessage: "マイナンバーファイルの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                }
                return
            }
            
            // マイナンバー読み取り
            self.readMyNumberDataForContinuousRead(nfcTag: nfcTag, session: session, certificateCompleted: certificateCompleted)
        }
    }
    
    // マイナンバー読み取り（連続読み取り用）
    private func readMyNumberDataForContinuousRead(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, certificateCompleted: Bool) {
        // 最大長で読み取り試行
        let readBinaryAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 16)  // 16バイトのデータを期待
        
        nfcTag.sendCommand(apdu: readBinaryAPDU) { data, sw1, sw2, error in
            var myNumber = "取得失敗"
            
            if let error = error {
                print("マイナンバーの読み取りに失敗: \(error.localizedDescription)")
            } else if sw1 != 0x90 || sw2 != 0x00 {
                // エラーステータスの詳細なログ出力
                print("マイナンバーの読み取りに失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                
                // ステータス 6700 (誤った長さ) の場合、異なるパラメータで再試行
                if sw1 == 0x67 && sw2 == 0x00 {
                    // より長いレスポンス長で再試行
                    let retryAPDU = NFCISO7816APDU(
                        instructionClass: 0x00,
                        instructionCode: 0xB0,
                        p1Parameter: 0x00,
                        p2Parameter: 0x00,
                        data: Data(),
                        expectedResponseLength: 255)  // 最大長で再試行
                    
                    nfcTag.sendCommand(apdu: retryAPDU) { retryData, retrySw1, retrySw2, retryError in
                        if retrySw1 == 0x90 && retrySw2 == 0x00 && retryData.count >= 15 {
                            // 4～15バイト目がマイナンバー
                            let myNumberData = retryData.subdata(in: 3..<15)
                            if let number = String(data: myNumberData, encoding: .ascii) {
                                myNumber = number
                                print("マイナンバー: \(number)")
                                DispatchQueue.main.async {
                                    CertificateDataManager.shared.setMyNumber(number)
                                }
                            }
                        }
                        
                        // 基本4情報の読み取りへ進む
                        self.selectBasicInfoFileForContinuousRead(nfcTag: nfcTag, session: session, certificateCompleted: certificateCompleted, myNumber: myNumber)
                    }
                    return
                }
            } else if data.count >= 15 {
                // 4～15バイト目がマイナンバー
                let myNumberData = data.subdata(in: 3..<15)
                if let number = String(data: myNumberData, encoding: .ascii) {
                    myNumber = number
                    print("マイナンバー: \(number)")
                    
                    // データ保存
                    DispatchQueue.main.async {
                        CertificateDataManager.shared.setMyNumber(number)
                    }
                }
            }
            
            // 続いて基本4情報を読み取る
            self.selectBasicInfoFileForContinuousRead(nfcTag: nfcTag, session: session, certificateCompleted: certificateCompleted, myNumber: myNumber)
        }
    }
    
    // 基本4情報ファイルを選択（連続読み取り用）
    private func selectBasicInfoFileForContinuousRead(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, certificateCompleted: Bool, myNumber: String) {
        let selectFileAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x02]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectFileAPDU) { data, sw1, sw2, error in
            if let error = error {
                if certificateCompleted {
                    print("基本4情報ファイルの選択に失敗: \(error.localizedDescription)")
                    session.alertMessage = "認証用証明書とマイナンバーの読み取りに成功しました。"
                    session.invalidate()
                } else {
                    session.invalidate(errorMessage: "基本4情報ファイルの選択に失敗: \(error.localizedDescription)")
                }
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                if certificateCompleted {
                    print("基本4情報ファイルの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                    session.alertMessage = "認証用証明書とマイナンバーの読み取りに成功しました。"
                    session.invalidate()
                } else {
                    session.invalidate(errorMessage: "基本4情報ファイルの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                }
                return
            }
            
            // まずデータ長を取得
            self.readBasicInfoLengthForContinuousRead(nfcTag: nfcTag, session: session, certificateCompleted: certificateCompleted, myNumber: myNumber)
        }
    }
    
    // 基本4情報のデータ長を取得（連続読み取り用）
    private func readBasicInfoLengthForContinuousRead(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, certificateCompleted: Bool, myNumber: String) {
        // 全てのデータを一度に読み取る
        self.readBasicInfoDataFullLength(nfcTag: nfcTag, session: session, certificateCompleted: certificateCompleted, myNumber: myNumber)
    }
    
    // 基本4情報を最大長で読み取る（長さ取得に失敗した場合）
    private func readBasicInfoDataFullLength(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, certificateCompleted: Bool, myNumber: String) {
        let readDataAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 255) // 最大長で読み取り
        
        nfcTag.sendCommand(apdu: readDataAPDU) { data, sw1, sw2, error in
            if let error = error {
                if certificateCompleted {
                    print("基本4情報の読み取りに失敗: \(error.localizedDescription)")
                    session.alertMessage = "認証用証明書とマイナンバーの読み取りに成功しました。"
                    session.invalidate()
                } else {
                    session.invalidate(errorMessage: "基本4情報の読み取りに失敗: \(error.localizedDescription)")
                }
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                if certificateCompleted {
                    print("基本4情報の読み取りに失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                    session.alertMessage = "認証用証明書とマイナンバーの読み取りに成功しました。"
                    session.invalidate()
                } else {
                    session.invalidate(errorMessage: "基本4情報の読み取りに失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                }
                return
            }
            
            // 基本4情報を解析
            self.parseBasicInfo(data: data, session: session)
        }
    }
    
    // 基本4情報を解析
    private func parseBasicInfo(data: Data, session: NFCTagReaderSession) {
        var result = [String: String]()
        
        // データの解析
        var index = 0
        
        // FF 20 82 ... というヘッダーパターンをスキップ
        if data.count > 5 && data[0] == 0xFF && data[1] == 0x20 {
            index = 5 // ヘッダー部分をスキップ
        }
        
        // TLV構造を解析
        while index < data.count - 3 { // 最低3バイト必要
            // TLVタグを確認
            if data[index] == 0xDF {
                let tagSecond = data[index + 1]
                let length = Int(data[index + 2])
                
                if index + 3 + length <= data.count {
                    let valueData = data.subdata(in: (index + 3)..<(index + 3 + length))
                    
                    switch tagSecond {
                    case 0x21:
                        // ヘッダー情報 - スキップ
                        break
                    case 0x22:
                        // 氏名
                        if let name = String(data: valueData, encoding: .utf8) {
                            result["name"] = name
                            print("氏名: \(name)")
                        }
                    case 0x23:
                        // 住所
                        if let address = String(data: valueData, encoding: .utf8) {
                            result["address"] = address
                            print("住所: \(address)")
                        }
                    case 0x24:
                        // 生年月日 - YYYYMMDD形式をYYYY年MM月DD日形式に変換
                        if let birthdate = String(data: valueData, encoding: .utf8), birthdate.count == 8 {
                            let year = birthdate.prefix(4)
                            let month = birthdate.dropFirst(4).prefix(2)
                            let day = birthdate.dropFirst(6).prefix(2)
                            let formattedDate = "\(year)年\(month)月\(day)日"
                            result["birthdate"] = formattedDate
                            print("生年月日: \(formattedDate)")
                        }
                    case 0x25:
                        // 性別
                        if valueData.count == 1 {
                            let genderCode = valueData[0]
                            var gender = "不明"
                            switch genderCode {
                            case 0x31: // "1"
                                gender = "男性"
                            case 0x32: // "2"
                                gender = "女性"
                            case 0x33: // "3"
                                gender = "その他"
                            default:
                                gender = "不明"
                            }
                            result["gender"] = gender
                            print("性別: \(gender)")
                        }
                    default:
                        break
                    }
                    
                    // 次のTLVへ
                    index += 3 + length
                } else {
                    break
                }
            } else {
                // 終端またはパディングデータ - 処理終了
                if data[index] == 0xFF {
                    break
                }
                index += 1
            }
        }
        
        // データマネージャーに基本4情報を保存
        if !result.isEmpty {
            DispatchQueue.main.async {
                CertificateDataManager.shared.setBasicInfo(result)
            }
            
            // 読み取り完了メッセージの作成
            var successMessage = "読み取り成功: "
            let items = ["name": "氏名", "address": "住所", "birthdate": "生年月日", "gender": "性別"]
            var readItems: [String] = []
            
            for (key, label) in items {
                if result[key] != nil {
                    readItems.append(label)
                }
            }
            
            successMessage += readItems.joined(separator: "、")
            print(successMessage)
            
            // 全ての読み取りが完了
            session.alertMessage = result.count == 4 
                ? "すべての情報の読み取りに成功しました。" 
                : "一部の情報のみ読み取りに成功しました: \(readItems.joined(separator: "、"))"
            session.invalidate()
        } else {
            print("基本4情報の読み取りに失敗しました。")
            session.alertMessage = "基本4情報の読み取りに失敗しました。"
            session.invalidate()
        }
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
    
    // マイナンバー読み取り機能を追加
    func readMyNumber(pin: String, nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, completion: @escaping (Bool, String) -> Void) {
        self.myNumberCompletionHandler = completion
        self.pin = pin
        
        // 券面入力補助APを選択
        selectCardInputSupportAP(nfcTag: nfcTag, session: session, forMyNumber: true)
    }
    
    // 基本4情報読み取り機能を追加
    func readBasicInfo(pin: String, nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, completion: @escaping (Bool, [String: String]) -> Void) {
        self.basicInfoCompletionHandler = completion
        self.pin = pin
        
        // 券面入力補助APを選択
        selectCardInputSupportAP(nfcTag: nfcTag, session: session, forMyNumber: false)
    }
    
    // 券面入力補助APを選択
    private func selectCardInputSupportAP(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, forMyNumber: Bool) {
        let selectAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x04,
            p2Parameter: 0x0C,
            data: Data([0xD3, 0x92, 0x10, 0x00, 0x31, 0x00, 0x01, 0x01, 0x04, 0x08]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "券面入力補助APの選択に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "券面入力補助APの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                return
            }
            
            // 券面入力補助用PINを選択
            self.selectCardInputSupportPIN(nfcTag: nfcTag, session: session, forMyNumber: forMyNumber)
        }
    }
    
    // 券面入力補助用PINを選択
    private func selectCardInputSupportPIN(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, forMyNumber: Bool) {
        let selectPINAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x11]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectPINAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "券面入力補助用PINの選択に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "券面入力補助用PINの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                return
            }
            
            // 券面入力補助用PINによる認証
            self.verifyCardInputSupportPIN(nfcTag: nfcTag, session: session, forMyNumber: forMyNumber)
        }
    }
    
    // 券面入力補助用PINによる認証
    private func verifyCardInputSupportPIN(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, forMyNumber: Bool) {
        // PINを数値からASCII文字列に変換
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
                if forMyNumber {
                    // マイナンバーファイルを選択
                    self.selectMyNumberFile(nfcTag: nfcTag, session: session)
                } else {
                    // 基本4情報ファイルを選択
                    self.selectBasicInfoFile(nfcTag: nfcTag, session: session)
                }
            } else if sw1 == 0x63 && (sw2 & 0xF0) == 0xC0 {
                // PIN間違い、残りリトライ回数表示
                let retryCount = sw2 & 0x0F
                session.invalidate(errorMessage: "暗証番号が間違っています。残り\(retryCount)回試行できます。")
                if forMyNumber {
                    self.myNumberCompletionHandler?(false, "暗証番号が間違っています。残り\(retryCount)回試行できます。")
                } else {
                    self.basicInfoCompletionHandler?(false, [:])
                }
            } else {
                session.invalidate(errorMessage: "PIN検証に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                if forMyNumber {
                    self.myNumberCompletionHandler?(false, "暗証番号検証に失敗しました。")
                } else {
                    self.basicInfoCompletionHandler?(false, [:])
                }
            }
        }
    }
    
    // マイナンバーファイルを選択
    private func selectMyNumberFile(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        let selectFileAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x01]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectFileAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "マイナンバーファイルの選択に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "マイナンバーファイルの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                return
            }
            
            // マイナンバー読み取り
            self.readMyNumberData(nfcTag: nfcTag, session: session)
        }
    }
    
    // マイナンバー読み取り
    private func readMyNumberData(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        let readBinaryAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: readBinaryAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "マイナンバーの読み取りに失敗: \(error.localizedDescription)")
                self.myNumberCompletionHandler?(false, "マイナンバーの読み取りに失敗しました。")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "マイナンバーの読み取りに失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                self.myNumberCompletionHandler?(false, "マイナンバーの読み取りに失敗しました。")
                return
            }
            
            // マイナンバーデータ処理
            if data.count >= 15 {
                // 4～15バイト目がマイナンバー
                let myNumberData = data.subdata(in: 3..<15)
                if let myNumber = String(data: myNumberData, encoding: .ascii) {
                    session.alertMessage = "マイナンバーの読み取りに成功しました。"
                    session.invalidate()
                    self.myNumberCompletionHandler?(true, myNumber)
                } else {
                    session.invalidate(errorMessage: "マイナンバーのデコードに失敗しました。")
                    self.myNumberCompletionHandler?(false, "マイナンバーのデコードに失敗しました。")
                }
            } else {
                session.invalidate(errorMessage: "マイナンバーデータが不正です。")
                self.myNumberCompletionHandler?(false, "マイナンバーデータが不正です。")
            }
        }
    }
    
    // 基本4情報ファイルを選択
    private func selectBasicInfoFile(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        let selectFileAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x02,
            p2Parameter: 0x0C,
            data: Data([0x00, 0x02]),
            expectedResponseLength: -1)
        
        nfcTag.sendCommand(apdu: selectFileAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "基本4情報ファイルの選択に失敗: \(error.localizedDescription)")
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "基本4情報ファイルの選択に失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                return
            }
            
            // まずデータ長を取得
            self.readBasicInfoLength(nfcTag: nfcTag, session: session)
        }
    }
    
    // 基本4情報のデータ長を取得
    private func readBasicInfoLength(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession) {
        let readLengthAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x00,
            p2Parameter: 0x02,
            data: Data(),
            expectedResponseLength: 1)
        
        nfcTag.sendCommand(apdu: readLengthAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "基本4情報データ長の読み取りに失敗: \(error.localizedDescription)")
                self.basicInfoCompletionHandler?(false, [:])
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 || data.count < 1 {
                session.invalidate(errorMessage: "基本4情報データ長の読み取りに失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                self.basicInfoCompletionHandler?(false, [:])
                return
            }
            
            // データ長を取得して全データを読み取る
            let dataLength = Int(data[0])
            self.readBasicInfoData(nfcTag: nfcTag, session: session, length: dataLength + 3) // ヘッダー部分も含める
        }
    }
    
    // 基本4情報データを読み取る
    private func readBasicInfoData(nfcTag: NFCISO7816Tag, session: NFCTagReaderSession, length: Int) {
        let readDataAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: length)
        
        nfcTag.sendCommand(apdu: readDataAPDU) { data, sw1, sw2, error in
            if let error = error {
                session.invalidate(errorMessage: "基本4情報の読み取りに失敗: \(error.localizedDescription)")
                self.basicInfoCompletionHandler?(false, [:])
                return
            }
            
            if sw1 != 0x90 || sw2 != 0x00 {
                session.invalidate(errorMessage: "基本4情報の読み取りに失敗: ステータス \(String(format: "%02X%02X", sw1, sw2))")
                self.basicInfoCompletionHandler?(false, [:])
                return
            }
            
            // 基本4情報を解析
            self.parseBasicInfo(data: data, session: session)
        }
    }
}

// CertificateDataManagerにマイナンバーと基本4情報のセッターを追加
extension CertificateDataManager {
    func setMyNumber(_ myNumber: String) {
        // マイナンバーをUserDefaultsまたは安全な場所に保存
        UserDefaults.standard.set(myNumber, forKey: "MyNumber")
        UserDefaults.standard.synchronize()
        
        // 必要に応じて通知を送信
        NotificationCenter.default.post(name: Notification.Name("MyNumberDidLoad"), object: nil)
    }
    
    func setBasicInfo(_ basicInfo: [String: String]) {
        // 基本4情報をUserDefaultsまたは安全な場所に保存
        UserDefaults.standard.set(basicInfo, forKey: "BasicInfo")
        UserDefaults.standard.synchronize()
        
        // 必要に応じて通知を送信
        NotificationCenter.default.post(name: Notification.Name("BasicInfoDidLoad"), object: nil)
    }
} 