import SwiftUI

public struct LimitationsView: View {
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("無損原則與技術限制聲明")
                            .font(.title2)
                            .bold()
                        Text("誠實工程揭露：不誇大、不宣稱任意格式均可無損互轉")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // 核心原則
                VStack(alignment: .leading, spacing: 8) {
                    Text("核心三大模式與定義")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text("1. 封裝直通 (Remux / -c copy):")
                                .bold()
                            Text("零重編碼、零畫質損失。僅更換容器包裝（如 MP4 轉 MKV），保證原始位元流 100% 不變。容器不支援時嚴格拒絕。")
                        }
                        HStack(alignment: .top) {
                            Text("2. 像素無損 (Lossless Transcode):")
                                .bold()
                            Text("數學無損重編碼（如 FFV1、8-bit x264 CRF 0）。解碼後每一格像素 1:1 精確一致，體積巨大。若為 ProRes 4444 XQ 則為視覺級極限近似無損（12-bit），非數學像素 1:1 一致。高位深來源請選用 MKV (FFV1)。")
                        }
                        HStack(alignment: .top) {
                            Text("3. 圖片無損 (Lossless Image):")
                                .bold()
                            Text("PNG、TIFF、BMP、WebP Lossless 之間互轉，像素無損並保留 EXIF/ICC。拒絕轉為有損 JPEG。")
                        }
                    }
                    .font(.body)
                    .padding(10)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // 注意事項清單
                VStack(alignment: .leading, spacing: 8) {
                    Text("重要限制與警語")
                        .font(.headline)
                    ForEach(LosslessLimitations.disclaimers, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text(item)
                                .font(.callout)
                        }
                    }
                }
                
                // 容器支援矩陣
                VStack(alignment: .leading, spacing: 8) {
                    Text("容器直通相容矩陣 (Container Support Matrix)")
                        .font(.headline)
                    
                    VStack(spacing: 6) {
                        ForEach(LosslessLimitations.containerSupportMatrix, id: \.container) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.name).bold()
                                    Spacer()
                                    Text("容器: .\(row.container)").font(.caption).foregroundColor(.secondary)
                                }
                                Text("支援視訊: \(row.supportedVideo.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text("支援音訊: \(row.supportedAudio.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text("備註: \(row.notes)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 550, minHeight: 480)
    }
}
